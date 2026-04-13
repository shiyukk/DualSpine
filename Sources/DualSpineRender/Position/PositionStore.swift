import Foundation
import DualSpineCore

/// Simple position persistence for reading progress.
/// Stores the last reading position per book using a JSON file in the app's documents directory.
///
/// In ReBabel, this will be replaced by SwiftData persistence on BookMetadata.
/// This standalone implementation is for the DualSpine test harness and library consumers
/// who don't use SwiftData.
public final class PositionStore: Sendable {
    private let storageURL: URL

    public init(storageDirectory: URL? = nil) {
        let dir = storageDirectory ?? FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("DualSpinePositions", isDirectory: true)

        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.storageURL = dir
    }

    /// Save a reading position for a book.
    /// - Parameters:
    ///   - position: The reading position to save.
    ///   - bookIdentifier: Unique identifier for the book (e.g. EPUB identifier or file hash).
    public func save(position: ReadingPosition, forBook bookIdentifier: String) {
        let fileURL = fileURL(for: bookIdentifier)
        guard let data = try? JSONEncoder().encode(position) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Load the last saved reading position for a book.
    public func load(forBook bookIdentifier: String) -> ReadingPosition? {
        let fileURL = fileURL(for: bookIdentifier)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ReadingPosition.self, from: data)
    }

    /// Remove saved position for a book.
    public func remove(forBook bookIdentifier: String) {
        let fileURL = fileURL(for: bookIdentifier)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func fileURL(for bookIdentifier: String) -> URL {
        let safeID = bookIdentifier
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .prefix(100)
        return storageURL.appendingPathComponent("\(safeID).json")
    }
}
