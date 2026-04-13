import Foundation
import SwiftSoup
import DualSpineCore

/// Parses EPUB XHTML content into semantically-bounded chunks.
///
/// Unlike naive fixed-size chunking, this chunker respects document structure:
/// - Never splits mid-paragraph
/// - Headers attach to their following content
/// - Short paragraphs are merged to reach the target token count
/// - Tables, blockquotes, and figures are kept as single units
public enum SemanticChunker {

    /// Default target chunk size in estimated tokens.
    /// 512 tokens is the sweet spot for most embedding models.
    public static let defaultTargetTokens = 512

    /// Minimum chunk size — chunks smaller than this get merged with neighbors.
    public static let minimumTokens = 64

    /// Parse all spine items in an EPUB document into semantic chunks.
    ///
    /// - Parameters:
    ///   - document: The parsed EPUB document.
    ///   - readContent: Closure that reads XHTML content for a given archive path.
    ///   - flatTOC: Flattened TOC for section resolution.
    ///   - targetTokens: Target chunk size in estimated tokens.
    public static func chunkDocument(
        _ document: EPUBDocument,
        readContent: (_ archivePath: String) throws -> String,
        flatTOC: [FlatTOCEntry] = [],
        targetTokens: Int = defaultTargetTokens
    ) throws -> BookChunkStore {
        var allChunks: [SemanticChunk] = []
        var globalIndex = 0

        let resolvedSpine = document.package.resolvedSpine

        for (spineIdx, (_, manifestItem)) in resolvedSpine.enumerated() {
            guard manifestItem.isContentDocument else { continue }

            let archivePath = document.archivePath(forHref: manifestItem.href)
            guard let xhtml = try? readContent(archivePath) else { continue }

            let spineChunks = try chunkXHTML(
                xhtml,
                spineIndex: spineIdx,
                spineHref: manifestItem.href,
                flatTOC: flatTOC,
                targetTokens: targetTokens,
                globalIndexStart: globalIndex
            )

            allChunks.append(contentsOf: spineChunks)
            globalIndex += spineChunks.count
        }

        return BookChunkStore(
            bookIdentifier: document.package.metadata.identifier ?? document.title,
            chunks: allChunks
        )
    }

    /// Parse a single XHTML document into semantic chunks.
    public static func chunkXHTML(
        _ xhtml: String,
        spineIndex: Int,
        spineHref: String,
        flatTOC: [FlatTOCEntry] = [],
        targetTokens: Int = defaultTargetTokens,
        globalIndexStart: Int = 0
    ) throws -> [SemanticChunk] {
        let doc = try SwiftSoup.parse(xhtml)
        guard let body = doc.body() else { return [] }

        // Extract raw blocks from the DOM
        var rawBlocks = extractBlocks(from: body, headingAncestry: [])

        // Merge short blocks to reach target size
        let mergedBlocks = mergeShortBlocks(rawBlocks, targetTokens: targetTokens)

        // Resolve TOC section for this spine item
        let tocSectionIndex = flatTOC.firstIndex(where: { entry in
            guard let href = entry.href else { return false }
            return spineHref.contains(href) || href.contains(spineHref)
        })

        // Convert to SemanticChunk values
        var chunks: [SemanticChunk] = []
        var charOffset = 0

        for (i, block) in mergedBlocks.enumerated() {
            let chunk = SemanticChunk(
                spineIndex: spineIndex,
                spineHref: spineHref,
                tocSectionIndex: tocSectionIndex,
                blockType: block.type,
                text: block.text,
                estimatedTokens: estimateTokens(block.text),
                headingAncestry: block.headingAncestry,
                characterOffsetInSpine: charOffset,
                globalIndex: globalIndexStart + i
            )
            chunks.append(chunk)
            charOffset += block.text.count
        }

        return chunks
    }

    // MARK: - Block Extraction

    private struct RawBlock {
        let type: SemanticChunk.BlockType
        let text: String
        let headingAncestry: [String]
    }

    private static func extractBlocks(
        from element: Element,
        headingAncestry: [String]
    ) -> [RawBlock] {
        var blocks: [RawBlock] = []
        var currentAncestry = headingAncestry

        for child in element.children() {
            let tag = child.tagName().lowercased()
            let text = (try? child.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !text.isEmpty else { continue }

            switch tag {
            // Headings — update ancestry and emit as block
            case "h1", "h2", "h3", "h4", "h5", "h6":
                let level = Int(String(tag.last!)) ?? 1
                // Trim ancestry to current level
                if level <= currentAncestry.count {
                    currentAncestry = Array(currentAncestry.prefix(level - 1))
                }
                currentAncestry.append(text)
                blocks.append(RawBlock(type: .heading, text: text, headingAncestry: currentAncestry))

            // Block-level semantic elements
            case "p":
                blocks.append(RawBlock(type: .paragraph, text: text, headingAncestry: currentAncestry))

            case "blockquote":
                // Treat entire blockquote as a single unit (don't recurse into children)
                let fullText = (try? child.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !fullText.isEmpty {
                    blocks.append(RawBlock(type: .blockquote, text: fullText, headingAncestry: currentAncestry))
                }
                continue  // Skip the default child recursion

            case "table":
                blocks.append(RawBlock(type: .table, text: text, headingAncestry: currentAncestry))

            case "figure":
                let caption = (try? child.select("figcaption").text()) ?? text
                blocks.append(RawBlock(type: .figure, text: caption, headingAncestry: currentAncestry))

            case "pre", "code":
                blocks.append(RawBlock(type: .codeBlock, text: text, headingAncestry: currentAncestry))

            case "li":
                blocks.append(RawBlock(type: .listItem, text: text, headingAncestry: currentAncestry))

            // Container elements — recurse
            case "div", "section", "article", "main", "aside", "details", "summary",
                 "ul", "ol", "dl", "header", "footer":
                let childBlocks = extractBlocks(from: child, headingAncestry: currentAncestry)
                blocks.append(contentsOf: childBlocks)
                // Update ancestry from any headings found in children
                if let lastHeading = childBlocks.last(where: { $0.type == .heading }) {
                    currentAncestry = lastHeading.headingAncestry
                }

            // Skip non-content elements
            case "nav", "script", "style", "noscript":
                continue

            default:
                // Unknown element — treat as paragraph if it has text content
                if !text.isEmpty {
                    blocks.append(RawBlock(type: .paragraph, text: text, headingAncestry: currentAncestry))
                }
            }
        }

        return blocks
    }

    // MARK: - Block Merging

    /// Merge short consecutive blocks (especially paragraphs) to approach the target token count.
    /// Headings always attach to the following content block rather than standing alone.
    private static func mergeShortBlocks(
        _ blocks: [RawBlock],
        targetTokens: Int
    ) -> [RawBlock] {
        guard !blocks.isEmpty else { return [] }

        var merged: [RawBlock] = []
        var buffer: [RawBlock] = []
        var bufferTokens = 0

        for block in blocks {
            let tokens = estimateTokens(block.text)

            // Large blocks (tables, long blockquotes) always stand alone
            if tokens >= targetTokens {
                flushBuffer(&buffer, &bufferTokens, into: &merged)
                merged.append(block)
                continue
            }

            // Headings start a new accumulation; blockquotes and tables stand alone
            if block.type == .heading {
                flushBuffer(&buffer, &bufferTokens, into: &merged)
                buffer.append(block)
                bufferTokens += tokens
                continue
            }

            if block.type == .blockquote || block.type == .table
                || block.type == .figure || block.type == .codeBlock {
                flushBuffer(&buffer, &bufferTokens, into: &merged)
                merged.append(block)
                continue
            }

            buffer.append(block)
            bufferTokens += tokens

            // Flush when we've reached the target
            if bufferTokens >= targetTokens {
                flushBuffer(&buffer, &bufferTokens, into: &merged)
            }
        }

        flushBuffer(&buffer, &bufferTokens, into: &merged)
        return merged
    }

    private static func flushBuffer(
        _ buffer: inout [RawBlock],
        _ tokenCount: inout Int,
        into result: inout [RawBlock]
    ) {
        guard !buffer.isEmpty else { return }

        if buffer.count == 1 {
            result.append(buffer[0])
        } else {
            let mergedText = buffer.map(\.text).joined(separator: "\n\n")
            let ancestry = buffer.last(where: { !$0.headingAncestry.isEmpty })?.headingAncestry ?? []
            result.append(RawBlock(
                type: .mergedParagraphs,
                text: mergedText,
                headingAncestry: ancestry
            ))
        }

        buffer.removeAll()
        tokenCount = 0
    }

    // MARK: - Token Estimation

    /// Rough token estimate: word count × 1.3 (accounts for subword tokenization).
    static func estimateTokens(_ text: String) -> Int {
        let wordCount = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        return max(Int(Double(wordCount) * 1.3), 1)
    }
}
