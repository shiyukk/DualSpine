#if canImport(UIKit)
import Foundation
import DualSpineCore

/// In-memory cache of parsed chapter HTML, indexed by spine index.
/// Bulk-loaded at book open so chapter injection is instant — no ZIP reads.
public actor ChapterCache {
    private var html: [Int: String] = [:]
    private var loading: Set<Int> = []

    private let document: EPUBDocument
    private let resourceActor: EPUBResourceActor

    public init(document: EPUBDocument, resourceActor: EPUBResourceActor) {
        self.document = document
        self.resourceActor = resourceActor
    }

    /// Eagerly load ALL chapters' HTML into memory in parallel.
    /// Returns when all have loaded (or failed).
    public func preloadAll() async {
        let resolved = document.package.resolvedSpine
        await withTaskGroup(of: Void.self) { group in
            for (idx, (_, manifest)) in resolved.enumerated() {
                guard manifest.isContentDocument else { continue }
                if html[idx] != nil { continue }
                loading.insert(idx)

                let archivePath = document.archivePath(forHref: manifest.href)
                let actor = resourceActor

                group.addTask { [weak self] in
                    guard let self else { return }
                    if let (data, _) = try? await actor.readResource(at: archivePath),
                       let text = String(data: data, encoding: .utf8) {
                        await self.set(idx: idx, html: text)
                    } else {
                        await self.clearLoading(idx: idx)
                    }
                }
            }
        }
    }

    /// Get HTML for a chapter — returns immediately if cached, else loads it.
    public func html(forSpineIndex idx: Int) async -> String? {
        if let cached = html[idx] {
            return cached
        }
        // Load on demand
        let resolved = document.package.resolvedSpine
        guard idx >= 0, idx < resolved.count else { return nil }
        let manifest = resolved[idx].1
        guard manifest.isContentDocument else { return nil }
        let archivePath = document.archivePath(forHref: manifest.href)
        guard let (data, _) = try? await resourceActor.readResource(at: archivePath),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        html[idx] = text
        return text
    }

    public func isLoaded(spineIndex idx: Int) -> Bool {
        html[idx] != nil
    }

    public var loadedCount: Int { html.count }

    private func set(idx: Int, html content: String) {
        html[idx] = content
        loading.remove(idx)
    }

    private func clearLoading(idx: Int) {
        loading.remove(idx)
    }
}
#endif
