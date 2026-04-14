import Foundation

/// A typed event posted from the JS reader controller back to Swift via
/// `WKScriptMessageHandler`.
///
/// Events are JSON with a discriminator (`type`) and a case-specific `payload`:
///
/// ```json
/// {"type":"progressUpdated","payload":{"overall":0.42,"pageIndex":3,"pageCount":18}}
/// ```
public enum ReaderEvent: Sendable, Equatable {
    /// The reader has mounted and is ready to receive commands.
    case ready

    /// The currently focused chapter changed (scroll mode) or the user turned
    /// past a chapter boundary (paginated mode).
    case chapterChanged(spineIndex: Int)

    /// Reading progress changed. `overall` is `0...1` across all mounted
    /// chapters. `pageIndex` and `pageCount` are present only in paginated
    /// mode.
    case progressUpdated(overall: Double, pageIndex: Int?, pageCount: Int?)

    /// The user navigated past the currently mounted window. Swift should
    /// load the adjacent chapter and re-issue ``ReaderCommand/mountChapters(chapters:anchor:)``.
    ///
    /// - Parameter direction: `"start"` (before window) or `"end"` (after window).
    case boundaryReached(direction: String, spineIndex: Int)

    /// Selection payload changed.
    case selectionChanged(SelectionPayload)

    /// Selection cleared.
    case selectionCleared

    /// User picked a color in the floating highlight picker.
    case highlightRequested(selection: SelectionPayload, tintHex: String)

    /// User tapped "Remove Highlight" on an existing highlight.
    case removeHighlightRequested(highlightID: String)

    /// A link in the content was tapped.
    case linkTapped(href: String, isInternal: Bool)

    /// An image was tapped (e.g. for zoom).
    case imageTapped(src: String, alt: String?, naturalWidth: Int, naturalHeight: Int)

    // MARK: - Payloads

    public struct SelectionPayload: Codable, Sendable, Hashable {
        public let text: String
        public let rangeStart: Int
        public let rangeEnd: Int
        public let rectX: Double
        public let rectY: Double
        public let rectWidth: Double
        public let rectHeight: Double
        public let spineIndex: Int
        public let spineHref: String
        /// Non-empty when the selection lies inside an existing highlight.
        public let highlightID: String

        public init(
            text: String,
            rangeStart: Int,
            rangeEnd: Int,
            rectX: Double,
            rectY: Double,
            rectWidth: Double,
            rectHeight: Double,
            spineIndex: Int,
            spineHref: String,
            highlightID: String = ""
        ) {
            self.text = text
            self.rangeStart = rangeStart
            self.rangeEnd = rangeEnd
            self.rectX = rectX
            self.rectY = rectY
            self.rectWidth = rectWidth
            self.rectHeight = rectHeight
            self.spineIndex = spineIndex
            self.spineHref = spineHref
            self.highlightID = highlightID
        }

        private enum CodingKeys: String, CodingKey {
            case text, rangeStart, rangeEnd, rectX, rectY, rectWidth, rectHeight
            case spineIndex, spineHref
            case highlightID = "highlightId"
        }
    }
}

// MARK: - Decoding

extension ReaderEvent {
    /// Parse a raw JS message body (`[String: Any]` from `WKScriptMessage.body`).
    public static func parse(from body: Any) -> ReaderEvent? {
        guard let dict = body as? [String: Any],
              let type = dict["type"] as? String
        else { return nil }

        let payload = dict["payload"] as? [String: Any] ?? [:]

        switch type {
        case "ready":
            return .ready

        case "chapterChanged":
            guard let index = payload["spineIndex"] as? Int else { return nil }
            return .chapterChanged(spineIndex: index)

        case "progressUpdated":
            guard let overall = payload["overall"] as? Double else { return nil }
            let pageIndex = payload["pageIndex"] as? Int
            let pageCount = payload["pageCount"] as? Int
            return .progressUpdated(overall: overall, pageIndex: pageIndex, pageCount: pageCount)

        case "boundaryReached":
            guard let direction = payload["direction"] as? String,
                  let index = payload["spineIndex"] as? Int else { return nil }
            return .boundaryReached(direction: direction, spineIndex: index)

        case "selectionChanged":
            guard let selection = decode(SelectionPayload.self, from: payload) else { return nil }
            return .selectionChanged(selection)

        case "selectionCleared":
            return .selectionCleared

        case "highlightRequested":
            guard
                let tintHex = payload["tintHex"] as? String,
                let selection = decode(SelectionPayload.self, from: payload["selection"] as? [String: Any] ?? [:])
            else { return nil }
            return .highlightRequested(selection: selection, tintHex: tintHex)

        case "removeHighlightRequested":
            guard let highlightID = payload["highlightId"] as? String else { return nil }
            return .removeHighlightRequested(highlightID: highlightID)

        case "linkTapped":
            guard let href = payload["href"] as? String else { return nil }
            let isInternal = payload["isInternal"] as? Bool ?? false
            return .linkTapped(href: href, isInternal: isInternal)

        case "imageTapped":
            guard let src = payload["src"] as? String else { return nil }
            return .imageTapped(
                src: src,
                alt: payload["alt"] as? String,
                naturalWidth: payload["naturalWidth"] as? Int ?? 0,
                naturalHeight: payload["naturalHeight"] as? Int ?? 0
            )

        default:
            return nil
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from payload: [String: Any]) -> T? {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
