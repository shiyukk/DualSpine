import Foundation

/// A single item from the OPF `<manifest>`.
/// Each item maps an `id` to a content file (XHTML, CSS, image, font, etc.) inside the EPUB.
public struct EPUBManifestItem: Sendable, Identifiable, Hashable {
    /// The `id` attribute from the manifest `<item>`.
    public let id: String

    /// Relative href to the resource within the EPUB archive (relative to OPF directory).
    public let href: String

    /// MIME type declared in the manifest (e.g. `application/xhtml+xml`, `image/jpeg`).
    public let mediaType: String

    /// EPUB 3 properties set (e.g. `nav`, `cover-image`, `scripted`, `svg`, `mathml`).
    public let properties: Set<String>

    public init(id: String, href: String, mediaType: String, properties: Set<String> = []) {
        self.id = id
        self.href = href
        self.mediaType = mediaType
        self.properties = properties
    }

    // MARK: - Convenience queries

    /// Whether this item is the EPUB 3 Navigation Document.
    public var isNavDocument: Bool { properties.contains("nav") }

    /// Whether this item is declared as the cover image.
    public var isCoverImage: Bool { properties.contains("cover-image") }

    /// Whether this item contains scripting.
    public var isScripted: Bool { properties.contains("scripted") }

    /// Whether this item is an XHTML content document.
    public var isContentDocument: Bool {
        mediaType == "application/xhtml+xml" || mediaType == "text/html"
    }

    /// Whether this item is a CSS stylesheet.
    public var isStylesheet: Bool {
        mediaType == "text/css"
    }

    /// Whether this item is an image.
    public var isImage: Bool {
        mediaType.hasPrefix("image/")
    }
}
