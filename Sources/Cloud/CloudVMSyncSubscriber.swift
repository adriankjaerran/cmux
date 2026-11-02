import CmuxAuthRuntime
import CmuxCloud
import Foundation

/// One `vms` sync record: the same entry shape `GET /api/vm` lists, or a
/// tombstone (`deleted`) carrying no summary.
struct VMSyncRecord: Equatable, Sendable {
    let id: String
    let deleted: Bool
    let summary: VMSummary?
}

/// Stub: the presence-socket `vms` sync went with `Sources/Devices` (Phase 9.14 (B)).
/// It never connects and never emits; the machines panel falls back to its REST poll.
/// Deleted with `Sources/Cloud` (Phase 9.12).
@MainActor
final class CloudVMSyncSubscriber {
    enum Event: Equatable {
        case connected
        case snapshot(records: [VMSyncRecord], backfilled: Bool)
        case delta(records: [VMSyncRecord])
        case disconnected
    }

    init(auth: AuthCoordinator) {}

    func setEventHandler(_ handler: @escaping @MainActor (Event) -> Void) {}

    var isRunning: Bool { false }

    func start() {}

    func stop() {}
}
