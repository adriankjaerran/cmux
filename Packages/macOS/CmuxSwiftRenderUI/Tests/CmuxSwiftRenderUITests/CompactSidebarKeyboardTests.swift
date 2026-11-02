import CmuxSwiftRender
@testable import CmuxSwiftRenderUI
import Foundation
import Testing

/// Keyboard mode in the fork's built-in compact sidebar
/// (`Resources/sidebars/compact.js`), run in a real runtime against a small
/// data context: cursor start, folder collapse/expand, collapse-all, open.
@MainActor
struct CompactSidebarKeyboardTests {
    private static let compactURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CmuxSwiftRenderUITests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // CmuxSwiftRenderUI
        .deletingLastPathComponent() // macOS
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("Resources/sidebars/compact.js")

    private final class Captured {
        var commands: [ActionCommand] = []
    }

    private func workspace(_ id: String, group: String? = nil, selected: Bool = false) -> SwiftValue {
        var fields: [String: SwiftValue] = [
            "id": .string(id), "title": .string(id), "selected": .bool(selected), "pinned": .bool(false),
        ]
        if let group { fields["group"] = .string(group) }
        return .object(fields)
    }

    private func group(_ id: String, anchor: String, collapsed: Bool) -> SwiftValue {
        .object([
            "id": .string(id), "name": .string(id), "collapsed": .bool(collapsed),
            "pinned": .bool(false), "anchorId": .string(anchor),
        ])
    }

    /// a | g1: m1 (selected), m2 | g2 (collapsed): n1 | z
    private func makeRuntime(_ captured: Captured) throws -> SidebarJSRuntime {
        let source = try String(contentsOf: Self.compactURL, encoding: .utf8)
        let runtime = SidebarJSRuntime()
        runtime.dispatch = SidebarActionDispatch { action in captured.commands.append(contentsOf: action.commands) }
        #expect(runtime.start(source: source))
        runtime.updateData(key: "groups", value: .array([
            group("g1", anchor: "m1", collapsed: false),
            group("g2", anchor: "n1", collapsed: true),
        ]))
        runtime.updateData(key: "workspaces", value: .array([
            workspace("a"),
            workspace("m1", group: "g1", selected: true),
            workspace("m2", group: "g1"),
            workspace("n1", group: "g2"),
            workspace("z"),
        ]))
        runtime.updateData(key: "selectedId", value: .string("m1"))
        #expect(runtime.errorMessage == nil)
        #expect(runtime.handlesKeys)
        return runtime
    }

    private func cursor(_ runtime: SidebarJSRuntime) -> String? {
        runtime.evaluateForTesting("String(cursorRow())")
    }

    private func press(_ runtime: SidebarJSRuntime, _ key: String) -> SidebarKeyResult {
        runtime.dispatchKey(SidebarKeyPress(key: key))
    }

    private func pumpActions() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test func cursorStartsOnSelectionAndWalksVisibleRows() throws {
        let runtime = try makeRuntime(Captured())
        #expect(cursor(runtime) == "null")
        runtime.setKeyboardMode(true)
        #expect(cursor(runtime) == "m1")
        #expect(press(runtime, "down") == SidebarKeyResult(handled: true))
        #expect(cursor(runtime) == "m2")
        _ = press(runtime, "down")
        #expect(cursor(runtime) == "h:g2")
        // g2 is collapsed: n1 is skipped.
        _ = press(runtime, "down")
        #expect(cursor(runtime) == "z")
        runtime.setKeyboardMode(false)
        #expect(cursor(runtime) == "null")
    }

    @Test func leftCollapsesTheFolderAndRightExpandsIt() async throws {
        let captured = Captured()
        let runtime = try makeRuntime(captured)
        runtime.setKeyboardMode(true)
        _ = press(runtime, "left")
        #expect(cursor(runtime) == "h:g1")
        _ = press(runtime, "down")
        // g1 collapsed optimistically: the next row is g2's header.
        #expect(cursor(runtime) == "h:g2")
        _ = press(runtime, "right")
        _ = press(runtime, "down")
        #expect(cursor(runtime) == "n1")
        await pumpActions()
        #expect(captured.commands == [
            .cmux(method: "workspace.group.collapse", params: ["group_id": "g1"]),
            .cmux(method: "workspace.group.expand", params: ["group_id": "g2"]),
        ])
    }

    @Test func cTogglesCollapseAll() async throws {
        let captured = Captured()
        let runtime = try makeRuntime(captured)
        runtime.setKeyboardMode(true)
        // g1 is open, so "c" collapses everything; the cursor falls back to
        // the header hiding the selected row.
        #expect(press(runtime, "c") == SidebarKeyResult(handled: true))
        #expect(cursor(runtime) == "h:g1")
        // Now none is open: "c" expands both.
        _ = press(runtime, "c")
        await pumpActions()
        #expect(captured.commands == [
            .cmux(method: "workspace.group.collapse", params: ["group_id": "g1"]),
            .cmux(method: "workspace.group.expand", params: ["group_id": "g1"]),
            .cmux(method: "workspace.group.expand", params: ["group_id": "g2"]),
        ])
    }

    @Test func returnOpensWorkspacesAndTogglesHeaders() throws {
        let runtime = try makeRuntime(Captured())
        runtime.setKeyboardMode(true)
        _ = press(runtime, "up")
        #expect(cursor(runtime) == "h:g1")
        #expect(press(runtime, "return") == SidebarKeyResult(handled: true))
        _ = press(runtime, "up")
        #expect(press(runtime, "space") == SidebarKeyResult(handled: true, exit: true, openWorkspaceId: "a"))
        #expect(press(runtime, "escape") == SidebarKeyResult(handled: true, exit: true))
        #expect(press(runtime, "q") == .unhandled)
        #expect(runtime.dispatchKey(SidebarKeyPress(key: "down", command: true)) == .unhandled)
    }

    @Test func cursorRowDrawsARing() throws {
        let runtime = try makeRuntime(Captured())
        let ringed = { () -> [String] in
            var found: [String] = []
            var stack = [runtime.store.rootId].compactMap { $0 }
            while let id = stack.popLast() {
                guard let node = runtime.store.node(id) else { continue }
                if node.string("borderColor") != nil { found.append(id) }
                stack.append(contentsOf: node.children)
            }
            return found
        }
        #expect(ringed().isEmpty)
        runtime.setKeyboardMode(true)
        #expect(ringed().count == 1)
        runtime.setKeyboardMode(false)
        #expect(ringed().isEmpty)
    }
}
