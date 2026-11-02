import CMUXMobileCore
import CmuxAgentChat
import CmuxControlSocket
import Foundation

/// Workspace surface inventory for the `terminal.create` / workspace-list payloads
/// (the former phone payload shape, still returned by `terminal.create`).
extension TerminalController {
    /// Maps an app panel kind to the shared, open mobile wire vocabulary.
    func mobileSurfaceKind(for panelType: PanelType) -> MobileSurfaceKind {
        switch panelType {
        case .terminal:
            return .terminal
        case .browser:
            return .browser
        case .markdown:
            return .markdown
        case .filePreview:
            return .filePreview
        case .rightSidebarTool:
            return .rightSidebarTool
        case .customSidebar:
            return .customSidebar
        case .agentSession:
            return .agentSession
        case .project:
            return .project
        case .extensionBrowser:
            return .extensionBrowser
        case .workspaceTodo:
            return .todo
        case .coderouterGuide:
            // Phones without a native renderer show the fallback card.
            return MobileSurfaceKind(rawValue: "coderouterGuide")
        case .notifications:
            // Notifications use the open-vocabulary fallback until the phone
            // provides a native renderer for this panel kind.
            return MobileSurfaceKind(rawValue: "notifications")
        case .cloudVMLoading:
            return .cloudVMLoading
        case .simulator:
            // Open wire vocabulary: phones without a native renderer show the
            // fallback card for this kind (design: unknown kinds stay cards).
            return MobileSurfaceKind(rawValue: "simulator")
        case .mobilePairing:
            return MobileSurfaceKind(rawValue: "mobilePairing")
        case .accountSignIn:
            return MobileSurfaceKind(rawValue: "accountSignIn")
        case .cloudVPNSetup:
            return MobileSurfaceKind(rawValue: "cloudVPNSetup")
        case .chief:
            // Open vocabulary: phones show the fallback card until they render Chief natively.
            return MobileSurfaceKind(rawValue: "chief")
        }
    }

    /// Builds the stable, spatially ordered mobile descriptors for every panel.
    func mobileSurfaceDescriptors(in workspace: Workspace) -> [WorkspaceSyncRecord.Surface] {
        orderedPanels(in: workspace).map { panel in
            let filePath: String?
            switch panel {
            case let markdown as MarkdownPanel:
                filePath = markdown.filePath
            case let filePreview as FilePreviewPanel:
                filePath = filePreview.filePath
            default:
                filePath = nil
            }
            if let filePath {
                panelArtifactAuthorizationStore.record(
                    workspaceID: workspace.id.uuidString,
                    surfaceID: panel.id.uuidString,
                    filePath: filePath
                )
            } else {
                panelArtifactAuthorizationStore.invalidate(
                    workspaceID: workspace.id.uuidString,
                    surfaceID: panel.id.uuidString
                )
            }
            return WorkspaceSyncRecord.Surface(
                surfaceID: panel.id.uuidString,
                kind: mobileSurfaceKind(for: panel.panelType).rawValue,
                title: workspace.panelTitle(panelId: panel.id) ?? panel.displayTitle,
                filePath: filePath,
                todo: panel.panelType == .workspaceTodo ? mobileTodoSnapshot(in: workspace) : nil,
                isFocused: panel.id == workspace.focusedPanelId
            )
        }
    }

    /// Projects the workspace-owned todo model without carrying Mac-local attachments.
    func mobileTodoSnapshot(in workspace: Workspace) -> MobileTodoSnapshot {
        let status: MobileTodoStatus = switch workspace.effectiveTaskStatus {
        case .todo: .todo
        case .working: .working
        case .needsAttention: .needsAttention
        case .review: .review
        case .done: .done
        }
        return MobileTodoSnapshot(
            status: status,
            statusHidden: workspace.todoState.statusHidden,
            items: workspace.todoState.checklist.map { item in
                let state: MobileTodoItemState = switch item.state {
                case .pending: .pending
                case .inProgress: .inProgress
                case .completed: .completed
                }
                let origin: MobileTodoItemOrigin = switch item.origin {
                case .user: .user
                case .agent: .agent
                }
                return MobileTodoItem(
                    id: item.id.uuidString,
                    text: item.text,
                    state: state,
                    origin: origin
                )
            }
        )
    }

    /// Bridges a typed todo snapshot into the legacy workspace-list JSON shape.
    func mobileTodoPayload(_ todo: MobileTodoSnapshot) -> [String: Any] {
        [
            "status": todo.status.rawValue,
            "status_hidden": todo.statusHidden,
            "items": todo.items.map { item in
                [
                    "id": item.id,
                    "text": item.text,
                    "state": item.state.rawValue,
                    "origin": item.origin.rawValue,
                ]
            },
        ]
    }

    func mobileNonEmpty(_ raw: String?) -> String? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    /// Stable positive correlation ID for one browser panel. Still read by the
    /// phone browser stream in `Sources/Mobile` (removed in Phase 9.14).
    static func mobileBrowserPanelCorrelation(_ id: UUID) -> Int {
        let bytes = id.uuid
        let value = (UInt32(bytes.0) << 24) | (UInt32(bytes.1) << 16) | (UInt32(bytes.2) << 8) | UInt32(bytes.3)
        return Int(value & 0x7FFF_FFFF)
    }
}
