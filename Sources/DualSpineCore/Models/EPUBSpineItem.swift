import Foundation

/// A single entry from the OPF `<spine>`, representing one content document in reading order.
public struct EPUBSpineItem: Sendable, Identifiable, Hashable {
    /// Unique ID for this spine entry (auto-generated, not from OPF).
    public let id: UUID

    /// The `idref` attribute pointing to a manifest item's `id`.
    public let manifestRef: String

    /// Whether this item is part of the linear reading order.
    /// Non-linear items (e.g. footnote popups) have `linear="no"`.
    public let linear: Bool

    /// Zero-based position in the spine.
    public let index: Int

    public init(manifestRef: String, linear: Bool = true, index: Int) {
        self.id = UUID()
        self.manifestRef = manifestRef
        self.linear = linear
        self.index = index
    }
}
