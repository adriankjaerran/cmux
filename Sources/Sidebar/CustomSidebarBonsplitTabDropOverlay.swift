import AppKit
import Bonsplit
import CmuxFoundation
import CmuxSettings
import CmuxSwiftRenderUI
import QuartzCore
import SwiftUI

/// What dropping a Bonsplit tab onto a custom-sidebar row does. Derived from
/// the row's item key: a workspace UUID, or `h:<groupId>` for a group header
/// (an optional `:edit` suffix marks the row's inline-edit variant).
enum CustomSidebarBonsplitTabDropTarget: Equatable {
    case workspace(UUID)
    case group(UUID)

    init?(itemKey: String) {
        var key = itemKey
        if key.hasSuffix(":edit") { key.removeLast(":edit".count) }
        if key.hasPrefix("h:") {
            guard let groupId = UUID(uuidString: String(key.dropFirst(2))) else { return nil }
            self = .group(groupId)
        } else {
            guard let workspaceId = UUID(uuidString: key) else { return nil }
            self = .workspace(workspaceId)
        }
    }
}

/// Accepts Bonsplit tab drags over the custom (JS) sidebar and outlines the
/// row under the pointer. Row geometry comes from the sidebar's
/// ``SceneRowFrameReporter``, in the coordinate space of the container this
/// overlay covers (this view is flipped, so the two coincide).
@MainActor
final class CustomSidebarBonsplitTabDropView: NSView {
    private static let pasteboardType = NSPasteboard.PasteboardType(BonsplitTabDragPayload.typeIdentifier)

    var reporter: SceneRowFrameReporter?
    var canPerform: (CustomSidebarBonsplitTabDropTarget, BonsplitTabDragPayload.Transfer) -> Bool = { _, _ in false }
    var perform: (CustomSidebarBonsplitTabDropTarget, BonsplitTabDragPayload.Transfer) -> Bool = { _, _ in false }

    private let outlineLayer = CAShapeLayer()

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        outlineLayer.fillColor = nil
        outlineLayer.lineWidth = 2
        outlineLayer.isHidden = true
        layer?.addSublayer(outlineLayer)
        registerForDraggedTypes([Self.pasteboardType])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        shouldCaptureHitTest() ? super.hitTest(point) : nil
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        if newSuperview == nil { hideOutline() }
        super.viewWillMove(toSuperview: newSuperview)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        hideOutline()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        hideOutline()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        resolve(sender) != nil
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { hideOutline() }
        guard let (target, transfer, _) = resolve(sender) else { return false }
        let moved = perform(target, transfer)
        if moved {
            AppDelegate.shared?.finishAcceptedBonsplitTabDrop(from: sender.draggingPasteboard)
        }
#if DEBUG
        dlog("customSidebar.bonsplitDrop.perform moved=\(moved ? 1 : 0) target=\(target)")
#endif
        return moved
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {
        hideOutline()
    }

    private func updateDrag(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let (_, _, row) = resolve(sender) else {
            hideOutline()
            return []
        }
        showOutline(row)
        return .move
    }

    private func resolve(
        _ sender: any NSDraggingInfo
    ) -> (CustomSidebarBonsplitTabDropTarget, BonsplitTabDragPayload.Transfer, SceneRowFrameReporter.Row)? {
        let pasteboard = sender.draggingPasteboard
        guard pasteboard.types?.contains(Self.pasteboardType) == true,
              let transfer = BonsplitTabDragPayload.transfer(
                  from: pasteboard,
                  registry: AppDelegate.shared?.tabDragTransferRegistry
              ),
              let row = reporter?.row(at: convert(sender.draggingLocation, from: nil)),
              let target = CustomSidebarBonsplitTabDropTarget(itemKey: row.key),
              canPerform(target, transfer) else {
            return nil
        }
        return (target, transfer, row)
    }

    private func showOutline(_ row: SceneRowFrameReporter.Row) {
        let rect = row.frame.insetBy(dx: 1, dy: 1)
        let radius = max(0, min(row.cornerRadius, min(rect.width, rect.height) / 2))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outlineLayer.frame = bounds
        outlineLayer.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        outlineLayer.strokeColor = NSColor.controlAccentColor.cgColor
        outlineLayer.isHidden = false
        CATransaction.commit()
    }

    private func hideOutline() {
        guard !outlineLayer.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outlineLayer.isHidden = true
        outlineLayer.path = nil
        CATransaction.commit()
    }

    /// Captures hit-testing only while a Bonsplit tab drag is in flight, so
    /// clicks, hovers, and the sidebar's own reorder gesture pass through.
    private func shouldCaptureHitTest() -> Bool {
        let eventType = NSApp.currentEvent?.type
        guard WindowInputRoutingContext.allowsWorkspaceDropOverlayHitTesting(eventType: eventType) else {
            return false
        }
        return BonsplitTabDragPayload.transfer(
            from: NSPasteboard(name: .drag),
            registry: AppDelegate.shared?.tabDragTransferRegistry
        ) != nil
    }
}

/// SwiftUI mount for ``CustomSidebarBonsplitTabDropView``. Place it as an
/// overlay on the container that declares
/// ``SceneRowFrameReporter/coordinateSpaceName``.
@MainActor
struct CustomSidebarBonsplitTabDropOverlay: NSViewRepresentable {
    let reporter: SceneRowFrameReporter
    /// The window's workspace list the sidebar shows (and groups live in).
    let tabManager: TabManager

    func makeNSView(context: Context) -> CustomSidebarBonsplitTabDropView {
        CustomSidebarBonsplitTabDropView()
    }

    func updateNSView(_ nsView: CustomSidebarBonsplitTabDropView, context: Context) {
        nsView.reporter = reporter
        let tabManager = tabManager
        nsView.canPerform = { [weak tabManager] target, transfer in
            guard let tabManager else { return false }
            return Self.canPerform(target, transfer: transfer, tabManager: tabManager)
        }
        nsView.perform = { [weak tabManager] target, transfer in
            guard let tabManager else { return false }
            return Self.perform(target, transfer: transfer, tabManager: tabManager)
        }
    }

    private static func canPerform(
        _ target: CustomSidebarBonsplitTabDropTarget,
        transfer: BonsplitTabDragPayload.Transfer,
        tabManager: TabManager
    ) -> Bool {
        guard let app = AppDelegate.shared,
              let source = app.locateBonsplitSurface(tabId: transfer.tab.id) else { return false }
        switch target {
        case .workspace(let workspaceId):
            guard source.workspaceId != workspaceId else { return false }
            return app.canMoveBonsplitTab(tabId: transfer.tab.id, toWorkspace: workspaceId)
        case .group(let groupId):
            guard tabManager.workspaceGroups.contains(where: { $0.id == groupId }) else { return false }
            if app.canMoveBonsplitTabToNewWorkspace(tabId: transfer.tab.id) { return true }
            return wholeWorkspaceFallbackIsPossible(source: source, groupId: groupId, tabManager: tabManager)
        }
    }

    private static func perform(
        _ target: CustomSidebarBonsplitTabDropTarget,
        transfer: BonsplitTabDragPayload.Transfer,
        tabManager: TabManager
    ) -> Bool {
        guard let app = AppDelegate.shared else { return false }
        switch target {
        case .workspace(let workspaceId):
            guard app.canMoveBonsplitTab(tabId: transfer.tab.id, toWorkspace: workspaceId) else { return false }
            return app.moveBonsplitTab(
                tabId: transfer.tab.id,
                toWorkspace: workspaceId,
                focus: true,
                focusWindow: true
            )
        case .group(let groupId):
            if app.canMoveBonsplitTabToNewWorkspace(tabId: transfer.tab.id) {
                guard let result = app.moveBonsplitTabToNewWorkspace(
                    tabId: transfer.tab.id,
                    destinationManager: tabManager,
                    focus: true,
                    focusWindow: true
                ) else { return false }
                tabManager.addWorkspaceToGroup(
                    workspaceId: result.destinationWorkspaceId,
                    groupId: groupId,
                    placement: .end
                )
                return true
            }
            // The tab is its workspace's only panel: move the whole
            // workspace into the group instead.
            guard let source = app.locateBonsplitSurface(tabId: transfer.tab.id),
                  wholeWorkspaceFallbackIsPossible(source: source, groupId: groupId, tabManager: tabManager) else {
                return false
            }
            tabManager.addWorkspaceToGroup(
                workspaceId: source.workspaceId,
                groupId: groupId,
                placement: .end
            )
            return true
        }
    }

    /// The single-panel fallback only works within this window (groups are
    /// per-TabManager) and only when the workspace is not already a member.
    private static func wholeWorkspaceFallbackIsPossible(
        source: (windowId: UUID, workspaceId: UUID, panelId: UUID, tabManager: TabManager),
        groupId: UUID,
        tabManager: TabManager
    ) -> Bool {
        guard source.tabManager === tabManager,
              let workspace = tabManager.tabs.first(where: { $0.id == source.workspaceId }) else { return false }
        return workspace.groupId != groupId
    }
}
