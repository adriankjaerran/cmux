import CmuxFoundation
import Foundation
import os

/// Fans raw PTY-output bytes from every cmux terminal surface out to local
/// subscribers (`surface.wait_text_change` parks on ``outputUpdates(surfaceID:)``).
///
/// The byte source is libghostty's `ghostty_surface_set_pty_tee_cb`
/// callback (cmux fork addition), which fires on the IO read thread before
/// the VT parser sees the bytes. The hot path bails before any allocation
/// when nobody is subscribed. Formerly `MobileTerminalByteTee`; the phone
/// replay buffer, render-grid identities and `terminal.bytes` events went
/// with `Sources/Mobile` (Phase 9.14).
@MainActor
final class TerminalOutputByteTee {
    struct OutputChunk: Sendable {
        let sequence: UInt64
        let data: Data
    }

    // nonisolated: the singleton itself is an immutable `let` constructed once;
    // the only cross-thread entry point (`append`, from the C tee trampoline) is
    // `nonisolated` and hops to the main actor internally.
    nonisolated static let shared = TerminalOutputByteTee()

    /// Monotonic byte-stream sequence per surface; each chunk advances it by
    /// its length.
    private var sequenceBySurfaceID: [UUID: UInt64] = [:]
    private var continuationsBySurfaceID: [
        UUID: [UUID: AsyncStream<OutputChunk>.Continuation]
    ] = [:]
    nonisolated private let subscriberCount = OSAllocatedUnfairLock(initialState: 0)
    nonisolated private let demand = AtomicBooleanGate(false)
    /// Serial queue so fan-out preserves byte order even though the
    /// upstream callback runs off the main thread.
    private let publishQueue = DispatchQueue(
        label: "dev.cmux.terminal-output.byte-tee.publish",
        qos: .userInitiated
    )

    nonisolated private init() {}

    /// Non-isolated entry point called from the C tee trampoline. Safe
    /// to invoke from any thread.
    nonisolated func append(surfaceID: UUID, bytes: UnsafeBufferPointer<UInt8>) {
        // Hot path: runs on the Ghostty PTY/IO read thread for every surface.
        // Bail before any allocation or main-actor hop when nobody listens.
        guard demand.loadAcquire() else { return }
        guard let base = bytes.baseAddress, bytes.count > 0 else { return }
        let copy = Data(bytes: base, count: bytes.count)
        publishQueue.async { [weak self] in
            Task { @MainActor [weak self] in
                self?.publishFromMain(surfaceID: surfaceID, data: copy)
            }
        }
    }

    /// Opens a bounded raw-output subscription for one surface. If a slow
    /// consumer drops a chunk, the stream ends so the reader resubscribes.
    func outputUpdates(surfaceID: UUID) -> AsyncStream<OutputChunk> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingOldest(64)) { continuation in
            continuationsBySurfaceID[surfaceID, default: [:]][id] = continuation
            subscriberCount.withLock { $0 += 1 }
            demand.storeRelease(true)
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.removeContinuation(id: id, surfaceID: surfaceID)
                }
            }
        }
    }

    /// Drops a surface's state and ends its subscriptions (the surface closed).
    func dropSurface(surfaceID: UUID) {
        sequenceBySurfaceID.removeValue(forKey: surfaceID)
        let continuations = continuationsBySurfaceID.removeValue(forKey: surfaceID)
            .map { Array($0.values) } ?? []
        guard !continuations.isEmpty else { return }
        let remainingCount = subscriberCount.withLock { count in
            count = max(0, count - continuations.count)
            return count
        }
        demand.storeRelease(remainingCount > 0)
        for continuation in continuations {
            continuation.finish()
        }
    }

    private func publishFromMain(surfaceID: UUID, data: Data) {
        let chunkSeq = sequenceBySurfaceID[surfaceID] ?? 0
        sequenceBySurfaceID[surfaceID] = chunkSeq &+ UInt64(data.count)
        #if DEBUG
        HostLatencyTrace.stamp(
            "host.tee",
            "s=\(surfaceID.uuidString.prefix(8).lowercased()) seq=\(chunkSeq &+ UInt64(data.count)) bytes=\(data.count)"
        )
        #endif
        guard let continuations = continuationsBySurfaceID[surfaceID] else { return }
        let chunk = OutputChunk(sequence: chunkSeq, data: data)
        var droppedIDs: [UUID] = []
        for (id, continuation) in continuations {
            if case .dropped = continuation.yield(chunk) {
                continuation.finish()
                droppedIDs.append(id)
            }
        }
        for id in droppedIDs {
            removeContinuation(id: id, surfaceID: surfaceID)
        }
    }

    private func removeContinuation(id: UUID, surfaceID: UUID) {
        guard continuationsBySurfaceID[surfaceID]?.removeValue(forKey: id) != nil else {
            return
        }
        if continuationsBySurfaceID[surfaceID]?.isEmpty == true {
            continuationsBySurfaceID[surfaceID] = nil
        }
        let remainingCount = subscriberCount.withLock { count in
            count = max(0, count - 1)
            return count
        }
        demand.storeRelease(remainingCount > 0)
    }
}
