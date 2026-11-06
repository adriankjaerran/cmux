import CoreGraphics
import SwiftUI

/// Collects the on-screen frames of `Reorderable` rows, keyed by their item
/// key (the JS `key:` of each entry), so a host can hit-test external drags
/// (e.g. a terminal tab dropped onto a workspace row) against the sidebar.
///
/// Frames are expressed in the named coordinate space
/// ``SceneRowFrameReporter/coordinateSpaceName``; the host declares that
/// space on a non-scrolling container around the sidebar, so reported frames
/// track scrolling and line up with an overlay covering that container.
///
/// A plain class on purpose (not observable): frames change on every scroll
/// and fold frame, and observing them would re-render the sidebar. Hosts read
/// them only at drag time.
@MainActor
public final class SceneRowFrameReporter {
    /// The named coordinate space reported frames are expressed in.
    public static let coordinateSpaceName = "cmux.sceneRowFrames"

    /// One reported row.
    public struct Row: Equatable, Sendable {
        /// The row's item key (see `Reorderable`'s `key:` option).
        public let key: String
        /// The row's visual box (layout slot inset by its leading margin), in
        /// ``SceneRowFrameReporter/coordinateSpaceName``.
        public let frame: CGRect
        /// The row box's corner radius.
        public let cornerRadius: CGFloat

        public init(key: String, frame: CGRect, cornerRadius: CGFloat) {
            self.key = key
            self.frame = frame
            self.cornerRadius = cornerRadius
        }
    }

    private struct Entry {
        var key: String
        var slot: CGRect
        var leadingInset: CGFloat
        var cornerRadius: CGFloat
    }

    /// Keyed by scene node id (stable per row) rather than item key, so a key
    /// change for the same row (e.g. entering inline edit) replaces in place.
    private var entries: [String: Entry] = [:]

    public init() {}

    /// Every reported row, in no particular order.
    public var rows: [Row] {
        entries.values.map(Self.row(from:))
    }

    /// The row whose visual box contains `point`, if any.
    public func row(at point: CGPoint) -> Row? {
        for entry in entries.values {
            let row = Self.row(from: entry)
            if row.frame.contains(point) { return row }
        }
        return nil
    }

    func recordFrame(nodeId: String, slot: CGRect, meta: RowMeta) {
        entries[nodeId] = Entry(
            key: meta.key,
            slot: slot,
            leadingInset: meta.leadingInset,
            cornerRadius: meta.cornerRadius
        )
    }

    func updateMeta(nodeId: String, meta: RowMeta) {
        guard var entry = entries[nodeId] else { return }
        entry.key = meta.key
        entry.leadingInset = meta.leadingInset
        entry.cornerRadius = meta.cornerRadius
        entries[nodeId] = entry
    }

    func remove(nodeId: String) {
        entries[nodeId] = nil
    }

    /// Non-geometry facts about a row that its reported frame depends on.
    struct RowMeta: Equatable {
        let key: String
        let leadingInset: CGFloat
        let cornerRadius: CGFloat
    }

    private static func row(from entry: Entry) -> Row {
        var frame = entry.slot
        let inset = min(max(0, entry.leadingInset), frame.width)
        frame.origin.x += inset
        frame.size.width -= inset
        return Row(key: entry.key, frame: frame, cornerRadius: entry.cornerRadius)
    }
}

private struct SceneRowFrameReporterKey: EnvironmentKey {
    static let defaultValue: SceneRowFrameReporter? = nil
}

extension EnvironmentValues {
    /// Where `Reorderable` rows report their frames. `nil` (the default)
    /// disables reporting.
    public var sceneRowFrameReporter: SceneRowFrameReporter? {
        get { self[SceneRowFrameReporterKey.self] }
        set { self[SceneRowFrameReporterKey.self] = newValue }
    }
}
