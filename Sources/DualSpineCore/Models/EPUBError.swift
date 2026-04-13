import Foundation

/// All errors surfaced by the DualSpine EPUB pipeline.
public enum EPUBError: Error, Sendable, LocalizedError {
    case invalidArchive(URL)
    case containerXMLMissing
    case containerXMLMalformed(String)
    case opfNotFound(String)
    case opfMalformed(String)
    case resourceNotFound(String)
    case encodingFailure(String)
    case tocParsingFailed(String)
    case spineEmpty
    case unsupportedEPUBVersion(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let url):
            "Unable to open EPUB archive at \(url.lastPathComponent)"
        case .containerXMLMissing:
            "META-INF/container.xml not found in archive"
        case .containerXMLMalformed(let detail):
            "container.xml is malformed: \(detail)"
        case .opfNotFound(let path):
            "OPF package document not found at \(path)"
        case .opfMalformed(let detail):
            "OPF package document is malformed: \(detail)"
        case .resourceNotFound(let path):
            "Resource not found in archive: \(path)"
        case .encodingFailure(let path):
            "Unable to decode resource at \(path) as UTF-8"
        case .tocParsingFailed(let detail):
            "Table of contents parsing failed: \(detail)"
        case .spineEmpty:
            "EPUB spine contains no items"
        case .unsupportedEPUBVersion(let version):
            "Unsupported EPUB version: \(version)"
        }
    }
}
