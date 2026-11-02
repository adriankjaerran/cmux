import Foundation

/// Target resolution shared by `terminal.input` / `terminal.paste`
/// (`Sources/TerminalInput/`) and, until they go, the phone-only `mobile.*`
/// bodies. The `mobile*` names are kept so those callers compile unchanged.
///
/// Accepts `surface_id`, `terminal_id` or `tab_id` (they must agree) and an
/// optional `workspace_id`; without a surface id the focused terminal of the
/// workspace wins, then the first terminal in spatial order.
extension TerminalController {
    enum MobileTerminalAliasUUID {
        case missing
        case value(UUID)
        case invalid
        case conflict
    }

    func mobileTerminalAliasUUID(params: [String: Any]) -> MobileTerminalAliasUUID {
        var selected: UUID?
        var sawAlias = false
        for key in ["surface_id", "terminal_id", "tab_id"] {
            guard v2HasNonNullParam(params, key) else {
                continue
            }
            sawAlias = true
            guard let candidate = v2UUID(params, key) else {
                return .invalid
            }
            if let selected, selected != candidate {
                return .conflict
            }
            selected = selected ?? candidate
        }
        if let selected {
            return .value(selected)
        }
        return sawAlias ? .invalid : .missing
    }

    func mobileTerminalAliasValidationError(params: [String: Any]) -> V2CallResult? {
        switch mobileTerminalAliasUUID(params: params) {
        case .missing, .value:
            return nil
        case .invalid:
            return .err(code: "invalid_params", message: "Missing or invalid terminal_id", data: nil)
        case .conflict:
            return .err(code: "invalid_params", message: "Conflicting terminal identifiers", data: nil)
        }
    }

    func mobileWorkspaceIDValidationError(params: [String: Any]) -> V2CallResult? {
        guard v2HasNonNullParam(params, "workspace_id"),
              v2UUID(params, "workspace_id") == nil else {
            return nil
        }
        return .err(code: "invalid_params", message: "Missing or invalid workspace_id", data: nil)
    }

    func mobileResolveWorkspaceAndSurface(
        params: [String: Any],
        requireTerminal: Bool
    ) -> (tabManager: TabManager, workspace: Workspace, surfaceId: UUID?)? {
        guard let tabManager = v2ResolveTabManager(params: params),
              let workspace = v2ResolveWorkspace(params: params, tabManager: tabManager) else {
            return nil
        }

        let requestedSurfaceId = v2UUID(params, "surface_id")
            ?? v2UUID(params, "terminal_id")
            ?? v2UUID(params, "tab_id")

        let surfaceId: UUID?
        if let requestedSurfaceId {
            if let target = workspace.terminalInputTarget(forPanelID: requestedSurfaceId) {
                surfaceId = target.surfaceID
            } else if !requireTerminal,
                      workspace.controlSurfaceTarget(for: requestedSurfaceId) != nil {
                // Non-terminal panel surfaces (markdown, file preview) have no
                // terminal input target; callers that don't require a terminal
                // (mobile.panel.artifact.*) resolve the workspace-owned surface
                // itself. Hidden remote-tmux mirror wrappers still fail closed
                // inside controlSurfaceTarget.
                surfaceId = requestedSurfaceId
            } else {
                return nil
            }
        } else if requireTerminal {
            surfaceId = workspace.focusedTerminalInputTarget()?.surfaceID
                ?? mobileTerminalPanels(in: workspace).first?.id
        } else {
            surfaceId = nil
        }

        // A session-restored / never-foregrounded terminal has its libghostty
        // surface created lazily — today only on the first keystroke (via the
        // input path's `requestBackgroundSurfaceStartIfNeeded`). The mobile
        // render-grid producer only reads a *live* surface, so such a terminal
        // shows blank on the phone until the user types. When a mobile client
        // resolves a terminal to read or drive, materialize the surface
        // headlessly so attaching alone loads it. Idempotent and a no-op once
        // the surface exists.
        if requireTerminal,
           let surfaceId,
           let owned = workspace.terminalInputTarget(forPanelID: surfaceId) {
            // Resolve the panel before asking the registry for a socket target.
            // Restored, never-foregrounded terminals are intentionally absent
            // from that registry until this request materializes their runtime.
            // Resolving the canonical target first made the on-demand start
            // unreachable for exactly the terminals mobile attach needs.
            owned.panel.surface.requestBackgroundSurfaceStartIfNeeded()
        }

        return (tabManager, workspace, surfaceId)
    }

    func mobileTerminalPanels(in workspace: Workspace) -> [TerminalPanel] {
        // Use the workspace's spatial (left-to-right, top-to-bottom) panel order
        // so the phone's terminal dropdown matches the on-screen bonsplit layout,
        // rather than focused-first/UUID order. `is_focused` in the payload still
        // tells the phone which terminal is active.
        orderedPanels(in: workspace).flatMap {
            workspace.terminalPanels(projectedFromPanelID: $0.id)
        }
    }

    /// Resolves a mobile terminal request to its structural workspace and
    /// canonical live socket target in one main-actor hop.
    func mobileCanonicalTerminalTarget(
        params: [String: Any]
    ) -> (
        workspace: Workspace,
        surfaceID: UUID,
        target: ControlTerminalSocketTarget
    )? {
        guard let resolved = mobileResolveWorkspaceAndSurface(
            params: params,
            requireTerminal: true
        ), let surfaceID = resolved.surfaceId,
              let target = resolved.workspace.controlSocketTerminalInputTarget(
                  for: surfaceID
              ) else {
            return nil
        }
        return (resolved.workspace, surfaceID, target)
    }
}
