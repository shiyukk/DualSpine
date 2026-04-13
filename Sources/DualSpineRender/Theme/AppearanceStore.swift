import Foundation

/// Scope for appearance settings.
public enum AppearanceScope: Sendable, Hashable {
    /// Global settings apply to all books without a per-book override.
    case global
    /// Per-book override identified by the book's unique identifier.
    case book(String)
}

/// Manages global appearance settings and optional per-book overrides.
///
/// Flow:
/// - Global settings apply by default to all books
/// - A book can have a per-book override which takes precedence
/// - Toggling off the override removes the book's entry → reverts to global
public final class AppearanceStore: @unchecked Sendable {
    private let storageURL: URL
    private let globalFileName = "global.json"
    private let queue = DispatchQueue(label: "com.dualspine.appearancestore", attributes: .concurrent)

    public init(storageDirectory: URL? = nil) {
        let dir = storageDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("DualSpineAppearance", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir
    }

    // MARK: - Global

    public func loadGlobal() -> ReadingAppearanceSettings {
        queue.sync {
            loadSettings(at: globalFileURL) ?? ReadingAppearanceSettings()
        }
    }

    public func saveGlobal(_ settings: ReadingAppearanceSettings) {
        queue.async(flags: .barrier) {
            self.saveSettings(settings, at: self.globalFileURL)
        }
    }

    // MARK: - Per-book

    /// Load per-book override, returns nil if no override exists.
    public func loadBookOverride(bookID: String) -> ReadingAppearanceSettings? {
        queue.sync {
            loadSettings(at: bookFileURL(for: bookID))
        }
    }

    /// Save per-book override.
    public func saveBookOverride(bookID: String, settings: ReadingAppearanceSettings) {
        queue.async(flags: .barrier) {
            self.saveSettings(settings, at: self.bookFileURL(for: bookID))
        }
    }

    /// Remove per-book override (book reverts to global).
    public func removeBookOverride(bookID: String) {
        queue.async(flags: .barrier) {
            try? FileManager.default.removeItem(at: self.bookFileURL(for: bookID))
        }
    }

    /// Effective settings for a book: per-book override if present, otherwise global.
    public func effectiveSettings(forBook bookID: String) -> ReadingAppearanceSettings {
        if let override = loadBookOverride(bookID: bookID) {
            return override
        }
        return loadGlobal()
    }

    /// Whether a book has a per-book override.
    public func hasBookOverride(bookID: String) -> Bool {
        FileManager.default.fileExists(atPath: bookFileURL(for: bookID).path)
    }

    // MARK: - Private

    private var globalFileURL: URL {
        storageURL.appendingPathComponent(globalFileName)
    }

    private func bookFileURL(for bookID: String) -> URL {
        let safeID = bookID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .prefix(100)
        return storageURL.appendingPathComponent("book_\(safeID).json")
    }

    private func loadSettings(at url: URL) -> ReadingAppearanceSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ReadingAppearanceSettings.self, from: data)
    }

    private func saveSettings(_ settings: ReadingAppearanceSettings, at url: URL) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
