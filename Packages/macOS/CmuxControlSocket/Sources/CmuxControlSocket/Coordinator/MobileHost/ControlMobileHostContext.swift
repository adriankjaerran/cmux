/// The mobile-host-domain slice of the control-command seam (a constituent of
/// the ``ControlCommandContext`` umbrella).
///
/// In this fork the phone and its `mobile.*` methods are gone. What is left
/// are the bare `terminal.create` / `terminal.replay` / `terminal.viewport` /
/// `terminal.scroll` / `terminal.mouse` methods, which upstream defines on the
/// v2 control socket and which stay advertised. The bare `terminal.input` /
/// `terminal.paste` live in the terminal-input domain.
///
/// Each seam method takes the coordinator's already-typed params and returns a
/// fully-built ``ControlCallResult``: the app conformance runs the legacy body
/// against live app state and bridges its Foundation payload to a
/// ``JSONValue``, so the wire bytes are unchanged and localized error strings
/// keep resolving against the app bundle.
@MainActor
public protocol ControlMobileHostContext: AnyObject, Sendable {
    /// `terminal.create`.
    func controlMobileTerminalCreate(params: [String: JSONValue]) -> ControlCallResult

    /// `terminal.replay`.
    func controlMobileTerminalReplay(params: [String: JSONValue]) -> ControlCallResult

    /// `terminal.viewport`.
    func controlMobileTerminalViewport(params: [String: JSONValue]) -> ControlCallResult

    /// `terminal.scroll`.
    func controlMobileTerminalScroll(params: [String: JSONValue]) -> ControlCallResult

    /// `terminal.mouse`.
    func controlMobileTerminalMouse(params: [String: JSONValue]) -> ControlCallResult
}
