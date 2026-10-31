import Foundation
import Testing

@testable import CmuxCommandPalette

struct CommandPaletteWorkspaceActivityTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func waitingAgentWins() {
        let label = CommandPaletteWorkspaceActivity.label(
            agents: [
                .init(state: .working(since: now.addingTimeInterval(-60)), lastActivityAt: now),
                .init(state: .needsInput, lastActivityAt: now),
            ],
            lastCommandFinishedAt: now,
            lastNotificationAt: nil,
            now: now
        )
        #expect(label == "waiting")
    }

    @Test func workingAgentShowsHowLongItHasRun() {
        let label = CommandPaletteWorkspaceActivity.label(
            agents: [.init(state: .working(since: now.addingTimeInterval(-180)), lastActivityAt: now)],
            lastCommandFinishedAt: nil,
            lastNotificationAt: nil,
            now: now
        )
        #expect(label == "running 3m")
    }

    @Test func otherwiseShowsTheLatestFinishedThing() {
        let label = CommandPaletteWorkspaceActivity.label(
            agents: [.init(state: .idle, lastActivityAt: now.addingTimeInterval(-7_200))],
            lastCommandFinishedAt: now.addingTimeInterval(-240),
            lastNotificationAt: now.addingTimeInterval(-90_000),
            now: now
        )
        #expect(label == "done 4m")
    }

    @Test func nothingHappenedShowsNothing() {
        let label = CommandPaletteWorkspaceActivity.label(
            agents: [],
            lastCommandFinishedAt: nil,
            lastNotificationAt: nil,
            now: now
        )
        #expect(label == nil)
    }

    @Test func ageFormatting() {
        #expect(CommandPaletteWorkspaceActivity.age(from: now.addingTimeInterval(-30), to: now) == "now")
        #expect(CommandPaletteWorkspaceActivity.age(from: now.addingTimeInterval(-3 * 3_600), to: now) == "3h")
        #expect(CommandPaletteWorkspaceActivity.age(from: now.addingTimeInterval(-2 * 86_400), to: now) == "2d")
    }
}
