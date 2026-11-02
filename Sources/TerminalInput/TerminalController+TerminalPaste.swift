import CMUXDebugLog
import CmuxControlSocket
import Foundation

/// `terminal.paste`: the local paste path (`cmux send --paste`, `cmux paste`,
/// tmux-compat `paste-buffer`, Feed replies, notification replies).
///
/// Same body and wire contract as the phone's `mobile.terminal.paste`, without
/// the phone-only parts: no exactly-once input delivery / acknowledgement, no
/// piggybacked phone viewport report, no `terminal_seq`.
extension TerminalController {
    /// Pastes `text` into the resolved terminal surface, then optionally sends
    /// a submit key in a separate input turn.
    ///
    /// `submit_key` is optional: `return`/`enter` (default) or `ctrl+enter`
    /// submit; `none` pastes without submitting.
    func v2TerminalPaste(params: [String: Any]) async -> V2CallResult {
        guard let text = v2RawString(params, "text"), !text.isEmpty else {
            return .err(code: "invalid_params", message: "Missing text", data: nil)
        }
        // Resolve the optional submit key up front so an unsupported value fails
        // before any text is pasted (no partial application). `return` is a
        // submit *intent*; the agent-aware upgrade to `ctrl+enter` happens below
        // once the surface (and its agent context) is resolved.
        let submitKeyRaw = (v2String(params, "submit_key") ?? "return").lowercased()
        var submitKeyName: String?
        var submitKeyWasReturnIntent = false
        switch submitKeyRaw {
        case "", "return", "enter":
            submitKeyName = "return"
            submitKeyWasReturnIntent = true
        case "ctrl+enter":
            submitKeyName = "ctrl+enter"
        case "none":
            submitKeyName = nil
        default:
            return .err(code: "invalid_params", message: "Unsupported submit_key", data: ["submit_key": submitKeyRaw])
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

        guard terminalPasteInFlightSurfaceIDs.insert(surfaceId).inserted else {
            return .err(code: "busy", message: "A prompt is already being submitted to this terminal", data: nil)
        }
        defer { terminalPasteInFlightSurfaceIDs.remove(surfaceId) }

        // Mirror the macOS TextBox composer's submit-key selection
        // (`TextBoxInput.dispatchEvents`): Claude Code needs `ctrl+enter` to
        // submit a multi-line block, while plain `return` submits a newline mid
        // prompt. Upgrade a `return` intent here when the surface is Claude and
        // the text spans multiple lines. Explicit `ctrl+enter`/`none` are
        // honored as-is.
        if submitKeyWasReturnIntent {
            submitKeyName = TextBoxAgentDetection.composedPromptSubmitKey(
                containsNewline: text.contains("\n") || text.contains("\r"),
                context: WorkspaceContentView.terminalAgentContext(panel: terminalPanel, workspace: resolved.workspace)
            )
        }

        // Send through the TerminalPanel explicit-input wrappers (not the raw
        // surface): they run `resumeForExplicitInputIfNeeded()` first, waking a
        // hibernated agent terminal the same way local typing does.
        let textResult = terminalTarget.sendTextResult(text)
        switch textResult {
        case .sent, .queued:
            break
        case .inputQueueFull:
            return terminalInputWriteFailure(code: "input_queue_full", message: Self.terminalInputQueueFullMessage, surfaceID: surfaceId)
        case .surfaceUnavailable:
            return terminalInputWriteFailure(code: "surface_unavailable", message: Self.terminalSurfaceUnavailableMessage, surfaceID: surfaceId)
        case .processExited:
            return terminalInputWriteFailure(code: "process_exited", message: Self.terminalProcessExitedMessage, surfaceID: surfaceId)
        }

        // The paste text is already accepted by the surface above. From here on a
        // submit-key failure must NOT surface as an RPC error: callers treat any
        // error as "nothing was sent", so a retry would paste the whole block a
        // second time. Report partial success instead (`submitted: false` plus
        // `submit_error`).
        var submitted = false
        var submitError: String?
        if let submitKeyName {
            // Gemini's editor treats Enter during its 40 ms paste-protection
            // window as a newline. React-based editors can also process paste
            // and Enter in one render with a stale, empty input buffer. Keep a
            // separate input turn, with margin for the documented cooldown.
            let generation = terminalTarget.surface.runtimeSurfaceGeneration
            do {
                try await Task.sleep(for: .milliseconds(150))
            } catch {
                return .ok([
                    "workspace_id": resolved.workspace.id.uuidString,
                    "surface_id": surfaceId.uuidString,
                    "submitted": false,
                    "submit_error": "cancelled",
                ])
            }
            // Closing/replacing a terminal during the suspension must never
            // send Enter into a different process or a newly created surface.
            guard let current = mobileCanonicalTerminalTarget(params: params)?.target,
                  current.surface === terminalTarget.surface,
                  current.surface.runtimeSurfaceGeneration == generation else {
                return .ok([
                    "workspace_id": resolved.workspace.id.uuidString,
                    "surface_id": surfaceId.uuidString,
                    "submitted": false,
                    "submit_error": "surface_changed",
                ])
            }
            let keyResult = current.sendNamedKeyResult(submitKeyName)
            if keyResult.accepted {
                submitted = true
            } else {
                switch keyResult {
                case .inputQueueFull:
                    submitError = "input_queue_full"
                case .surfaceUnavailable:
                    submitError = "surface_unavailable"
                case .processExited:
                    submitError = "process_exited"
                case .unknownKey, .sent, .queued:
                    // .sent / .queued are accepted results and unreachable in this
                    // else-branch; grouped here only to keep the switch exhaustive.
                    submitError = "unknown_key"
                }
            }
        }

        terminalTarget.forceRefresh(reason: "terminalInput.paste")

        if submitted,
           let rawEventID = v2String(params, "feed_event_id"),
           let eventID = UUID(uuidString: rawEventID) {
            _ = FeedCoordinator.shared.store?.recordTerminalReply(eventID, text: text)
        }

        #if DEBUG
        cmuxDebugLog(
            "terminal.paste workspace=\(resolved.workspace.id.uuidString.prefix(8)) surface=\(surfaceId.uuidString.prefix(8)) chars=\(text.count) submitted=\(submitted ? 1 : 0)"
        )
        #endif

        var payload: [String: Any] = [
            "workspace_id": resolved.workspace.id.uuidString,
            "surface_id": terminalPanel.id.uuidString,
            "delivery": textResult == .sent ? "delivered" : "queued",
            "submitted": submitted,
        ]
        if let submitError {
            payload["submit_error"] = submitError
        }
        return .ok(payload)
    }

    /// A write the terminal refused, as the plain RPC error the CLI expects.
    func terminalInputWriteFailure(code: String, message: String, surfaceID: UUID) -> V2CallResult {
        .err(code: code, message: message, data: ["surface_id": surfaceID.uuidString])
    }

    /// `ControlTerminalInputContext` witness for `terminal.paste`.
    func controlTerminalPaste(params: [String: JSONValue]) async -> ControlCallResult {
        terminalInputControlResult(await v2TerminalPaste(params: params.mapValues(\.foundationObject)))
    }

    /// Bridges a Foundation-shaped `V2CallResult` to the typed
    /// `ControlCallResult` (same bridge as the other coordinator witnesses).
    nonisolated func terminalInputControlResult(_ result: V2CallResult) -> ControlCallResult {
        switch result {
        case let .ok(payload):
            return .ok(JSONValue(foundationObject: payload) ?? .object([:]))
        case let .err(code, message, data):
            return .err(
                code: code,
                message: message,
                data: data.flatMap { JSONValue(foundationObject: $0) }
            )
        }
    }
}
