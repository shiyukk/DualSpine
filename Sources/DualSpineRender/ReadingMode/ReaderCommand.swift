import Foundation

/// A typed command sent from Swift to the JS reader controller.
///
/// All commands are encoded as JSON with a discriminator (`type`) field and
/// a case-specific `payload`. The JS side parses and routes to the active
/// ``LayoutEngine``.
///
/// ```json
/// {"type":"mountChapters","payload":{"chapters":[...], "anchor":{...}}}
/// ```
public enum ReaderCommand: Sendable {
    /// Switch between scroll and paginated modes. The active layout unmounts
    /// and a new one mounts with the provided anchor.
    case setMode(mode: ModeDescriptor, anchor: ReadingAnchor)

    /// Replace the mounted chapter window. Used on initial load and whenever
    /// Swift-side windowed loading adds or removes chapters.
    case mountChapters(chapters: [ChapterContent], anchor: ReadingAnchor)

    /// Navigate to a specific anchor within the currently mounted window.
    /// If the target chapter is not mounted, the JS side emits a
    /// ``ReaderEvent/boundaryReached(direction:)`` so Swift can mount it.
    case navigate(anchor: ReadingAnchor)

    /// Turn to the next page (paginated) or emit a boundary event (scroll).
    case nextPage

    /// Turn to the previous page (paginated) or emit a boundary event (scroll).
    case prevPage

    /// Apply highlight overlays.
    case applyHighlights([HighlightCommand])

    /// Remove a single highlight by ID.
    case removeHighlight(id: String)

    /// Replace the theme stylesheet contents.
    case applyTheme(css: String)

    /// Set individual CSS variables on the reader root.
    case updateStyle(variables: [String: String])

    /// Set the current spine href for selection payload context.
    case setSpineHref(href: String)

    /// Show the floating highlight color picker anchored to the current
    /// selection.
    case showHighlightPicker

    /// Tear down the current layout engine.
    case unmount

    // MARK: - Payloads

    public struct ModeDescriptor: Codable, Sendable, Hashable {
        /// `"scroll"` or `"paginated"`.
        public let mode: String
        /// `"slide"` or `"fade"`. Ignored for scroll mode.
        public let transition: String?

        public init(mode: String, transition: String? = nil) {
            self.mode = mode
            self.transition = transition
        }

        public static let scroll = ModeDescriptor(mode: "scroll")
        public static let paginatedSlide = ModeDescriptor(mode: "paginated", transition: "slide")
        public static let paginatedFade = ModeDescriptor(mode: "paginated", transition: "fade")
    }

    public struct HighlightCommand: Codable, Sendable, Hashable {
        public let id: String
        public let spineIndex: Int
        public let rangeStart: Int
        public let rangeEnd: Int
        public let color: String

        public init(id: String, spineIndex: Int, rangeStart: Int, rangeEnd: Int, color: String) {
            self.id = id
            self.spineIndex = spineIndex
            self.rangeStart = rangeStart
            self.rangeEnd = rangeEnd
            self.color = color
        }
    }
}

// MARK: - Encoding

extension ReaderCommand: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    private enum PayloadKind: String {
        case setMode
        case mountChapters
        case navigate
        case nextPage
        case prevPage
        case applyHighlights
        case removeHighlight
        case applyTheme
        case updateStyle
        case setSpineHref
        case showHighlightPicker
        case unmount
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .setMode(mode, anchor):
            try container.encode(PayloadKind.setMode.rawValue, forKey: .type)
            try container.encode(SetModePayload(mode: mode, anchor: anchor), forKey: .payload)
        case let .mountChapters(chapters, anchor):
            try container.encode(PayloadKind.mountChapters.rawValue, forKey: .type)
            try container.encode(MountPayload(chapters: chapters, anchor: anchor), forKey: .payload)
        case let .navigate(anchor):
            try container.encode(PayloadKind.navigate.rawValue, forKey: .type)
            try container.encode(NavigatePayload(anchor: anchor), forKey: .payload)
        case .nextPage:
            try container.encode(PayloadKind.nextPage.rawValue, forKey: .type)
            try container.encode(EmptyPayload(), forKey: .payload)
        case .prevPage:
            try container.encode(PayloadKind.prevPage.rawValue, forKey: .type)
            try container.encode(EmptyPayload(), forKey: .payload)
        case let .applyHighlights(highlights):
            try container.encode(PayloadKind.applyHighlights.rawValue, forKey: .type)
            try container.encode(HighlightsPayload(highlights: highlights), forKey: .payload)
        case let .removeHighlight(id):
            try container.encode(PayloadKind.removeHighlight.rawValue, forKey: .type)
            try container.encode(RemoveHighlightPayload(id: id), forKey: .payload)
        case let .applyTheme(css):
            try container.encode(PayloadKind.applyTheme.rawValue, forKey: .type)
            try container.encode(ThemePayload(css: css), forKey: .payload)
        case let .updateStyle(variables):
            try container.encode(PayloadKind.updateStyle.rawValue, forKey: .type)
            try container.encode(StylePayload(variables: variables), forKey: .payload)
        case let .setSpineHref(href):
            try container.encode(PayloadKind.setSpineHref.rawValue, forKey: .type)
            try container.encode(SpineHrefPayload(href: href), forKey: .payload)
        case .showHighlightPicker:
            try container.encode(PayloadKind.showHighlightPicker.rawValue, forKey: .type)
            try container.encode(EmptyPayload(), forKey: .payload)
        case .unmount:
            try container.encode(PayloadKind.unmount.rawValue, forKey: .type)
            try container.encode(EmptyPayload(), forKey: .payload)
        }
    }

    private struct EmptyPayload: Encodable {}

    private struct SetModePayload: Encodable {
        let mode: ModeDescriptor
        let anchor: ReadingAnchor
    }

    private struct MountPayload: Encodable {
        let chapters: [ChapterContent]
        let anchor: ReadingAnchor
    }

    private struct NavigatePayload: Encodable {
        let anchor: ReadingAnchor
    }

    private struct HighlightsPayload: Encodable {
        let highlights: [HighlightCommand]
    }

    private struct RemoveHighlightPayload: Encodable {
        let id: String
    }

    private struct ThemePayload: Encodable {
        let css: String
    }

    private struct StylePayload: Encodable {
        let variables: [String: String]
    }

    private struct SpineHrefPayload: Encodable {
        let href: String
    }
}

// MARK: - JSON

extension ReaderCommand {
    /// Render this command as a compact JSON string suitable for embedding
    /// in a single `evaluateJavaScript` call.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                self,
                EncodingError.Context(codingPath: [], debugDescription: "JSON not UTF-8")
            )
        }
        return string
    }
}
