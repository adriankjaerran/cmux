import AppKit
import CmuxSwiftRender
@testable import CmuxSwiftRenderUI
import Foundation
import Testing

/// Sidebar keyboard mode: the prelude's pure `sidebarKeyNav` over a visible
/// row list with collapsible groups, and the `onKey` / `keyboardMode()`
/// bridge the app drives.
@MainActor
struct SidebarKeyboardModeTests {
    /// Visible rows: ungrouped "a", expanded group g1 (h:g1, m1, m2),
    /// collapsed group g2 (its members are not visible), ungrouped "z".
    private static let rows = """
    [
      { id: "a", group: null },
      { id: "h:g1", header: true, group: "g1", collapsed: false },
      { id: "m1", group: "g1" },
      { id: "m2", group: "g1" },
      { id: "h:g2", header: true, group: "g2", collapsed: true },
      { id: "z", group: null },
    ]
    """

    private func runtime() throws -> SidebarJSRuntime {
        let runtime = SidebarJSRuntime()
        #expect(runtime.start(source: "sidebar(() => Text(\"x\"))"))
        return runtime
    }

    /// Runs one navigation step and returns its result as a dictionary.
    private func step(_ runtime: SidebarJSRuntime, cursor: String?, key: String, rows: String = rows) throws -> [String: Any] {
        let cursorLiteral = cursor.map { "\"\($0)\"" } ?? "null"
        let json = try #require(runtime.evaluateForTesting(
            "JSON.stringify(sidebarKeyNav(\(rows), \(cursorLiteral), \"\(key)\"))"
        ))
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }

    @Test func downAndUpWalkVisibleRowsIncludingHeaders() throws {
        let runtime = try runtime()
        #expect(try step(runtime, cursor: "a", key: "down")["cursor"] as? String == "h:g1")
        #expect(try step(runtime, cursor: "h:g1", key: "down")["cursor"] as? String == "m1")
        #expect(try step(runtime, cursor: "m2", key: "down")["cursor"] as? String == "h:g2")
        // The collapsed group's members are skipped: its header leads to "z".
        #expect(try step(runtime, cursor: "h:g2", key: "down")["cursor"] as? String == "z")
        #expect(try step(runtime, cursor: "z", key: "up")["cursor"] as? String == "h:g2")
        #expect(try step(runtime, cursor: "h:g1", key: "up")["cursor"] as? String == "a")
    }

    @Test func upAndDownStopAtTheEnds() throws {
        let runtime = try runtime()
        let top = try step(runtime, cursor: "a", key: "up")
        #expect(top["cursor"] as? String == "a")
        #expect(top["handled"] as? Bool == true)
        #expect(try step(runtime, cursor: "z", key: "down")["cursor"] as? String == "z")
    }

    @Test func unknownCursorStartsAtTheTop() throws {
        let runtime = try runtime()
        #expect(try step(runtime, cursor: "gone", key: "down")["cursor"] as? String == "h:g1")
        let empty = try step(runtime, cursor: nil, key: "down", rows: "[]")
        #expect(empty["cursor"] is NSNull || empty["cursor"] == nil)
    }

    @Test func leftOnAMemberJumpsToItsHeaderAndCollapses() throws {
        let runtime = try runtime()
        let result = try step(runtime, cursor: "m2", key: "left")
        #expect(result["cursor"] as? String == "h:g1")
        #expect(result["collapse"] as? String == "g1")
    }

    @Test func leftOnHeadersAndUngroupedRows() throws {
        let runtime = try runtime()
        let expanded = try step(runtime, cursor: "h:g1", key: "left")
        #expect(expanded["collapse"] as? String == "g1")
        #expect(expanded["cursor"] as? String == "h:g1")
        // Already collapsed: nothing to do, still consumed.
        let collapsed = try step(runtime, cursor: "h:g2", key: "left")
        #expect(collapsed["collapse"] == nil)
        #expect(collapsed["handled"] as? Bool == true)
        let ungrouped = try step(runtime, cursor: "a", key: "left")
        #expect(ungrouped["collapse"] == nil)
        #expect(ungrouped["cursor"] as? String == "a")
    }

    @Test func rightExpandsACollapsedHeaderOrStepsIn() throws {
        let runtime = try runtime()
        let collapsed = try step(runtime, cursor: "h:g2", key: "right")
        #expect(collapsed["expand"] as? String == "g2")
        #expect(collapsed["cursor"] as? String == "h:g2")
        let expanded = try step(runtime, cursor: "h:g1", key: "right")
        #expect(expanded["expand"] == nil)
        #expect(expanded["cursor"] as? String == "m1")
        let member = try step(runtime, cursor: "m1", key: "right")
        #expect(member["cursor"] as? String == "m1")
        #expect(member["expand"] == nil)
    }

    @Test func returnAndSpaceOpenRowsAndToggleHeaders() throws {
        let runtime = try runtime()
        #expect(try step(runtime, cursor: "m1", key: "return")["open"] as? String == "m1")
        #expect(try step(runtime, cursor: "a", key: "space")["open"] as? String == "a")
        let header = try step(runtime, cursor: "h:g2", key: "return")
        #expect(header["toggle"] as? String == "g2")
        #expect(header["open"] == nil)
        #expect(try step(runtime, cursor: "h:g1", key: "space")["toggle"] as? String == "g1")
    }

    @Test func escapeExitsAndOtherKeysAreUnhandled() throws {
        let runtime = try runtime()
        #expect(try step(runtime, cursor: "a", key: "escape")["exit"] as? Bool == true)
        #expect(try step(runtime, cursor: "a", key: "x")["handled"] as? Bool == false)
    }

    // MARK: - Host bridge

    @Test func onKeyResultsMapToHostDecisions() {
        let runtime = SidebarJSRuntime()
        #expect(runtime.start(source: """
        onKey((e) => {
          if (e.key === "down") return true;
          if (e.key === "escape") return { exit: true };
          if (e.key === "return") return { open: "w1" };
          return false;
        });
        sidebar(() => Text("x"))
        """))
        #expect(runtime.handlesKeys)
        #expect(runtime.dispatchKey(SidebarKeyPress(key: "down")) == SidebarKeyResult(handled: true))
        #expect(runtime.dispatchKey(SidebarKeyPress(key: "escape")) == SidebarKeyResult(handled: true, exit: true))
        #expect(runtime.dispatchKey(SidebarKeyPress(key: "return"))
            == SidebarKeyResult(handled: true, exit: true, openWorkspaceId: "w1"))
        #expect(runtime.dispatchKey(SidebarKeyPress(key: "q")) == .unhandled)
    }

    @Test func programWithoutOnKeyDoesNotHandleKeys() {
        let runtime = SidebarJSRuntime()
        #expect(runtime.start(source: "sidebar(() => Text(\"x\"))"))
        #expect(!runtime.handlesKeys)
        #expect(runtime.dispatchKey(SidebarKeyPress(key: "down")) == .unhandled)
    }

    @Test func keyboardModeSignalDrivesProps() throws {
        let runtime = SidebarJSRuntime()
        #expect(runtime.start(source: """
        let seen = "none";
        onKey(() => true);
        onKeyboardMode((on) => { seen = on ? "on" : "off"; });
        sidebar(() => Text(() => keyboardMode() ? "ring" : "plain"))
        """))
        let rootId = try #require(runtime.store.rootId)
        #expect(runtime.store.node(rootId)?.string("text") == "plain")
        runtime.setKeyboardMode(true)
        #expect(runtime.store.node(rootId)?.string("text") == "ring")
        #expect(runtime.evaluateForTesting("seen") == "on")
        runtime.setKeyboardMode(false)
        #expect(runtime.store.node(rootId)?.string("text") == "plain")
        #expect(runtime.evaluateForTesting("seen") == "off")
    }

    @Test func keyHandlerCanWriteClipboard() {
        let runtime = SidebarJSRuntime()
        var written: [String] = []
        runtime.dispatch = SidebarActionDispatch(run: { _ in }, writeClipboard: { written.append($0) })
        #expect(runtime.start(source: """
        onKey(() => clipboard.write("id"));
        sidebar(() => Text("x"))
        """))
        _ = runtime.dispatchKey(SidebarKeyPress(key: "y"))
        #expect(written == ["id"])
    }
}
