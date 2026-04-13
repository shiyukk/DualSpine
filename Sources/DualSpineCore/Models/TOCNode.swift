import Foundation

/// A node in the EPUB table of contents hierarchy.
/// Supports both EPUB 2 (NCX) and EPUB 3 (Navigation Document) sources.
public struct TOCNode: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public let title: String
    public let href: String?
    public let fragmentID: String?
    public let children: [TOCNode]
    public let level: Int

    public init(
        id: UUID = UUID(),
        title: String,
        href: String? = nil,
        fragmentID: String? = nil,
        children: [TOCNode] = [],
        level: Int = 0
    ) {
        self.id = id
        self.title = title
        self.href = href
        self.fragmentID = fragmentID
        self.children = children
        self.level = level
    }

    /// Recursively flatten the hierarchy into an ordered list with level metadata.
    public func flattened() -> [FlatTOCEntry] {
        var result: [FlatTOCEntry] = []
        var ordinal = 0
        flattenRecursive(into: &result, ordinal: &ordinal)
        return result
    }

    private func flattenRecursive(into result: inout [FlatTOCEntry], ordinal: inout Int) {
        let entry = FlatTOCEntry(
            title: title,
            href: href,
            fragmentID: fragmentID,
            level: level,
            index: ordinal
        )
        result.append(entry)
        ordinal += 1

        for child in children {
            child.flattenRecursive(into: &result, ordinal: &ordinal)
        }
    }
}

/// A flattened TOC entry suitable for UI display (list/outline views).
public struct FlatTOCEntry: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public let title: String
    public let href: String?
    public let fragmentID: String?
    public let level: Int
    public let index: Int

    public init(
        id: UUID = UUID(),
        title: String,
        href: String? = nil,
        fragmentID: String? = nil,
        level: Int = 0,
        index: Int = 0
    ) {
        self.id = id
        self.title = title
        self.href = href
        self.fragmentID = fragmentID
        self.level = level
        self.index = index
    }

    /// Indented display title for hierarchical outline rendering.
    public var displayTitle: String {
        let indent = String(repeating: "  ", count: level)
        return indent + title
    }
}
