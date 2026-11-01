import Foundation
import Testing
@testable import CmuxWorkspaces

/// Fork: a group header is only a folder; its anchor is an ordinary member
/// that can leave the group without dissolving it.
@MainActor
struct WorkspaceGroupFolderAnchorTests {
    private func makeWorld() -> (
        model: WorkspacesModel<CoordinatorStubTab>,
        host: StubGroupHost,
        groups: WorkspaceGroupCoordinator<CoordinatorStubTab>
    ) {
        let model = WorkspacesModel<CoordinatorStubTab>()
        let host = StubGroupHost(model: model) // held by the test; attach is weak
        let groups = WorkspaceGroupCoordinator(model: model)
        groups.attach(host: host)
        return (model, host, groups)
    }

    @Test
    func removingAnchorPromotesNextMemberAndKeepsGroup() throws {
        let (model, host, groups) = makeWorld()
        _ = host
        let first = CoordinatorStubTab()
        let second = CoordinatorStubTab()
        model.tabs = [first, second]
        let groupId = try #require(groups.createWorkspaceGroup(name: "G", childWorkspaceIds: [first.id, second.id]))
        #expect(model.workspaceGroups.first { $0.id == groupId }?.liveAnchorWorkspaceId == first.id)

        groups.removeWorkspaceFromGroup(workspaceId: first.id)

        let group = try #require(model.workspaceGroups.first { $0.id == groupId })
        #expect(group.liveAnchorWorkspaceId == second.id)
        #expect(first.groupId == nil)
        #expect(second.groupId == groupId)
    }

    @Test
    func removingSoleMemberDissolvesGroup() throws {
        let (model, host, groups) = makeWorld()
        _ = host
        let only = CoordinatorStubTab()
        model.tabs = [only]
        let groupId = try #require(groups.createWorkspaceGroup(name: "G", childWorkspaceIds: [only.id]))

        groups.removeWorkspaceFromGroup(workspaceId: only.id)

        #expect(!model.workspaceGroups.contains { $0.id == groupId })
        #expect(only.groupId == nil)
    }

    @Test
    func addingAnchorToAnotherGroupMovesItAndPromotesNext() throws {
        let (model, host, groups) = makeWorld()
        _ = host
        let a = CoordinatorStubTab()
        let b = CoordinatorStubTab()
        let c = CoordinatorStubTab()
        model.tabs = [a, b, c]
        let source = try #require(groups.createWorkspaceGroup(name: "S", childWorkspaceIds: [a.id, b.id]))
        let target = try #require(groups.createWorkspaceGroup(name: "T", childWorkspaceIds: [c.id]))

        groups.addWorkspaceToGroup(workspaceId: a.id, groupId: target)

        #expect(a.groupId == target)
        #expect(model.workspaceGroups.first { $0.id == source }?.liveAnchorWorkspaceId == b.id)
        #expect(model.workspaceGroups.first { $0.id == target }?.liveAnchorWorkspaceId == c.id)
    }

    @Test
    func newGroupFromAnchorTakesItAndPromotesNext() throws {
        let (model, host, groups) = makeWorld()
        _ = host
        let a = CoordinatorStubTab()
        let b = CoordinatorStubTab()
        model.tabs = [a, b]
        let source = try #require(groups.createWorkspaceGroup(name: "S", childWorkspaceIds: [a.id, b.id]))

        let fresh = try #require(groups.createWorkspaceGroup(name: "N", childWorkspaceIds: [a.id]))

        #expect(a.groupId == fresh)
        #expect(model.workspaceGroups.first { $0.id == fresh }?.liveAnchorWorkspaceId == a.id)
        #expect(model.workspaceGroups.first { $0.id == source }?.liveAnchorWorkspaceId == b.id)
    }
}
