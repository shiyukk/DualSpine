import Foundation

/// Messages sent from the JavaScript bridge (`epub-bridge.js`) to Swift
/// via `WKScriptMessageHandler`.
public enum EPUBBridgeMessage: Sendable {

    /// User selected text in the EPUB content.
    case selectionChanged(SelectionPayload)

    /// User cleared their text selection.
    case selectionCleared

    /// Scroll position or reading progress changed.
    case progressUpdated(ProgressPayload)

    /// A link in the content was tapped.
    case linkTapped(LinkPayload)

    /// The content document finished loading and is ready for interaction.
    case contentReady(ContentReadyPayload)

    /// An image in the content was tapped (for zoom/inspection).
    case imageTapped(ImagePayload)

    /// User tapped a highlight color in the floating toolbar (JS-driven).
    case highlightRequest(HighlightRequestPayload)

    /// User tapped "Remove Highlight" in the floating toolbar (JS-driven).
    case removeHighlightRequest(RemoveHighlightPayload)

    /// Page changed in paginated mode.
    case pageChanged(PagePayload)

    /// User tapped previous at the first page of a spine item.
    case paginationAtStart

    /// User tapped next at the last page of a spine item.
    case paginationAtEnd

    // MARK: - Payloads

    public struct SelectionPayload: Codable, Sendable {
        public let text: String
        public let rangeStart: Int
        public let rangeEnd: Int
        public let rectX: Double
        public let rectY: Double
        public let rectWidth: Double
        public let rectHeight: Double
        /// The spine item href where the selection occurred.
        public let spineHref: String
    }

    public struct ProgressPayload: Codable, Sendable {
        /// 0.0–1.0 progress within the current spine item.
        public let chapterProgress: Double
        /// Total vertical scroll offset in points.
        public let scrollOffset: Double
        /// Total content height in points.
        public let contentHeight: Double
        /// Whether the user has scrolled to the end of the current spine item.
        public let isAtEnd: Bool
    }

    public struct LinkPayload: Codable, Sendable {
        public let href: String
        public let isInternal: Bool
    }

    public struct ContentReadyPayload: Codable, Sendable {
        public let spineHref: String
        public let contentHeight: Double
        public let characterCount: Int
    }

    public struct ImagePayload: Codable, Sendable {
        public let src: String
        public let alt: String?
        public let naturalWidth: Int
        public let naturalHeight: Int
    }

    public struct HighlightRequestPayload: Codable, Sendable {
        public let tintHex: String
    }

    public struct RemoveHighlightPayload: Codable, Sendable {
        public let highlightId: String
    }

    public struct PagePayload: Codable, Sendable {
        public let currentPage: Int
        public let totalPages: Int
        public let progress: Double
    }

    // MARK: - Parsing

    /// Parse a raw message dictionary from `WKScriptMessage.body`.
    public static func parse(from body: Any) -> EPUBBridgeMessage? {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String else {
            return nil
        }

        switch type {
        case "selectionChanged":
            guard let payload = decodePayload(SelectionPayload.self, from: dict["payload"]) else {
                return nil
            }
            return .selectionChanged(payload)

        case "selectionCleared":
            return .selectionCleared

        case "progressUpdated":
            guard let payload = decodePayload(ProgressPayload.self, from: dict["payload"]) else {
                return nil
            }
            return .progressUpdated(payload)

        case "linkTapped":
            guard let payload = decodePayload(LinkPayload.self, from: dict["payload"]) else {
                return nil
            }
            return .linkTapped(payload)

        case "contentReady":
            guard let payload = decodePayload(ContentReadyPayload.self, from: dict["payload"]) else {
                return nil
            }
            return .contentReady(payload)

        case "imageTapped":
            guard let payload = decodePayload(ImagePayload.self, from: dict["payload"]) else {
                return nil
            }
            return .imageTapped(payload)

        case "highlightRequest":
            guard let payload = decodePayload(HighlightRequestPayload.self, from: dict["payload"]) else {
                return nil
            }
            return .highlightRequest(payload)

        case "removeHighlightRequest":
            guard let payload = decodePayload(RemoveHighlightPayload.self, from: dict["payload"]) else {
                return nil
            }
            return .removeHighlightRequest(payload)

        case "pageChanged":
            guard let payload = decodePayload(PagePayload.self, from: dict["payload"]) else {
                return nil
            }
            return .pageChanged(payload)

        case "paginationAtStart":
            return .paginationAtStart

        case "paginationAtEnd":
            return .paginationAtEnd

        case "paginationDisabled":
            return nil

        default:
            return nil
        }
    }

    private static func decodePayload<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
        guard let dict = value,
              let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
