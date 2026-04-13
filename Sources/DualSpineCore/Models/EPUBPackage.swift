import Foundation

/// The fully parsed OPF package document — metadata, manifest, and spine.
public struct EPUBPackage: Sendable {
    public let metadata: EPUBMetadata
    public let manifest: [String: EPUBManifestItem]  // id → item
    public let spine: [EPUBSpineItem]
    public let version: EPUBVersion

    /// Relative path of the NCX file (EPUB 2) declared via `<spine toc="...">`.
    public let ncxHref: String?

    public init(
        metadata: EPUBMetadata,
        manifest: [String: EPUBManifestItem],
        spine: [EPUBSpineItem],
        version: EPUBVersion,
        ncxHref: String? = nil
    ) {
        self.metadata = metadata
        self.manifest = manifest
        self.spine = spine
        self.version = version
        self.ncxHref = ncxHref
    }

    // MARK: - Resolved queries

    /// Spine items paired with their manifest entries, in reading order.
    public var resolvedSpine: [(spine: EPUBSpineItem, manifest: EPUBManifestItem)] {
        spine.compactMap { spineItem in
            guard let manifestItem = manifest[spineItem.manifestRef] else { return nil }
            return (spineItem, manifestItem)
        }
    }

    /// Ordered list of content document hrefs in reading order.
    public var readingOrderHrefs: [String] {
        resolvedSpine.map(\.manifest.href)
    }

    /// The EPUB 3 Navigation Document, if declared in the manifest.
    public var navDocument: EPUBManifestItem? {
        manifest.values.first(where: \.isNavDocument)
    }

    /// The cover image manifest item, resolved via EPUB 3 properties or EPUB 2 meta fallback.
    public var coverImage: EPUBManifestItem? {
        if let epub3Cover = manifest.values.first(where: \.isCoverImage) {
            return epub3Cover
        }
        if let coverID = metadata.coverMetaID {
            return manifest[coverID]
        }
        return nil
    }

    /// Look up a manifest item by its href (normalized, case-insensitive comparison).
    public func manifestItem(forHref href: String) -> EPUBManifestItem? {
        let normalized = href.lowercased()
        return manifest.values.first { $0.href.lowercased() == normalized }
    }
}

// MARK: - EPUB Version

public enum EPUBVersion: Sendable, Hashable {
    case epub2
    case epub3
    case epub31
    case epub32
    case epub33
    case unknown(String)

    public init(versionString: String) {
        switch versionString {
        case "2.0": self = .epub2
        case "3.0": self = .epub3
        case "3.1": self = .epub31
        case "3.2": self = .epub32
        case "3.3": self = .epub33
        default: self = .unknown(versionString)
        }
    }

    public var isEPUB3OrLater: Bool {
        switch self {
        case .epub2, .unknown: return false
        case .epub3, .epub31, .epub32, .epub33: return true
        }
    }
}
