import CMUXDebugLog
import CmuxControlSocket
import Foundation

/// `terminal.input`: write raw text to a terminal. Same body and wire contract
/// as the phone's `mobile.terminal.input`, without the phone-only parts (input
/// delivery / acknowledgement, viewport report, byte tee, `terminal_seq`).
extension TerminalController: ControlTerminalInputContext {
    func v2TerminalInput(params: [String: Any]) -> V2CallResult {
        guard let text = v2RawString(params, "text"), !text.isEmpty else {
            return .err(code: "invalid_params", message: "Missing text", data: nil)
        }
        if let error = mobileWorkspaceIDValidationError(params: params) {
            return error
        }
        if let error = mobileTerminalAliasValidationError(params: params) {
            return error
        }
        guard let resolved = mobileCanonicalTerminalTarget(params: params) else {
            return .err(code: "not_found", message: "Terminal surface not found", data: nil)
        }
        let surfaceId = resolved.surfaceID
        let terminalTarget = resolved.target
        let terminalPanel = terminalTarget.panel

        let sendResult = terminalTarget.sendInputResult(text)
        switch sendResult {
        case .sent, .queued:
            break
        case .inputQueueFull:
            return terminalInputWriteFailure(code: "input_queue_full", message: Self.terminalInputQueueFullMessage, surfaceID: surfaceId)
        case .surfaceUnavailable:
            return terminalInputWriteFailure(code: "surface_unavailable", message: Self.terminalSurfaceUnavailableMessage, surfaceID: surfaceId)
        case .processExited:
            return terminalInputWriteFailure(code: "process_exited", message: Self.terminalProcessExitedMessage, surfaceID: surfaceId)
        }
        #if DEBUG
        cmuxDebugLog(
            "terminal.input workspace=\(resolved.workspace.id.uuidString.prefix(8)) surface=\(surfaceId.uuidString.prefix(8)) queued=\(sendResult == .queued ? 1 : 0) chars=\(text.count)"
        )
        #endif
        return .ok([
            "workspace_id": resolved.workspace.id.uuidString,
            "surface_id": terminalPanel.id.uuidString,
            "queued": sendResult == .queued,
        ])
    }

    /// `ControlTerminalInputContext` witness for `terminal.input`.
    func controlTerminalInput(params: [String: JSONValue]) -> ControlCallResult {
        terminalInputControlResult(v2TerminalInput(params: params.mapValues(\.foundationObject)))
    }
}
