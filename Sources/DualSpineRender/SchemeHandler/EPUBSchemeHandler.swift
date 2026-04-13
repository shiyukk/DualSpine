import Foundation
import WebKit
import DualSpineCore

/// Custom `WKURLSchemeHandler` that serves EPUB resources directly from the ZIP archive
/// via a custom `epub-content://` URL scheme — no GCDWebServer, no localhost HTTP.
///
/// URL format: `epub-content://<book-id>/<relative-path>`
/// Example:    `epub-content://my-book/OEBPS/chapter1.xhtml`
///
/// The handler reads resources through `EPUBResourceActor` for thread safety.
@MainActor
public final class EPUBSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The custom URL scheme used for serving EPUB content.
    nonisolated public static let scheme = "epub-content"

    private let resourceActor: EPUBResourceActor
    private let contentBasePath: String

    /// Active tasks tracked for cancellation support.
    private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    public init(resourceActor: EPUBResourceActor, contentBasePath: String) {
        self.resourceActor = resourceActor
        self.contentBasePath = contentBasePath
        super.init()
    }

    // MARK: - WKURLSchemeHandler

    public func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(EPUBError.resourceNotFound("nil URL"))
            return
        }

        // Extract the resource path from the URL.
        // URL: epub-content://book-id/OEBPS/chapter1.xhtml → path = "/OEBPS/chapter1.xhtml"
        let resourcePath = String(url.path.dropFirst()) // Remove leading "/"

        let taskKey = ObjectIdentifier(urlSchemeTask as AnyObject)
        let actor = resourceActor

        let task = Task { [weak self] in
            do {
                let (data, mimeType) = try await actor.readResource(at: resourcePath)

                guard !Task.isCancelled else { return }

                let response = URLResponse(
                    url: url,
                    mimeType: mimeType,
                    expectedContentLength: data.count,
                    textEncodingName: mimeType.hasPrefix("text/")
                        || mimeType.contains("xhtml")
                        || mimeType.contains("xml")
                        || mimeType.contains("javascript")
                        || mimeType.contains("json")
                        ? "utf-8" : nil
                )

                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                guard !Task.isCancelled else { return }
                urlSchemeTask.didFailWithError(error)
            }

            _ = await MainActor.run { [weak self] in
                self?.activeTasks.removeValue(forKey: taskKey)
            }
        }

        activeTasks[taskKey] = task
    }

    public func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        let taskKey = ObjectIdentifier(urlSchemeTask as AnyObject)
        let task = activeTasks.removeValue(forKey: taskKey)
        task?.cancel()
    }
}
