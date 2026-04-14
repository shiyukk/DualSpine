#if canImport(UIKit)
import Foundation
import WebKit
import DualSpineCore

/// Single source of truth for the EPUB reading surface.
///
/// The controller owns mode, spine position, and the mounted chapter window.
/// It emits typed ``ReaderCommand`` instances to the JS layout engine and
/// reacts to typed ``ReaderEvent`` instances coming back. All JS dispatch
/// happens through one entry point: `window.__dsReader.dispatch(<JSON>)`.
///
/// ### Actor semantics
///
/// Mutable state lives on this actor. `WKWebView` interaction is gated to
/// `@MainActor` via `MainActor.run` calls so the actor never races WebKit.
public actor ReadingModeController {
    // MARK: - Mode

    /// Rendering mode applied to the current window.
    public enum Mode: Sendable, Equatable {
        case scroll
        case paginated(Transition)

        public var descriptor: ReaderCommand.ModeDescriptor {
            switch self {
            case .scroll: return .scroll
            case .paginated(.slide): return .paginatedSlide
            case .paginated(.fade): return .paginatedFade
            }
        }

        /// Build from the legacy ``EPUBReaderView`` public API fields.
        public static func from(isPaginated: Bool, paginationMode: String) -> Mode {
            guard isPaginated else { return .scroll }
            return paginationMode == "fade" ? .paginated(.fade) : .paginated(.slide)
        }
    }

    /// Paginated-mode page transition style.
    public enum Transition: Sendable, Equatable {
        case slide
        case fade
    }

    // MARK: - State

    /// Observable state projection. Read-only copy for callers that need a
    /// consistent snapshot.
    public struct State: Sendable, Equatable {
        public var mode: Mode
        public var currentSpineIndex: Int
        public var mountedWindow: [Int]
        public var isReady: Bool

        public init(
            mode: Mode = .scroll,
            currentSpineIndex: Int = 0,
            mountedWindow: [Int] = [],
            isReady: Bool = false
        ) {
            self.mode = mode
            self.currentSpineIndex = currentSpineIndex
            self.mountedWindow = mountedWindow
            self.isReady = isReady
        }
    }

    /// Callback fired on the main actor whenever an event is routed back from
    /// the JS layer (after the controller's internal handling).
    public typealias EventObserver = @MainActor @Sendable (ReaderEvent) -> Void

    /// Callback fired on the main actor when the current spine index changes
    /// as a result of user navigation inside the reader (chapter boundaries,
    /// continuous scroll progression). The owning ``EPUBReaderView`` updates
    /// its `spineIndex` binding in response.
    public typealias SpineObserver = @MainActor @Sendable (Int) -> Void

    // MARK: - Configuration

    /// How many chapters on each side of the current spine to keep mounted.
    public static let windowRadius: Int = 3

    // MARK: - Stored state

    private var state: State

    private let document: EPUBDocument
    private let chapterCache: ChapterCache
    private let spineCount: Int

    private weak var webView: WKWebView?

    private var eventObserver: EventObserver?
    private var spineObserver: SpineObserver?

    /// Anchor to seek to once the JS layer signals readiness.
    private var pendingAnchorForReady: ReadingAnchor?

    // MARK: - Init

    public init(
        document: EPUBDocument,
        chapterCache: ChapterCache,
        initialMode: Mode = .scroll,
        initialSpineIndex: Int = 0
    ) {
        self.document = document
        self.chapterCache = chapterCache
        self.spineCount = document.package.resolvedSpine.count
        self.state = State(
            mode: initialMode,
            currentSpineIndex: initialSpineIndex,
            mountedWindow: [],
            isReady: false
        )
    }

    // MARK: - Wiring

    public func attach(webView: WKWebView) async {
        self.webView = webView
    }

    public func setEventObserver(_ observer: EventObserver?) {
        self.eventObserver = observer
    }

    public func setSpineObserver(_ observer: SpineObserver?) {
        self.spineObserver = observer
    }

    public func currentState() -> State { state }

    // MARK: - Lifecycle

    /// Mount the initial window around `anchor.spineIndex` and seek to the
    /// anchor. Safe to call before the JS layer has signalled `ready` —
    /// mounting is deferred until readiness in that case.
    public func start(anchor: ReadingAnchor) async {
        state.currentSpineIndex = anchor.spineIndex
        state.mode = state.mode // no-op, keeps invariants explicit
        pendingAnchorForReady = anchor
        if state.isReady {
            await remountWindow(around: anchor.spineIndex, seekTo: anchor)
        }
    }

    /// Switch to a new mode around the current spine index, preserving
    /// reading position via an anchor the caller provides.
    public func transition(to newMode: Mode, anchor: ReadingAnchor) async {
        guard newMode != state.mode else {
            await navigate(to: anchor)
            return
        }
        state.mode = newMode
        state.currentSpineIndex = anchor.spineIndex
        guard state.isReady else {
            pendingAnchorForReady = anchor
            return
        }
        // Single atomic setMode command; JS layer tears down + rebuilds.
        await remountWindow(around: anchor.spineIndex, seekTo: anchor, modeChanged: true)
    }

    /// Navigate to an anchor. If the target chapter is outside the mounted
    /// window, the window is shifted before the seek.
    public func navigate(to anchor: ReadingAnchor) async {
        guard anchor.spineIndex >= 0, anchor.spineIndex < spineCount else { return }
        state.currentSpineIndex = anchor.spineIndex
        guard state.isReady else {
            pendingAnchorForReady = anchor
            return
        }
        if !state.mountedWindow.contains(anchor.spineIndex) {
            await remountWindow(around: anchor.spineIndex, seekTo: anchor)
        } else {
            await dispatch(.navigate(anchor: anchor))
        }
    }

    /// User-facing next-page intent. In paginated mode the JS layer handles
    /// it directly; if a boundary is reached, a ``ReaderEvent/boundaryReached(direction:spineIndex:)``
    /// event arrives and the controller advances the spine.
    public func nextPage() async {
        await dispatch(.nextPage)
    }

    /// User-facing prev-page intent.
    public func prevPage() async {
        await dispatch(.prevPage)
    }

    /// Apply the current theme stylesheet.
    public func applyTheme(css: String) async {
        await dispatch(.applyTheme(css: css))
    }

    /// Apply a set of highlight overlays (the full set for the mounted window).
    public func applyHighlights(_ highlights: [ReaderCommand.HighlightCommand]) async {
        await dispatch(.applyHighlights(highlights))
    }

    /// Remove a single highlight by ID.
    public func removeHighlight(id: String) async {
        await dispatch(.removeHighlight(id: id))
    }

    /// Show the in-content highlight colour picker.
    public func showHighlightPicker() async {
        await dispatch(.showHighlightPicker)
    }

    /// Tear down the JS layer. Safe to call multiple times.
    public func unmount() async {
        state.isReady = false
        state.mountedWindow = []
        await dispatch(.unmount)
    }

    // MARK: - Events

    /// Called by the bridge when a typed event arrives. Runs actor-isolated
    /// processing then forwards to the main-actor observer.
    public func handle(event: ReaderEvent) async {
        switch event {
        case .ready:
            state.isReady = true
            if let anchor = pendingAnchorForReady {
                pendingAnchorForReady = nil
                await remountWindow(around: anchor.spineIndex, seekTo: anchor, modeChanged: true)
            }
        case let .chapterChanged(spineIndex):
            if spineIndex != state.currentSpineIndex {
                state.currentSpineIndex = spineIndex
                await notifySpineChanged(spineIndex)
                await expandWindowIfNeeded(around: spineIndex)
            }
        case let .boundaryReached(direction, spineIndex):
            let target = direction == "start" ? spineIndex - 1 : spineIndex + 1
            guard target >= 0, target < spineCount else { break }
            state.currentSpineIndex = target
            await notifySpineChanged(target)
            await remountWindow(
                around: target,
                seekTo: ReadingAnchor(
                    spineIndex: target,
                    progress: direction == "start" ? 1.0 : 0.0
                )
            )
        default:
            break
        }
        await forwardEvent(event)
    }

    // MARK: - Window management

    private func windowIndices(around spineIndex: Int) -> [Int] {
        let lower = max(0, spineIndex - Self.windowRadius)
        let upper = min(spineCount - 1, spineIndex + Self.windowRadius)
        guard upper >= lower else { return [] }
        return Array(lower...upper)
    }

    private func remountWindow(
        around spineIndex: Int,
        seekTo anchor: ReadingAnchor,
        modeChanged: Bool = false
    ) async {
        let targetWindow = windowIndices(around: spineIndex)
        let chapters = await loadChapters(indices: targetWindow)
        state.mountedWindow = targetWindow

        if modeChanged {
            await dispatch(.setMode(mode: state.mode.descriptor, anchor: anchor))
        }
        await dispatch(.mountChapters(chapters: chapters, anchor: anchor))
    }

    private func expandWindowIfNeeded(around spineIndex: Int) async {
        let needed = windowIndices(around: spineIndex)
        if Set(needed) == Set(state.mountedWindow) { return }
        let chapters = await loadChapters(indices: needed)
        state.mountedWindow = needed
        await dispatch(
            .mountChapters(
                chapters: chapters,
                anchor: ReadingAnchor(spineIndex: spineIndex)
            )
        )
    }

    private func loadChapters(indices: [Int]) async -> [ChapterContent] {
        let resolved = document.package.resolvedSpine
        var contents: [ChapterContent] = []
        contents.reserveCapacity(indices.count)
        for index in indices {
            guard index >= 0, index < resolved.count else { continue }
            let href = resolved[index].manifest.href
            guard let html = await chapterCache.html(forSpineIndex: index) else { continue }
            let baseURL = chapterBaseURL(forHref: href)
            let body = ChapterBodyExtractor.extractBody(from: html, baseURL: baseURL)
            contents.append(
                ChapterContent(
                    spineIndex: index,
                    spineHref: href,
                    bodyHTML: body
                )
            )
        }
        return contents
    }

    private func chapterBaseURL(forHref href: String) -> URL? {
        let archivePath = document.archivePath(forHref: href)
        return URL(string: "\(EPUBSchemeHandler.scheme)://book/\(archivePath)")
    }

    // MARK: - Dispatch

    private func dispatch(_ command: ReaderCommand) async {
        guard let webView else { return }
        guard let json = try? command.jsonString() else { return }
        let escaped = Self.escapeForJSStringLiteral(json)
        let js = "window.__dsReader && window.__dsReader.dispatch('\(escaped)')"
        await MainActor.run { [weak webView] in
            webView?.evaluateJavaScript(js)
        }
    }

    private func notifySpineChanged(_ index: Int) async {
        guard let observer = spineObserver else { return }
        await MainActor.run { observer(index) }
    }

    private func forwardEvent(_ event: ReaderEvent) async {
        guard let observer = eventObserver else { return }
        await MainActor.run { observer(event) }
    }

    // MARK: - Helpers

    private static func escapeForJSStringLiteral(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "\\": result += "\\\\"
            case "'": result += "\\'"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\u{2028}": result += "\\u2028"
            case "\u{2029}": result += "\\u2029"
            default: result.append(character)
            }
        }
        return result
    }
}
#endif
