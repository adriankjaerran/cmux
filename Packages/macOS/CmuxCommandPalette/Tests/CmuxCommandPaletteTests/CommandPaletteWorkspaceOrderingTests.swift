import Foundation
import Testing

@testable import CmuxCommandPalette

struct CommandPaletteWorkspaceOrderingTests {
    @Test func recentModePutsPreviousWorkspacesFirstAndCurrentLast() {
        let current = UUID()
        let previous = UUID()
        let older = UUID()
        let untouched = UUID()

        let ordered = CommandPaletteWorkspaceOrdering().orderedWorkspaceIDs(
            sidebarIDs: [current, older, previous, untouched],
            selectedID: current,
            recentIDs: [previous, older],
            mode: .recent
        )

        #expect(ordered == [previous, older, untouched, current])
    }

    @Test func sidebarModeKeepsSelectedWorkspaceFirst() {
        let current = UUID()
        let other = UUID()

        let ordered = CommandPaletteWorkspaceOrdering().orderedWorkspaceIDs(
            sidebarIDs: [other, current],
            selectedID: current,
            recentIDs: [other],
            mode: .sidebar
        )

        #expect(ordered == [current, other])
    }

    @Test func recentModeIgnoresStaleAndDuplicateHistoryEntries() {
        let current = UUID()
        let recent = UUID()
        let untouched = UUID()
        let stale = UUID()

        let ordered = CommandPaletteWorkspaceOrdering().orderedWorkspaceIDs(
            sidebarIDs: [current, recent, untouched],
            selectedID: current,
            recentIDs: [recent, stale, recent],
            mode: .recent
        )

        #expect(ordered == [recent, untouched, current])
    }

    @Test func recentModeFallsBackToSelectedFirstWithoutHistory() {
        let current = UUID()
        let other = UUID()

        let ordered = CommandPaletteWorkspaceOrdering().orderedWorkspaceIDs(
            sidebarIDs: [other, current],
            selectedID: current,
            recentIDs: [],
            mode: .recent
        )

        #expect(ordered == [current, other])
    }
}

struct CommandPaletteWorkspaceUnreadOrderingTests {
    @Test func unreadWorkspacesComeFirstInSidebarOrder() {
        let current = UUID(), a = UUID(), b = UUID(), c = UUID()
        let ordered = CommandPaletteWorkspaceOrdering().orderedWorkspaceIDs(
            sidebarIDs: [a, current, b, c],
            selectedID: current,
            recentIDs: [],
            mode: .sidebar,
            unreadIDs: [c, a]
        )
        #expect(ordered == [a, c, current, b])
    }

    @Test func selectedWorkspaceIsNotPromotedEvenIfUnread() {
        let current = UUID(), previous = UUID(), other = UUID()
        let ordered = CommandPaletteWorkspaceOrdering().orderedWorkspaceIDs(
            sidebarIDs: [current, previous, other],
            selectedID: current,
            recentIDs: [previous],
            mode: .recent,
            unreadIDs: [current, other]
        )
        #expect(ordered == [other, previous, current])
    }
}
