import Foundation
import ZIPFoundation

/// Thread-safe, read-only accessor for resources inside an EPUB ZIP archive.
/// This is **not** Sendable — callers that need cross-isolation access should
/// use `EPUBResourceActor` (in DualSpineRender) which wraps this type.
public final class EPUBArchive {
    private let archive: Archive
    public let sourceURL: URL

    public init(at url: URL) throws {
        do {
            self.archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw EPUBError.invalidArchive(url)
        }
        self.sourceURL = url
    }

    /// Read raw bytes for a resource at the given archive-relative path.
    public func readData(at path: String) throws -> Data {
        let normalized = Self.normalizePath(path)
        guard let entry = archive[normalized] else {
            throw EPUBError.resourceNotFound(normalized)
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return data
    }

    /// Read a text resource as a UTF-8 string.
    public func readString(at path: String) throws -> String {
        let data = try readData(at: path)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EPUBError.encodingFailure(path)
        }
        return string
    }

    /// Check whether a resource exists at the given path.
    public func containsEntry(at path: String) -> Bool {
        let normalized = Self.normalizePath(path)
        return archive[normalized] != nil
    }

    /// All entry paths in the archive.
    public var allEntryPaths: [String] {
        archive.map(\.path)
    }

    /// Guess the MIME type for a file path based on its extension.
    public static func mimeType(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        return mimeTypes[ext] ?? "application/octet-stream"
    }

    // MARK: - Private

    private static func normalizePath(_ path: String) -> String {
        var p = path
        if p.hasPrefix("/") { p = String(p.dropFirst()) }
        // Resolve relative components (e.g. "../Styles/style.css" from "Text/chapter1.xhtml")
        // URLComponents handles this for us
        if p.contains("..") || p.contains("./") {
            let components = p.split(separator: "/")
            var resolved: [String] = []
            for component in components {
                if component == ".." {
                    resolved.removeLast()
                } else if component != "." {
                    resolved.append(String(component))
                }
            }
            p = resolved.joined(separator: "/")
        }
        return p
    }

    private static let mimeTypes: [String: String] = [
        "xhtml": "application/xhtml+xml",
        "html": "text/html",
        "htm": "text/html",
        "xml": "application/xml",
        "css": "text/css",
        "js": "application/javascript",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "png": "image/png",
        "gif": "image/gif",
        "svg": "image/svg+xml",
        "webp": "image/webp",
        "avif": "image/avif",
        "ttf": "font/ttf",
        "otf": "font/otf",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "mp3": "audio/mpeg",
        "mp4": "video/mp4",
        "m4a": "audio/mp4",
        "ncx": "application/x-dtbncx+xml",
        "smil": "application/smil+xml",
        "opf": "application/oebps-package+xml",
    ]
}
