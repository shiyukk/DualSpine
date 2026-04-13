import Foundation
import DualSpineCore

/// Thread-safe resource provider for serving EPUB content to WKWebView.
/// Wraps `EPUBArchive` in actor isolation so the scheme handler can safely
/// read resources from any thread WebKit dispatches on.
public actor EPUBResourceActor {
    private var archive: EPUBArchive?
    private let archiveURL: URL
    private let contentBasePath: String

    public init(archiveURL: URL, contentBasePath: String) {
        self.archiveURL = archiveURL
        self.contentBasePath = contentBasePath
    }

    /// Read a resource from the EPUB archive.
    /// The path should be relative to the content base (e.g. `"chapter1.xhtml"`).
    public func readResource(at relativePath: String) throws -> (data: Data, mimeType: String) {
        if archive == nil {
            archive = try EPUBArchive(at: archiveURL)
        }

        let archivePath: String
        if relativePath.hasPrefix(contentBasePath) {
            archivePath = relativePath
        } else {
            archivePath = contentBasePath + relativePath
        }

        let data = try archive!.readData(at: archivePath)
        let mime = EPUBArchive.mimeType(for: relativePath)
        return (data, mime)
    }

    /// Read raw data at an absolute archive path (used for cover images, etc.).
    public func readRawData(at archivePath: String) throws -> Data {
        if archive == nil {
            archive = try EPUBArchive(at: archiveURL)
        }
        return try archive!.readData(at: archivePath)
    }

    /// Release the underlying archive to free memory.
    public func close() {
        archive = nil
    }
}
