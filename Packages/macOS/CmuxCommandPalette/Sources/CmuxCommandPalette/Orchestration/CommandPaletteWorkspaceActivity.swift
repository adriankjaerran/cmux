public import Foundation

/// Fork: the short activity note shown on a Go to Workspace (⌘P) row in place
/// of the "Workspace" kind label, e.g. "waiting", "running 3m", "done 4m".
public enum CommandPaletteWorkspaceActivity {
    /// One agent session in the workspace.
    public struct Agent: Sendable, Equatable {
        /// The session state.
        public enum State: Sendable, Equatable {
            case needsInput
            case working(since: Date?)
            case idle
            case ended
        }

        public let state: State
        /// The most recent hook or transcript activity.
        public let lastActivityAt: Date

        public init(state: State, lastActivityAt: Date) {
            self.state = state
            self.lastActivityAt = lastActivityAt
        }
    }

    /// The note for one workspace, or `nil` when nothing has happened there.
    ///
    /// An agent waiting for input wins, then a working agent; otherwise the
    /// latest finished thing (agent activity, terminal command, notification)
    /// is shown as "done <age>".
    public static func label(
        agents: [Agent],
        lastCommandFinishedAt: Date?,
        lastNotificationAt: Date?,
        now: Date
    ) -> String? {
        if agents.contains(where: { $0.state == .needsInput }) {
            return String(localized: "commandPalette.activity.waiting", defaultValue: "waiting")
        }
        let workingSince = agents.compactMap { agent -> Date?? in
            if case .working(let since) = agent.state { return .some(since) }
            return nil
        }
        if !workingSince.isEmpty {
            let running = String(localized: "commandPalette.activity.running", defaultValue: "running")
            guard let since = workingSince.compactMap({ $0 }).min() else { return running }
            return "\(running) \(age(from: since, to: now))"
        }
        let candidates = agents.map(\.lastActivityAt) + [lastCommandFinishedAt, lastNotificationAt].compactMap { $0 }
        guard let latest = candidates.max() else { return nil }
        let done = String(localized: "commandPalette.activity.done", defaultValue: "done")
        return "\(done) \(age(from: latest, to: now))"
    }

    /// Compact age: "now", "4m", "3h", "2d".
    public static func age(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return String(localized: "commandPalette.activity.now", defaultValue: "now") }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}

/// Fork: when a terminal command last finished in each workspace (Ghostty's
/// shell-integration COMMAND_FINISHED action), for the ⌘P activity note.
@MainActor
public final class CommandPaletteWorkspaceActivityRecorder {
    public static let shared = CommandPaletteWorkspaceActivityRecorder()

    private var lastCommandFinishedAt: [UUID: Date] = [:]

    public init() {}

    public func recordCommandFinished(workspaceId: UUID, at date: Date = Date()) {
        lastCommandFinishedAt[workspaceId] = date
    }

    public func lastCommandFinished(workspaceId: UUID) -> Date? {
        lastCommandFinishedAt[workspaceId]
    }
}
