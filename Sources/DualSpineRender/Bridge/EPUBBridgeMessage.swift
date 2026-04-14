import Foundation

/// Messages surfaced to `EPUBReaderView` consumers.
///
/// This enum is a compatibility projection over the new ``ReaderEvent`` channel.
/// Only the cases a host app can usefully react to are exposed; internal
/// boundary and progress-window events stay inside the controller.
public enum EPUBBridgeMessage: Sendable {
    case selectionChanged(SelectionPayload)
    case selectionCleared
    case progressUpdated(ProgressPayload)
    case linkTapped(LinkPayload)
    case contentReady(ContentReadyPayload)
    case imageTapped(ImagePayload)
    case highlightRequest(HighlightRequestPayload)
    case removeHighlightRequest(RemoveHighlightPayload)
    case pageChanged(PagePayload)

    // MARK: - Payloads

    public struct SelectionPayload: Codable, Sendable {
        public let text: String
        public let rangeStart: Int
        public let rangeEnd: Int
        public let rectX: Double
        public let rectY: Double
        public let rectWidth: Double
        public let rectHeight: Double
        public let spineHref: String

        public init(
            text: String,
            rangeStart: Int,
            rangeEnd: Int,
            rectX: Double,
            rectY: Double,
            rectWidth: Double,
            rectHeight: Double,
            spineHref: String
        ) {
            self.text = text
            self.rangeStart = rangeStart
            self.rangeEnd = rangeEnd
            self.rectX = rectX
            self.rectY = rectY
            self.rectWidth = rectWidth
            self.rectHeight = rectHeight
            self.spineHref = spineHref
        }
    }

    public struct ProgressPayload: Codable, Sendable {
        /// Progress within the current spine item. In the new engine this
        /// tracks overall reader progress across the mounted window.
        public let chapterProgress: Double
        public let scrollOffset: Double
        public let contentHeight: Double
        public let isAtEnd: Bool

        public init(
            chapterProgress: Double,
            scrollOffset: Double = 0,
            contentHeight: Double = 0,
            isAtEnd: Bool = false
        ) {
            self.chapterProgress = chapterProgress
            self.scrollOffset = scrollOffset
            self.contentHeight = contentHeight
            self.isAtEnd = isAtEnd
        }
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
}

// MARK: - Projection

extension EPUBBridgeMessage {
    /// Project a new-engine ``ReaderEvent`` into the legacy ``EPUBBridgeMessage``
    /// shape that host applications observe. Returns `nil` for events that
    /// are internal to the engine (boundary, ready).
    static func from(event: ReaderEvent, currentSpineHref: String) -> EPUBBridgeMessage? {
        switch event {
        case .ready, .boundaryReached, .chapterChanged:
            return nil

        case let .progressUpdated(overall, pageIndex, pageCount):
            if let pageIndex, let pageCount, pageCount > 0 {
                let progress = pageCount > 1 ? Double(pageIndex) / Double(pageCount - 1) : 0
                return .pageChanged(PagePayload(
                    currentPage: pageIndex,
                    totalPages: pageCount,
                    progress: progress
                ))
            }
            return .progressUpdated(ProgressPayload(chapterProgress: overall))

        case let .selectionChanged(payload):
            return .selectionChanged(SelectionPayload(
                text: payload.text,
                rangeStart: payload.rangeStart,
                rangeEnd: payload.rangeEnd,
                rectX: payload.rectX,
                rectY: payload.rectY,
                rectWidth: payload.rectWidth,
                rectHeight: payload.rectHeight,
                spineHref: payload.spineHref.isEmpty ? currentSpineHref : payload.spineHref
            ))

        case .selectionCleared:
            return .selectionCleared

        case let .highlightRequested(selection, tintHex):
            _ = selection
            return .highlightRequest(HighlightRequestPayload(tintHex: tintHex))

        case let .removeHighlightRequested(highlightID):
            return .removeHighlightRequest(RemoveHighlightPayload(highlightId: highlightID))

        case let .linkTapped(href, isInternal):
            return .linkTapped(LinkPayload(href: href, isInternal: isInternal))

        case let .imageTapped(src, alt, width, height):
            return .imageTapped(ImagePayload(
                src: src,
                alt: alt,
                naturalWidth: width,
                naturalHeight: height
            ))
        }
    }
}
