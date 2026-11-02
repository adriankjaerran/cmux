/// The local terminal-input slice of the control-command seam (a constituent
/// of the ``ControlCommandContext`` umbrella): `terminal.input` and
/// `terminal.paste`.
///
/// `cmux send --paste`, `cmux paste` and tmux-compat `paste-buffer` use
/// `terminal.paste`; `terminal.input` stays on the wire for scripts. Both used
/// to live in the mobile-host domain (as bare aliases of `mobile.terminal.*`);
/// they are served here so the local path does not depend on the phone code.
///
/// Like the mobile-host seam, each method takes the coordinator's typed params
/// and returns a fully-built ``ControlCallResult``: the app conformance runs the
/// body against live app state and bridges its Foundation payload, keeping the
/// localized terminal error strings resolving against the app bundle.
@MainActor
public protocol ControlTerminalInputContext: AnyObject, Sendable {
    /// `terminal.input` — write text to the resolved terminal surface.
    ///
    /// - Parameter params: The decoded request params.
    /// - Returns: The fully-built command result.
    func controlTerminalInput(params: [String: JSONValue]) -> ControlCallResult

    /// `terminal.paste` — paste text into the resolved terminal surface, then
    /// optionally send a submit key in a separate input turn.
    ///
    /// - Parameter params: The decoded request params.
    /// - Returns: The fully-built command result.
    func controlTerminalPaste(params: [String: JSONValue]) async -> ControlCallResult
}
