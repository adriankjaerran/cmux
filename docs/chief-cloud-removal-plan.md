# Removal plan: Chief, Cloud, Account, Mobile and the rest of upstream's servers

Written 2026-11-02 against `1654d6a`. This plan splits Phases 8 and 9 of [removal-plan.md](removal-plan.md)
into small steps. Nothing in it is done yet.

✅ done · ⬜ open · Size: S = under an hour, M = a few hours, L = a day or more.

**22 steps** (4 for Chief, 18 for Cloud and the rest). About **9–10 working days** in all, builds included.
Each step builds on its own and is one commit. Never two steps in one build.

## Read this first

- **Wait for the CodeRouter work.** Another worker is removing CodeRouter right now. It touches `CLI/cmux.swift`,
  `CLI/Commands/CmuxCommand.swift`, `CLI/CMUXCLI+VMTransfer.swift`, `Sources/Workspace.swift`,
  `Sources/SessionPersistence.swift`, `Sources/Cloud/*Coderouter*`, `scripts/reload.sh` and the pbxproj. Start
  only after that commit has landed. Line numbers below are from `1654d6a` and will move.
- **Order:** hide → stub → delete. First the user can't reach it. Then nothing calls it. Then the code goes.
- **Rules from removal-plan.md still hold:**
  1. Don't change `SessionPersistence.currentVersion` (stays `1`).
  2. Optional session fields (`chief`, `cloudVM`, `cloudMachineTeams`, …) may go. The decoder ignores unknown keys.
  3. Don't remove cases from `PanelType` (`Sources/Panels/Panel.swift`): keep `.chief`, `.cloudVMLoading`,
     `.mobilePairing`, `.accountSignIn`, `.cloudVPNSetup`. They restore as nothing. Same for other stored enums:
     `SurfaceKind.chief`, `DockControlDefinition` kind `.chief`, `RightSidebarMode.machines`.
  4. Keep the `chief` key (and its `enabled`, `harness`, `model`, `effort` children) in
     `CmuxConfigSchema.generated.swift`. `~/.config/cmux/cmux.json` has `"chief": { "enabled": false }`.
  5. Socket methods your scripts use must keep working as upstream defines them (the NIGHTLY CLI calls them).
- **Your session files have no Chief or Cloud data.** Checked today: Personal has 17 terminal and 5 browser panels,
  groups Fabstack, Personal, Hoegh, Obsidian, Schjødt, no `cmux.chief.home` group, no `cloudVM`, no `remote`.
  Both apps have `chiefEnabled = 0` and no `cloud.*`, `auth.*` or `mobile*` defaults except `mobileHost.deviceID`.
  You were never signed in.
- **The `cmuxTests` folder isn't in this repo**, so the test target can't build anyway. But it still lists
  package products in the pbxproj. When a package goes, remove it from **both** the `cmux` and `cmuxTests`
  targets. A dangling product reference breaks package resolution for the whole project.

### How to edit the pbxproj

The project lists every file by hand (no synced folders). Deleting a Swift file means removing four kinds of
lines: the `PBXFileReference`, the group child, the `PBXBuildFile` that points at that file ref, and the
`Sources` build-phase line with that build-file id. Removing a package means: the `XCLocalSwiftPackageReference`
block, its line in `packageReferences`, the `XCSwiftPackageProductDependency` blocks, the `… in Frameworks`
`PBXBuildFile` lines and their lines in each target's Frameworks phase and `packageProductDependencies`.
`git show 7e6c136 -- cmux.xcodeproj/project.pbxproj` is a clean example (CmuxFeedback, 12 lines).

For the big steps, write a small script in `/tmp` that takes a list of paths, finds their ids and drops every line
that names them. Run it, then `plutil -lint cmux.xcodeproj/project.pbxproj` and build.

### After deleting packages: stale bundles

Xcode doesn't prune old resource bundles from an incremental build. After a step that deletes a package, check
`ls "<test app>/Contents/Resources" | grep -E "Chief|HomeRender|MessagesLab|AgentQuestion|Cloud|Iroh"`. If any
are left, delete the built test app once (`~/Library/Developer/Xcode/DerivedData/cmux-test/Build/Products/Debug/cmux DEV test.app`)
and rebuild. Check the same in `~/Applications/cmux Personal.app` after the final install.

---

## Standard checks (do these after every step)

- ⬜ `./scripts/test-app.sh --seed` (it runs `reload.sh --tag test --no-global-cli-links` with
  `CMUX_DEV_BACKEND_MODE=local CMUX_DEV_CLOUD_ENABLED=0`) builds and opens **cmux DEV test** with your layout.
- ⬜ All groups and workspaces come back, the pinned cmux row is first.
- ⬜ A new zsh terminal shows folder and git branch in the sidebar.
- ⬜ `claude` and `pi` start through the shims and show `run` / `wait` / `idle`. A notification shows the red number.
- ⬜ The cmux agent works: `cmux_overview`, `cmux_sessions`, `cmux_send` with **multi-line** text (that's
  `send --paste`), `cmux_message_agent`, `cmux_config`.
- ⬜ `T="$HOME/Library/Developer/Xcode/DerivedData/cmux-test/Build/Products/Debug/cmux DEV test.app/Contents/Resources/bin/cmux"`,
  **and `export CMUX_SOCKET_PATH=/tmp/cmux-debug-test.sock; unset CMUX_WORKSPACE_ID CMUX_SURFACE_ID CMUX_TAB_ID`**
  (shells inside cmux Personal point at `/tmp/cmux-debug-mine.sock`; without this the checks hit Personal), then `"$T" --version`, `"$T" config doctor` (clean), `"$T" tree --all`.
- ⬜ ⌘Q the test app and open it again: everything comes back.
- ⬜ Commit. Don't install into cmux Personal until the end (see the last section).

Step-specific checks are listed under each step.

---

## Phase 8: Chief and Chief Home

**What it is:** Chief is upstream's built-in "manager" agent with its own pane, memory, and a "Home" group
(`cmux.chief.home`) that can't be unpinned or deleted. Home is the chat screen behind it. You already run with
`chief.enabled: false` and use your pinned cmux agent instead.

**Size:** ~8,100 (`CmuxChief`) + 6,300 (`CmuxHomeCore`) + 5,500 (`CmuxHomeRender`) + 37,100 (`CmuxMessagesLab`)
+ 900 (`CmuxAgentQuestion`) lines in packages, `Sources/Chief/` (35 files), ~15 other app files.

**Keep:** `isAgentHome`, `setAgentHome`, `agentHomeCommand` and everything in `TabManager+NonInteractiveClose.swift`
and `Workspace+TerminalRespawn.swift`. `agent message` / `agent.message.*` (not Chief). `cmux claude-teams` /
`codex-teams` (Claude Agent Teams, local).

### ✅ 8.1 Chief off for good (S, very low risk)

**Done:** commit "Phase 8.1: Chief off for good". As planned. `startChiefIfEnabled()` body is now empty (no
early `return` before dead code). The Home-group drop on restore matches the literal `"cmux.chief.home"` (not
`ChiefHomeNavigation.homeGroupExternalID`) so it survives 8.3/8.4. Checked by CLI: build, `--version`,
`config doctor` clean. Correction (written in 8.2): the 8.1 `tree`/`capabilities`/`claude` checks went to
cmux Personal, not the test app, because `CMUX_SOCKET_PATH=/tmp/cmux-debug-mine.sock` is set in shells inside
Personal. They were redone against the test app after 8.2 (see 8.2). Not checked (needs clicking): ⌘⇧P, View menu, pinned row, group
unpin/delete, ⌘Q restore, cmux agent tools, notifications.

**What it removes:** nothing yet. Chief can no longer be switched on, and the Home rules stop applying.
This is `plan.md` Phase 2 folded in.

**Edits:**
- `Sources/ChiefSettingsBridge.swift`: `ChiefSettings.isEnabled` always returns `false` (fork comment). This hides
  the View menu item (`cmuxApp.swift` ~1241), the ⌘⇧P entries (`ContentView+ViewCommandPalette.swift` 62, 70, 181),
  the `openChief` shortcut (`AppDelegate.swift` ~15179), and the `chief.*` entries in `system.capabilities`
  (`TerminalController+Capabilities.swift` ~506).
- `Sources/AppDelegate+Chief.swift`: `startChiefIfEnabled()` returns at once (called from `AppDelegate.swift:1639`).
- `Sources/Workspace+ChiefPane.swift`: `isChiefHome` returns `false`. So `isProtectedHome` (`Workspace.swift:2901`)
  becomes `isAgentHome` in effect. Don't edit `isProtectedHome` itself yet.
- `Sources/TabManager.swift` `isChiefHomeGroup` (~2451): return `false`. Groups can then be unpinned and deleted.
- On restore, drop a group whose `externalID == "cmux.chief.home"` (`TabManager.swift`, where `workspaceGroups`
  are restored) and skip a `.chief` panel in `Workspace.swift` ~2418 (return `nil`). A workspace left with no panels
  is dropped as today.

**Stub returns:** `isEnabled` → `false`, `isChiefHome` → `false`, `isChiefHomeGroup` → `false`.

**Build edits:** none.

**Risk:** very low. Your layout has no Home group. The ContentView `chiefEnabled` `@AppStorage` (~994) may still
flip UI on a config change; with `isEnabled` false the views it gates find nothing to show.

- ⬜ Standard checks.
- ⬜ ⌘⇧P "chief" finds nothing. View menu has no "Open Chief".
- ⬜ The pinned cmux row still can't be closed or unpinned. Close its terminal: a fresh agent starts.
- ⬜ A group (e.g. Obsidian) can be unpinned and deleted.

### ✅ 8.2 Chief commands, menus, settings card and shortcut (M, low risk)

**Done:** commit "Phase 8.2: ...". Differs from the plan:
- `Sources/Chief/ChiefSettingsCard.swift`, `ChiefSettingsPanel.swift`, `ChiefSettingsActions.swift`,
  `ChiefSettingsBrainHint.swift`, `ChiefSettingsStrings.swift` are **kept**: they are the settings drawer inside the
  Chief pane (`ChiefTranscriptView`), not the Settings window card. They go with the rest of `Sources/Chief/` in 8.4.
- Also removed: the `palette.newChiefSplit` palette command, the View menu `chiefEnabled` `@AppStorage` in
  `cmuxApp.swift`, the `chief.*` mobile route in `TerminalController.swift` (`chiefMobileResult`), the
  `chief.*` async route in `TerminalController+ControlSocketAsync.swift`, `chief` from `topLevelCommandNames`
  (`CMUXCLI+CommandSuggestions.swift`), the `chief` pre-focus rule (`CMUXCLI+WindowDispatch.swift`), the `chief …`
  lines in `CMUXCLI+TaskHelp.swift`, the `ChiefCommand` facade (`CLI/Commands/SystemCommands.swift`), and the
  pbxproj entries of the missing test files `CLIChiefDispatchPlanTests.swift` and `ChiefControlRequestTests.swift`.
  The chief rows in `ControlCommandExecutionPolicyTests.swift` went too.
- `SidebarChiefHomeRow.shortcutKeys` now returns `nil` (it read `.openChief`); the row goes in 8.3.
- Left for Phase 9: `chief.*` entries in `Sources/Mobile/MobileHostService+Capabilities.swift` and
  `+TicketAuthorization.swift`; the relay deny-list for `chief.*` in `CmuxRemoteWorkspace`. Localized strings
  for the removed text are left in the `.xcstrings` files.
- `new-pane`/`new-surface --type chief` stay until 8.3.
Checked against the test app: `--version`, `config doctor` clean (cmux.json still has `"chief"`), `tree --all`
has the same workspace names as Personal, `chief status` → "Unknown command 'chief'", `rpc chief.status` →
`method_not_found`, `config get chief.enabled` → `false`, no `chief` in `system.capabilities`, a new terminal
running `claude` showed `claude_code=Idle`, then `Running` during a prompt, then `Idle`; closing it cleared the
status.

**What it removes:** every way to reach Chief: `cmux chief …`, the `chief.*` socket methods, the Chief card in
Settings → Automation, the "Open Chief" menu item, palette commands and shortcut.

**Files:**
- CLI: delete `CLI/CMUXCLI+Chief.swift`, `CLI/CMUXCLI+ChiefDispatch.swift`, `CLI/ChiefDispatchPlan.swift`. Remove
  `case "chief"` in `CLI/cmux.swift` (~7267 and the help switch ~19799, ~22197 `chiefDispatchUsage`), and its
  entry in the ArgumentParser tree if there is one (`CLI/Commands/CmuxCommand.swift`). Remove `chief` from the
  help topic lists. `ChiefDispatchPlan.swift` is also in `cmuxCLITests`; drop it there too.
- Socket: delete `Sources/TerminalController+Chief.swift` and `Sources/Chief/ChiefControlRequest.swift`. Remove
  the `chief.*` lines in `Packages/macOS/CmuxControlSocket/.../Wire/ControlCommandExecutionPolicy.swift` and in
  `TerminalController+Capabilities.swift`.
- Settings: delete `Packages/macOS/CmuxSettingsUI/.../Sections/ChiefSettingsCard.swift`; remove its use in
  `AutomationSection.swift` and `Navigation/CuratedSettingEntry+Default.swift`. Remove the `chief` row in
  `Sources/SettingsSearchIndex.swift` (204, 393). Delete `Sources/Chief/ChiefSettingsCard.swift`,
  `ChiefSettingsPanel.swift`, `ChiefSettingsActions.swift`, `ChiefSettingsBrainHint.swift`, `ChiefSettingsStrings.swift`.
- Shortcut: remove `openChief` from `ShortcutAction` and `+Defaults`, `+DisplayName`, `+Group`,
  `ShortcutKeymapPreset.swift`, `KeyboardShortcutSettings.swift` (3), `AppDelegate.swift` (2),
  `AppDelegate+DockShortcutRouting.swift`, `ContentView+RightSidebarCommandPalette.swift`,
  `ContentView+ViewCommandPalette.swift` (6), `cmuxApp.swift`, and the shortcut name in
  `CmuxConfigSchema.generated.swift`. You don't bind it.

**Keep:** `ChiefCatalogSection` in `CmuxSettings` (only `enabled` is still read), the `chief.enabled` parser in
`KeyboardShortcutSettingsFileStore+SectionParsers.swift` (~425), `"chief.enabled"` in
`CmuxSettingsFileStore+SupportedPaths.swift` (~236) and the whole `chief` object in the schema. `cmux config get
chief.enabled` should still work.

**Build edits:** pbxproj file removals only.

**Risk:** low. `CmuxSettings` and `CmuxControlSocket` are linked by the CLI too, so the CLI must build.
An old NIGHTLY CLI calling `chief.*` now gets "unknown method"; you don't call it.

- ⬜ Standard checks. `config doctor` clean with `"chief": {"enabled": false}` still in `cmux.json`.
- ✅ `"$T" chief status` → unknown command. `"$T" rpc chief.status` → unknown method.
- ✅ `"$T" config get chief.enabled` → `false`.
- ⬜ Settings → Automation has no Chief card. Settings → Keyboard Shortcuts has no "Open Chief".

### ✅ 8.3 Chief panes out of workspaces, Dock, sidebar and drag-and-drop (M, medium risk)

**Done:** commit "Phase 8.3: ...". Differs from the plan:
- **`Sources/Chief/` (all 34 files) was deleted here, not in 8.4.** Its files use `ChiefPanel`,
  `ChiefHomeNavigation`, `leaveChiefHome` and `openChiefInRightDock`, so it can't build once the 7 outside files
  go. 8.4 is now only the packages (plus leftovers). The pbxproj entries of the missing test files
  `ChiefHomeNavigationFocusTests.swift`, `ChiefListAndSettingsCopyTests.swift`, `ChiefPanelSessionTests.swift` went too.
- `Sources/ChiefSettingsBridge.swift` stays (imports only `CmuxSettings`; `Sources/Mobile/` still reads
  `ChiefSettings.isEnabled` until Phase 9). Its `openChiefHome` extension went (nothing called it).
- `SidebarSelection.home` (the Chief Home sidebar selection) was removed, with its uses in `ContentView.swift`,
  `AppDelegate.swift`, `SessionPersistence.swift` and `RecoverableMainWindowRoute.swift`. The `chiefEnabled`
  `@AppStorage` in `ContentView` went too.
- `--type chief` is gone from `new-pane` / `new-surface` (parser, help) and from `canvas new-pane` (CLI and
  `canvas.new_pane`; `CanvasNewPaneType.chief` removed). `new-pane --type chief` now falls back to a terminal,
  like any unknown type (upstream behaviour). `canvas new-pane --type chief` is a usage error. Dock socket
  placement accepts terminal and browser only. `chief.open` left the focus-intent list in `TerminalController.swift`.
- Dock: the empty pane's "New Chief" button went. `DockSplitStore.newSurface/newSplit/makePanel` lost the
  `conversationID` parameter.
- English strings in `Localizable.xcstrings` for the changed messages were updated; other languages are left.
- `WindowChromeMetrics` "home row" metrics and their comments are untouched (layout values, still used).
- The only `agentHome` hit in `git diff -U0` is `isProtectedHome` becoming `isAgentHome`, as this step asks.
Checked against the test app: build, `--version`, `config doctor` clean, `tree --all` has the same 12 workspaces as
Personal's session file, `system.capabilities` has the same 545 methods as the baseline, `config get chief.enabled`
→ `false`, the saved test session has no `"chief"` key, `canvas new-pane --type chief` → usage error.


**What it removes:** the Chief panel itself and all code that knows about it outside `Sources/Chief/`. After this
step no file outside `Sources/Chief/` imports `CmuxChief`, `CmuxHomeCore`, `CmuxHomeRender`, `MessagesLab*` or
`CmuxAgentQuestion`.

**Files (the 10 app files that import `CmuxHomeCore` outside `Sources/Chief/`):**
- Delete `Sources/Panels/ChiefPanel.swift`, `Sources/Workspace+ChiefPane.swift`, `Sources/DockSplitStore+ChiefPane.swift`,
  `Sources/ChiefHomeNavigation.swift`, `Sources/AppDelegate+Chief.swift`, `Sources/Sidebar/ChiefHomeConversationRows.swift`,
  `Sources/Sidebar/SidebarChiefHomeRow.swift`.
- `Sources/Workspace.swift`: `.chief` in the snapshot builder (~834) returns `nil`; restore (~2418) returns `nil`
  (already from 8.1); remove the Chief Home anchor code (~11377, ~11623, ~11642) and `var isProtectedHome` becomes
  `isAgentHome` (keep the name, other code calls it).
- `Sources/DockSplitStore.swift` (1088, 1113, 1180, 812, 1199) and `DockSplitStore+SessionRestore.swift` (242, 782),
  `DockSplitStore+SessionSnapshot.swift` (434): `.chief` creates and restores nothing. Keep `SurfaceKind.chief`.
- `Sources/PaneTransferSourceResolver.swift` and `Sources/PaneDropContainer.swift`: remove the `.chiefConversation`
  source case and `canPerformChiefConversationDrop` / `performChiefConversationDrop`.
- `Sources/TabManager.swift`: remove `isChiefHomeGroup`, the Home guards (2413–2488), the hidden-conversations
  block (2664–2672) and the three `leaveChiefHome` calls (4277, 4753, 4760). Same in `AppDelegate.swift`
  (16883, 17377), `SidebarWorkspaceGroupDialogs.swift` (67), `VerticalTabsSidebar+WorkspaceGroups.swift` (473, 559).
- `SessionPersistence.swift`: drop the optional `chief: SessionChiefPanelSnapshot?` field and the type (rule 2).
- Switches over `PanelType` that name `.chief` (`CmuxLifecycleEventPublishing.swift`,
  `ContentView+CommandPaletteSurfaceMetadata.swift`, `ClosedItemHistory+PanelTitle.swift`,
  `DockControlDefinition.swift`): keep the case, give it a plain title.

**Stub returns:** restoring a `.chief` panel → `nil` (nothing). A `.chief` Dock control → no panel.

**Build edits:** pbxproj file removals.

**Risk:** medium. `TabManager.swift` and `Workspace.swift` are huge and also hold the agent-home code. Only remove
lines that name Chief. Run `git diff -U0 | grep -i agentHome` before committing: it must be empty.

- ⬜ Standard checks.
- ✅ `grep -rlE "import (CmuxChief|CmuxHomeCore|CmuxHomeRender|MessagesLab|CmuxAgentQuestion)$" Sources CLI | grep -v Sources/Chief/` is empty.
- ⬜ Drag a tab between panes and between workspaces still works. Close a workspace, reopen it with ⇧⌘T.
- ⬜ The pinned cmux row: can't close, can't unpin, stays on top, respawns.

### ✅ 8.4 Delete the Chief and Home packages (S–M, low risk)

**Done:** commit "Phase 8.4: ...". `Sources/Chief/` had already gone in 8.3 (see there). Removed here: the 5 packages,
their 5 package references, 6 products, 12 `… in Frameworks` build files and their Frameworks-phase and
`packageProductDependencies` lines in `cmux` and `cmuxTests` (52 pbxproj lines). Also removed (not in the plan):
`Assets.xcassets/ChiefAvatar.imageset` (only `ChiefPanel` used it), `scripts/chief/record-motion.sh` (records the
Chief Home UI), and the 5 package names in `scripts/ci/package-test-lane.sh`. No `Package.resolved` change.
Checked against the test app: build, `--version`, `config doctor` clean, `tree --all` same 12 workspaces,
`system.capabilities` same 545 methods as the baseline, `chief status` → unknown command, `config get
chief.enabled` → `false`. No stale Chief/Home/MessagesLab/AgentQuestion bundle in the built app (no rebuild needed).
Docs updated: `removal-plan.md` Phase 8 ✅, `overview.md`, `plan.md` Phase 2 ✅.

**What it removes:** `Sources/Chief/` (the rest), `Packages/macOS/CmuxChief`, `Packages/Shared/CmuxHomeCore`,
`CmuxHomeRender`, `CmuxMessagesLab`, `CmuxAgentQuestion`.

**Check first:** `CmuxAgentQuestion` is only used by Chief, HomeCore and MessagesLab (checked). Your plan.md Phase 6
("ask" vs "perm" marks) uses the agent registry in `Sources/Mobile/AgentChat`, not this package.

**Build edits (pbxproj):** remove 5 package references and 6 products (`CmuxChief`, `CmuxHomeCore`,
`CmuxHomeRender`, `MessagesLabHome`, `MessagesLabSidebar`, `CmuxAgentQuestion`) from both `cmux` and `cmuxTests`.
Remove every `Sources/Chief/*.swift` file entry. No `Package.resolved` change (all local).

**Risk:** low once 8.3 builds. The CLI doesn't link any of these.

- ⬜ Standard checks.
- ✅ No `CmuxChief_*`, `CmuxHomeRender_*`, `CmuxMessagesLab_*`, `CmuxAgentQuestion_*` bundle in the built app
  (see "stale bundles" above).
- ✅ Update `removal-plan.md` (Phase 8 ✅), `docs/overview.md`, `docs/plan.md` Phase 2 (done by 8.1).

---

## Phase 9: Cloud, Account, Mobile, Devices, Iroh, cmux-tui / Machines, `cmux vm`, pricing, Stack Auth

### What looks cloud or mobile but is local (keep, or move first)

This is the hard part. These live in cloud/mobile packages or folders but serve local features:

| Thing | Where it lives now | What it does locally | Plan |
|---|---|---|---|
| **`cmux send --paste`** (the cmux agent's multi-line `cmux_send`) | socket method `terminal.paste` → `TerminalController.swift` ~1383 → `controlCommandCoordinator.handleMobileHostAsync` (`CmuxControlSocket/Coordinator/MobileHost/`) → `v2MobileTerminalPaste` (~16553) → `MobileHostTerminalInputApplier` (`Sources/Mobile/`), `TerminalController+MobileInputDelivery.swift` | Pastes text into a terminal, with submit key | Step 9.6: keep `terminal.paste` / `terminal.input`, move what they need out of `Sources/Mobile` |
| **Agent transcript registry** | `Sources/Mobile/AgentChat/` (13 files) + `Packages/macOS/CmuxMobileHost/.../AgentChat/` (11 files, e.g. `AgentChatSessionRecord`, `AgentChatHookSessionStore`) | Started at launch (`AppDelegate.swift` 855, 2601, 2607). Records resume intents from session restore (`AgentChatTranscriptResumeIntentRecorder`, used by `Workspace`, `TabManager`, `DockSplitStore`), feeds global search (`Sources/Search/`) and current work | Step 9.5: move out, keep |
| `CmuxAgentChat` | `Packages/Shared` | Types for the above, 31 app files | Keep |
| `CMUXMobileCore` | `Packages/Shared` | Shared core, used by CmuxTerminal, CmuxGit, CmuxSettingsUI, CmuxSurfaceCatalogModel, 97 app files | Keep |
| `CmuxTerminalSharing` + `CmuxTerminalSizing` | `Packages/macOS`, `Packages/Shared` | `LocalTerminalSizingHost`, the terminal size overlay | Keep for now (later candidate) |
| `CmuxSSHClipboardTrust` | `Packages/macOS` | Plain SSH clipboard | Keep |
| **Current work** (`CurrentWorkInput`, `CurrentWorkSnapshot`, `WorkspaceFacts`) | `CmuxCloud/Surfaces/` | `current.list`, the ⌘P current-work view (`CurrentWorkReducer`, `CurrentWorkPalettePresentation`) | Step 9.4: move to `CmuxSurfaceCatalogModel` |
| **Surface move rules** (`SurfaceTransferRejection`, `SurfaceOwnershipPolicy`, `SurfaceTransferOrigin`, `SurfaceProjectionEndReason`, `SurfaceRemotePlacement`, `SurfaceWorkspaceCreationReceipt`) | `CmuxCloud/Surfaces/` | Drag a tab to another pane or workspace (10 app files) | Step 9.4: move |
| `NotificationReadTarget` | `CmuxCloud/Notifications/CloudNotificationPlacement.swift` | `TerminalNotificationStore` | Step 9.4: move |
| **Managed policies** (`ManagedFileTransferPolicy`, `ManagedRemoteConnectionsPolicy`, + `ManagedCloudPolicy`, `ManagedIrohNetworkingPolicy`, `ManagedAICredentialUploadPolicy`) | `CmuxCloud/Environment/ManagedCapabilityPolicy.swift` | File drag/upload into terminals, clipboard read, SSH (`GhosttyTerminalView`, `TerminalCustomUploadRunner`, `TerminalSSHSessionDetector`, …) | Step 9.4: move to `CmuxSettings/Policies/` |
| **App URL scheme** (`AuthEnvironment.callbackScheme`, 19 uses) | `CmuxCloud/Environment/AuthEnvironment.swift` | `cmux-dev-test://` / `cmux-dev-mine://` links: "Copy workspace link" (`WorkspaceSurfaceIdentifierClipboardText.swift`), `CmuxSSHURLRequest`, browser link handling | Step 9.4: small local `AppURLScheme`. **Keep** the URL type in `Info.plist` and `CMUX_AUTH_CALLBACK_SCHEME` |
| `cmux hooks claude push-notification` | `CLI/CMUXCLI+ClaudePushNotificationHook.swift` | Turns Claude's PushNotification tool into a **desktop** banner. The wrapper calls it | Keep |
| `claude-teams`, `codex-teams` | CLI | Claude Agent Teams | Keep |
| `TerminalNotificationOrigin.cloudVM / .deviceMac` | `Sources/TerminalNotificationOrigin.swift` | Stored in notification history; unknown values decode as `.local` | Leave as is |

### Where cloud code is woven into local paths

| Path | Where | How the local path stays safe |
|---|---|---|
| **Terminal spawn** | `Workspace.newTerminalSurfaceOutcome` / `newTerminalSplitOutcome` (~9326, ~9674): `cloudTerminalSourcePlacement(forPanel:)` routes to `routeCloudPaneTerminalTab` | Stub `cloudTerminalSourcePlacement` → `nil` (9.8), then delete the branch. The remote tmux branch above it stays |
| **Image paste / drop** | `GhosttyTerminalView.swift` ~10337–10430 (`.pasteCloudImages`, `CloudImagePasteInputLease`), `TerminalImageTransfer.swift` (`.cloud` target, `CloudImagePasteError`), `TerminalSurface+CloudImagePaste.swift`, `TextBoxInputContainer+CloudImagePaste.swift` | Remove the `.cloud` target and `.pasteCloudImages` plan together (9.8). `.local` and `.remote` (SSH) stay |
| **Cloud reconnect overlay** | `GhosttyTerminalView.swift` 10776, 11460–11710 (`cloudTerminalOverlay`) | `synchronizeCloudTerminalReconnectOverlay` → no-op (9.8), then delete |
| **Terminal work diagnostics** | `GhosttyTerminalView.swift` ~348 uses `MobileHostDiagnostics.log` | Swap for a plain `Logger` before `Sources/Mobile` goes (9.8) |
| **File explorer** | `FileExplorerStore.swift`, `FileExplorerWorkspaceRootResolver.swift` (`AuthenticatedTeamScope`, `ManagedCloudPolicy`), `FileExplorerSearchController+Cloud.swift`, `CloudFileExplorer*.swift`, `CloudVMFileExplorerProvider.swift`, `LiveCloudFileExplorerCommandRunner.swift`, `CloudFilePreview*.swift` | Local and SSH providers stay (`RemoteFileExplorerProvider.swift`). Cloud provider never chosen (9.8), then deleted |
| **Browser** | `BrowserPanel.swift` (`CloudBrowserRouting`, `CloudDesktopConnectionObserver`), `BrowserPanel+CloudConnection.swift`, `+MobileBrowserDialogs`, `+MobileBrowserStreaming`, `+AppPricingRestore`, `BrowserNavigationDelegate.swift` (`appSessionHandoffOrigin`), `BrowserPopupWindowController.swift`, `BrowserExternalNavigationHandler.swift` | Sign-in handoff origin → `nil` (feature off); cloud routing → direct (9.8) |
| **Sidebar** | Footer (`VerticalTabsSidebar+EmptyAreasAndFooter.swift`: account, `mobileConnect`, `cloud` buttons), `SidebarAccountMenuButtonStyle.swift`, `SidebarAccountTeamPopover.swift`, `SidebarCloudWorkspaceBadgeView.swift`, `SidebarWorkspacePresenceHeadsView.swift`, `SidebarProBadge.swift`; right sidebar "Cloud" tab (`RightSidebarMode.machines`, `RightSidebarMode+Availability.swift`, `RightSidebarPanelView.swift`); `TabManager+CloudWorkspaceSelection.swift` (`CloudWorkspaceSelectionState`) | Hide in 9.1, stub in 9.7 |
| **Session restore** | `Workspace.swift` 211, 309, 327, 406, 1647 (`cloudVMBinding`, cloud projections), `SessionPersistence.swift` 1820–1887 (`SessionCloudVMBindingSnapshot`, `cloudVM`, `cloudMachineTeams`), `SessionSnapshotImportTrust.swift` 106–116, `WorkspaceCloudBindingState.swift`, `Sources/RemoteTui/WorkspaceCloudVMBinding*.swift` | Restore ignores them (9.9), then drop the optional fields. Keep `remote` (SSH) |
| **TerminalController routing** | `TerminalController.swift`: `iroh_diag` (1509), `auth.*` (1742–1774), `mobile.*` (1960–1988, 15480–15643), `vm.*` (2275, `Sources/Cloud/VMClientSocketCommands*.swift`), `remotes.*`, `phone_push.*`, `dogfood.feedback.submit`, `MobileHostIdentity` in `TerminalController+SharedSizing.swift`; `ControlCommandCoordinator+System.swift` (`auth.login`, `mobile.dev_stack_auth.configure`) | 9.11. Keep `terminal.paste`, `terminal.input`, `surface.*`, `current.list`, everything in removal-plan.md's list |
| **AppDelegate startup** | `cmuxApp.swift` 97 (`MacAuthComposition()`), 255–280 (`appDelegate.configure(auth:cloudMachinePinStore:cloudWorkspaceCoordinator:…:devicesRegistry:computersService:)`); `AppDelegate.configure` 2455–2560 (`CloudTelemetryUploader`, `CloudOperationRecorder`, `VMClient.bootstrap`, `RemotesClient`/`TeamsClient`/`AIAccountsClient`/`CoderouterClient`/`MachineUsageClient.bootstrap`, `PhonePushClient`, `MobileHostService.configure`, `DeviceRegistryClient`, `configureWorkspacePresence`, `PhoneReplyInbox*`); `MobileHostService.shared.start()` (8340), `syncToSettings()` (2037, 11056), `sweepSoon` (2035); `App/MacDevicesComposition.swift` | 9.2 stops the starts, 9.10 removes the wiring |
| **Quit path** | `AppDelegate.swift` ~2088 and ~2150 wait for `CloudNotificationSyncHub.shared.persistenceStore` to drain; 2424 `MobileHostService.shared.stop()` | Remove carefully in 9.10; ⌘Q must still save the layout |
| **Settings window default** | `CmuxSettingsUI/Scene/SettingsWindowScene.swift` 136 and 353: `?? .account` | Change to `?? .app` **before** Account is hidden (9.1), or Settings opens on a missing section |

### Decided: `cmux ssh` and SSH-TUI (`Sources/RemoteTui/`)

`cmux ssh <host>` normally goes through `runSSHTui` (`CLI/cmux.swift` ~14107) unless the daemon bootstrap is
skipped. That path needs the `cmux-tui` client, which `reload.sh` doesn't bundle in this fork, and it lives on
`CmuxCloud` + `CmuxCloudTui` (`SSHTuiLinkManager`, `SSHTuiConnection`, `CloudMachineLink`, `CloudTuiClientPaths`).
So `cmux ssh` may already not work here. removal-plan.md says "keep remote SSH", but that table was about
`RemoteTmux*`, `CmuxRemoteSession`, `CmuxRemoteWorkspace`, `CmuxRemoteDaemon`.

- ✅ **Decided (9.0): SSH-TUI goes.** **Decide before 9.9:** run `"$T" ssh <one of your hosts>` in the test app today.
  - If it fails already: SSH-TUI goes with Cloud (`Sources/RemoteTui/`, `CLI/CMUXCLI+SSHTui.swift`, the
    `runSSHTui` call; `cmux ssh` then uses the plain path). Remote tmux and `CmuxRemote*` stay.
  - If it works and you want it: keep `Sources/RemoteTui/`, `CmuxCloudTui` and the `SSHTui*` / `CloudMachineLink`
    files from `CmuxCloud` (move them in 9.4 too). That makes 9.15 bigger.
  - Your `cmux.json` has `"showSSH": false` and no script uses `cmux ssh`.

---

### ✅ 9.0 Baseline and decisions (S, no code)

Done: baseline in `/tmp/cmux-baseline/` (taken after 8.2, see its NOTE; `lsof -i` showed no network sockets).
SSH-TUI decision: **goes** with Cloud; remote tmux (`RemoteTmux*`) and `CmuxRemote*` stay. The unused
`sentry-cocoa` package reference was removed right away in its own commit (pbxproj + `Package.resolved`).

**What it does:** records how the test app answers today, so later steps can be compared.

- ✅ Build the test app after the CodeRouter commit. Save to `/tmp/cmux-baseline/`: `"$T" rpc system.capabilities`,
  `"$T" --json tree --all`, `"$T" identify`, `"$T" --help`, `"$T" config doctor`.
- ✅ `lsof -i -p <test app pid>` right after launch: expect nothing.
- ✅ Decide the SSH-TUI question above: SSH-TUI goes; remote tmux and `CmuxRemote*` stay.
- ✅ Note the one leftover found while checking: the pbxproj still has an unused
  `XCRemoteSwiftPackageReference "sentry-cocoa"` (lines ~14415, ~20008). Nothing links it, but it's resolved and
  downloaded on a clean build. Remove it in 9.17 (or right away as its own tiny commit).

### ✅ 9.1 Hide every entry point (M, low risk)

Done (see `git log`, "Phase 9.1"). Differs from the plan: Settings hides the five sections through a new
`SettingsTaxonomyGroup.hiddenSections` set (sidebar, search hits, mount order; a stored hidden selection falls back
to App). `CloudMachinesFeature.isAvailable(policy:)` in the `CmuxCloud` package also answers false (DevicesFeature and
`CloudActivationPolicy` called it directly). Also hidden: the menu-bar status item's Cloud section, Help menu
"Cloud Diagnostics…", the Pro upgrade item and DEBUG pricing / Cloud lab / Cloud welcome / Pro checklist items
(`currentUpgradeOffer` → nil), the footer Upgrade (Pro) badge, the "Open Mobile Pairing" palette command and the
`.mobileConnect` / `.cloudVM` "+" menu rows. `switchRightSidebarToMachines` shortcut kept (the tab is unavailable).
Settings/menus/footer not looked at by eye (no screenshot possible from the worker).

**What it removes:** what you can see or click: Settings → Account, Mobile, Cloud, Devices, Networking; the Cloud
menu; sidebar footer account / mobile / cloud buttons and the team popover; "New Cloud Workspace" / "New Cloud
Machine" (menu, tab-bar "+", palette); the team picker; account and Pro palette commands; the right-sidebar Cloud
tab; pricing and Pro screens; the debug "Show Cloud Welcome" menu.

**Edits:**
- `SettingsWindowScene.swift` 136, 353: default `?? .app`.
- `CmuxSettingsUI/Navigation/SettingsTaxonomy.swift`: leave out `.account`, `.mobile`, `.cloudMachines`,
  `.computers`, `.networking` (keep the enum cases for now; `SettingsSectionID+Compatibility.swift` maps old raw values).
- `Sources/Cloud/CloudMachinesFeature+FeatureFlags.swift`: `isAvailable`, `offMainIsAvailable`, `isEnabled`,
  `offMainIsEnabled` → `false`. This hides the right-sidebar Cloud tab (`RightSidebarMode+Availability.swift`) and
  most cloud UI, and makes `VMClient.bootstrap`'s `isCloudEnabled` false.
- `Sources/Devices/DevicesFeature.swift`: `isAvailable` / `isEnabled` → `false`.
- `Sources/cmuxApp+CloudMenu.swift`: don't add the menu. `Sources/Debug/CloudWelcomeDebugMenu.swift`: don't add.
- Shortcuts: remove `openTeamPicker`, `newCloudWorkspace`, `newCloudMachine` like Phase 6 did for Simulator
  (`ShortcutAction` + `+Defaults`, `+DisplayName`, `+Group`, `KeyboardShortcutSettings.swift`, `AppDelegate.swift`,
  `AppDelegate+DockShortcutRouting.swift`, `AppDelegate+CloudTeamPicker.swift`, `AppDelegate+NewCloudWorkspace.swift`,
  `ContentView+RightSidebarCommandPalette.swift`, `cmuxApp.swift`, `CmuxConfig.swift`, schema names). Also the
  new-cloud cases in `CmuxSurfaceTabBarBuiltInAction.swift` (15 uses) and `AppDelegate+NewWorkspaceContextMenu.swift`.
  You bind none of them.
- Footer: don't show `.account`, `.mobileConnect`, `.cloud` buttons (`VerticalTabsSidebar+EmptyAreasAndFooter.swift` 81–84).
- Palette: `ContentView+AuthCommandPalette.swift`, `ContentView+ProCommandPalette.swift` register nothing.

**Build edits:** none (or the few files the shortcut removal empties).

**Risk:** low. The trap is the Settings default section. Removing shortcut cases touches `CmuxSettings`, which the
CLI links.

- ⬜ Standard checks.
- ⬜ Settings opens on App. Sidebar list has no Account, Mobile, Cloud, Devices, Networking.
- ⬜ No Cloud menu. Sidebar footer: only the buttons you had minus account/mobile/cloud. Nothing else moved.
- ✅ Right sidebar has no Cloud tab; Files, Find, Vault, Feed, Dock still open (`"$T" right-sidebar files` …).
- ⬜ Keyboard Shortcuts: ⌘O, ⌥⌘↑/↓ still work.

### ✅ 9.2 Nothing cloud starts at launch (S–M, medium risk)

Done (see `git log`, "Phase 9.2"). All listed calls removed at the call site; no hang or crash at launch, so nothing
needed stubbing inside. `syncToSettings()` at ~11056 is inside `syncMobileHostService()` (the user-defaults
observer), which is now a no-op. Kept: `MobileHostService.shared.configure(auth:)` (configure only, not in the list),
`CoderouterClient.bootstrap` (the CodeRouter commit kept it), the `PhoneReplyInboxCoordinator.injectTerminalInput`
hook, and the `syncToSettings()` calls in `AppDelegate+ManagedPolicy.swift` (fire only on an MDM policy change;
they go in 9.10). The test app already had no sockets before this step (checked after 9.1 too).

**What it removes:** background work: mobile host listener, Iroh networking monitor, phone-reply sweeps, cloud
telemetry resume, device registry, workspace presence. Objects are still created, they just don't start.

**Edits (`AppDelegate.swift`):**
- 8340: don't call `MobileHostService.shared.start()`. 2037 and 11056: don't call `syncToSettings()`.
  2035: don't call `PhoneReplyInboxCoordinator.shared.sweepSoon`.
- In `configure` (~2494–2540): don't call `cloudUploader.resumePending()`, `NewMachineSheetDataCache.bootstrap`,
  `RemotesClient` / `TeamsClient` / `AIAccountsClient` / `MachineUsageClient.bootstrap`, `PhonePushClient.configure`,
  `DeviceRegistryClient.configure`, `computersService.configure`, `devicesRegistry.configure`,
  `configureWorkspacePresence`, `PhoneReplyInbox*.configure`. Leave `CoderouterClient` to whatever the CodeRouter
  commit did.
- `App/MacDevicesComposition.swift`: don't call `preferences.start()`.
- `caffeineController.onStateChange` emits a mobile event: keep the menu-bar refresh, drop `MobileHostService.emitEvent`.

**Keep:** `agentChatTranscriptService.start()` (2607) and the socket listener.

**Risk:** medium. Some of these set up shared singletons other code reads. If a crash or a hang shows up at
launch, put the call back and stub it inside instead.

- ⬜ Standard checks.
- ✅ `lsof -i -p <pid>`: nothing listening, nothing connected. `nettop -p <pid>` for a minute: no traffic. (Done: lsof empty, nettop 60 s empty.)
- ✅ Vault (right sidebar) and global search still list Claude/Pi sessions (that's the transcript service). (Done via `cmux vault sessions` / `vault search`; global search UI needs a manual look.)

### ✅ 9.3 Cloud CLI commands go; unlink `CmuxCloudResizeCore` from the CLI (M, low risk)

Done (see `git log`, "Phase 9.3"). 23 files deleted (11 `CMUXCLI+VM*.swift`, not 13, plus `CMUXCLI+SSHTui.swift`), ~9,700
lines, plus ~3,600 dead lines in `CLI/cmux.swift`. Differs from the plan:
- `RemoteDaemonStatusCommand` lived in `Commands/VMCommands.swift`; moved to `Commands/SystemCommands.swift`
  (`remote-daemon-status` still works).
- `cmux agent` no longer falls back to `cmux vm agent`; unknown verbs print the local usage. `cmux agent --help` is
  new local text.
- `cmux surface ls|open|new-terminal|new-display` (the surface catalog, implemented in `CMUXCLI+VMTui.swift`) went
  too: it was the cloud machine catalog. `surface resume` and the sizing verbs stay. The app-side `surface.project` /
  `surface.catalog` methods are untouched.
- `cmux cloud guide` and the "Use Cloud" section of `cmux guide` / `--skill` went.
- Dead VM-only helpers in `cmux.swift` went too (`vmIDForSplitAttach` branch of `runSSHWithOptions`, the
  `vm-pty-connect` websocket bridge, VM create idempotency store, freestyle attach retries, ...).
  `commandDefersSocketConnectionUntilRequest` now returns `false` (only `vm dev|layout|env` used it).
  `VMDaemonWebSocketEndpoint` stays (SSH options still carry it).
- Changed English strings got new keys (`cli.surface.usage.local`, `cli.guide.overview.share.local`,
  `cli.rightSidebar.error.setRequiresMode.local`) because `Localizable.xcstrings` has `en` values for the old keys.
  Old keys are still in the xcstrings (orphans; clean up later).
- `refresh-docs.sh` writes into `~/Code/cmux-config/docs/cli`, so it ran from a copy in `/tmp` instead: no `NOTE:` lines;
  the only changes are the removed Cloud lines.


**What it removes:** `cmux vm` / `cloud`, `vm-pty-attach`, `vm-tui-connect`, `vm-ssh-attach`, `auth` / `login` /
`logout`, `team`, `billing`, `remotes` / `remote`, `ai-accounts`, `mobile`, `iroh-diag`, and the right-sidebar CLI
words `cloud`, `machines`, `devices`.

**Files:**
- Delete `CLI/CMUXCLI+VM*.swift` (13), `CLI/VMMachineTerminalResolution.swift`, `CLI/VMReadyPollInterval.swift`,
  `CLI/VMRemoteWorkspaceResolver.swift`, `CLI/Commands/VMCommands.swift`, `CLI/CMUXCLI+CloudDomains.swift`,
  `CLI/CMUXCLI+CloudFeature.swift`, `CLI/CMUXCLI+CloudSidebar.swift`, `CLI/CMUXCLI+AuthTeam.swift`,
  `CLI/Commands/AuthCommands.swift`, `CLI/CMUXCLI+Remotes.swift`, `CLI/RemotesArgumentParser.swift`.
  About 11,000 lines.
- `CLI/cmux.swift`: the cases at ~5787 (`iroh-diag`), 5796 (`billing`), 5819 (`auth`), 5924 (`vm`, `cloud`),
  6893 (`remotes`), 6896 (`ai-accounts`), 6899 (`mobile`), 7393–7397 (`vm-*-attach`), the help switch
  (~19795–19922), the VM helpers used only by them (e.g. `printVMSSHInfo` ~14544, `vm.desktop_open` ~4563),
  `CLI/Commands/CmuxCommand.swift` subcommand list, completion candidates, `CMUXCLI+TaskHelp.swift`.
  Right-sidebar args ~22986: drop `cloud`, `machines`, `devices`.
- If you decided SSH-TUI goes: `CLI/CMUXCLI+SSHTui.swift` and the `runSSHTui` call (~14107) too.

**Keep:** `ssh`, `remote-daemon-status`, `claude-teams`, `codex-teams`, `hooks … push-notification`, `send --paste`,
everything in removal-plan.md's command table.

**Build edits:** pbxproj: remove the CLI files from the `cmux-cli` target (and `cmuxCLITests` if listed); remove
`CmuxCloudResizeCore` from `cmux-cli`'s `packageProductDependencies` and Frameworks phase (only
`CMUXCLI+VMHelp.swift` imported it).

**Risk:** low. `cmux.swift` is 40,000+ lines and the CodeRouter worker just edited it. Build the CLI and check help.

- ⬜ Standard checks.
- ✅ `"$T" vm list`, `"$T" auth status`, `"$T" remotes list`, `"$T" mobile` → unknown command. (Also `cloud`, `login`, `billing`, `iroh-diag`, `ai-accounts`, `vm-pty-attach`, `right-sidebar set cloud`.)
- ✅ `"$T" --help`, `"$T" help remote`, `"$T" docs settings` still print (also `ssh --help`, `agent --help`, `surface --help`, `remote-daemon-status --help`). `~/Code/cmux-config/scripts/refresh-docs.sh`
  with `CMUX="$T"` runs without `NOTE: … failed` lines (compare with the baseline).
- ✅ `"$T" send --paste -- $'a\nb'` into a scratch terminal works.

### ✅ 9.4 Move the local types out of `CmuxCloud` (M, low–medium risk)

Done (see `git log`, "Phase 9.4"). Differs from the plan: `ManagedCapabilityPolicy.swift` keeps `import AppKit`
(`ManagedFileTransferPolicy.presentRefusal()` uses `NSAlert`); it compiled unchanged in CmuxSettings' Swift 6 mode,
no concurrency fix needed. `NotificationReadTarget` is its own file in CmuxSurfaceCatalogModel. The package test
`SurfaceOwnershipPolicyCrossTeamTests.swift` moved with it (not run). `AppURLScheme` also keeps the Debug
dev-override file read (`~/.config/cmux/dev-profiles/<tag>.env`, `~/.cmux-dev.env`) for `CMUX_AUTH_CALLBACK_SCHEME`,
so it resolves exactly like `AuthEnvironment.callbackScheme`. Also pointed at it: `BrowserPanel.swift` and
`BrowserPopupWindowController.swift` (own-scheme allowlist checks); `WorkspaceSurfaceIdentifierClipboardText.swift`
needed no edit (it uses `CmuxNavigationURLRequest.workspaceLink`'s default). The auth-callback policy inits
(`BrowserNavigationDelegate`, `BrowserPopupWindowController`) keep `AuthEnvironment` (9.8 work).
`CmuxSSHURLRequest.swift`, `AppDelegate+CmuxSSHURL.swift`, `BrowserExternalNavigationHandler.swift` no longer
import `CmuxCloud`. pbxproj: one new app file (`AppURLScheme.swift`).
Found: the test app opened by `test-app.sh` from a cmux Personal shell inherits `CMUX_TAG=mine` /
`CMUX_AUTH_CALLBACK_SCHEME=cmux-dev-mine`, so its scheme is `cmux-dev-mine` (it accepted
`cmux-dev-mine://workspace/<id>` via `open -a`, ignored `cmux-dev-test://…`). Same before this step; a harness issue.

**What it does:** moves code, no behaviour change. After this, the app files in the table above no longer need
`CmuxCloud` for local work.

**Moves:**
- To `Packages/macOS/CmuxSurfaceCatalogModel` (they import only it and Foundation; `CmuxCloud` already depends on
  it): `Surfaces/CurrentWorkInput.swift`, `CurrentWorkSnapshot.swift`, `SurfaceOwnershipPolicy.swift`,
  `SurfaceTransferOrigin.swift`, `SurfaceTransferRejection.swift`, `SurfaceProjectionEndReason.swift`,
  `SurfaceRemotePlacement.swift`, `SurfaceWorkspaceCreationReceipt.swift`, and `NotificationReadTarget` from
  `Notifications/CloudNotificationPlacement.swift`. Keep them `public`. Add `import CmuxSurfaceCatalogModel` where a
  `CmuxCloud` file or app file now misses it.
- To `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Policies/` (next to `ManagedDevicePolicy`):
  `Environment/ManagedCapabilityPolicy.swift` (it only needs Foundation; drop its `import AppKit`).
- New app file `Sources/AppURLScheme.swift`: `enum AppURLScheme { static var callbackScheme: String }`, same logic
  as `AuthEnvironment.callbackScheme` (reads `CMUX_AUTH_CALLBACK_SCHEME` from the environment, falls back by bundle
  id). Point the local users at it: `CmuxSSHURLRequest.swift`, `WorkspaceSurfaceIdentifierClipboardText.swift`,
  `BrowserExternalNavigationHandler.swift`, `BrowserNavigationDelegate.swift`, `AppDelegate+CmuxSSHURL.swift`.
- If SSH-TUI stays: also `Link/SSHTuiConnection.swift` and what it needs.

**Build edits:** none in pbxproj (package files aren't listed there). The CLI links `CmuxSurfaceCatalogModel` and
`CmuxSettings`, so it compiles the moved files too; that's fine.

**Risk:** low–medium. Type name clashes if a file is copied instead of moved. Package tests of `CmuxCloud` may
break; nothing runs them.

- ✅ Standard checks (build, `--version`, `config doctor`, `tree --all`, `current.list`; the clicking ones need a manual look).
- ✅ Tab to another pane and to another workspace via `cmux move-surface` (and back). ⬜ Real drag and file drop: manual.
- ✅ Workspace link logic: `AppURLScheme` copies `AuthEnvironment.callbackScheme`; `open -a <test app> <scheme>://workspace/<id>`
  selected the workspace. ⬜ The menu item and Safari paste: manual (and see the scheme note above).

### ✅ 9.5 Move the agent transcript registry out of Mobile (M, medium risk)

Done (see `git log`, "Phase 9.5"). Took the new-package route: `Packages/macOS/CmuxAgentChatHost` (deps
`CmuxAgentChat`, `CmuxFoundation`; same Swift 6 settings as CmuxMobileHost, no test target) with all 11 files from
`CmuxMobileHost/AgentChat/` (git mv, unchanged). `Sources/Mobile/AgentChat/` has **14** files, not 13; moved to
`Sources/AgentChat/` (pbxproj: group moved from `Mobile` to `Sources`, file refs unchanged). `import CmuxMobileHost`
→ `import CmuxAgentChatHost` in the 11 `Sources/AgentChat` files that had it, `ConversationSidebarSupport.swift`,
`Search/AgentChatTranscriptService+GlobalSearch.swift`, `Surfaces/CurrentWorkQueryService.swift`; the mobile
`TerminalController+MobileChat.swift` / `+MobileChatArtifacts.swift` import both until they go. The package is linked
into `cmux` and `cmuxTests`. Still in `Sources/AgentChat` for 9.14: `AgentChatTranscriptService`'s default
`MobileHostService.hasEventSubscribers` / `emitEvent` args and `AgentChatProseStreamWakeDriver`'s
`.mobileHostEventSubscriptionsDidChange` observer (they reference `Sources/Mobile`).

**What it does:** moves code, no behaviour change. The registry that feeds resume, search and current work stops
living under "Mobile".

**Moves:**
- `Sources/Mobile/AgentChat/` (13 files) → `Sources/AgentChat/` (pbxproj: update the group path; file refs stay).
- `Packages/macOS/CmuxMobileHost/Sources/CmuxMobileHost/AgentChat/` (11 files): simplest is to **shrink**
  `CmuxMobileHost` later (9.16) to just this folder and keep the package name. Cleaner: a new package
  `Packages/macOS/CmuxAgentChatHost` (deps: `CmuxAgentChat`, `CmuxFoundation`, which is all those files import),
  link it in the app target, and change `import CmuxMobileHost` to `import CmuxAgentChatHost` in
  `Sources/AgentChat/*`, `Sources/Search/AgentChatTranscriptService+GlobalSearch.swift`,
  `Sources/Surfaces/CurrentWorkQueryService.swift`, `Sources/ConversationSidebarSupport.swift`.
  Pick one; the new package is a little more work now and less confusion later.

**Build edits:** pbxproj group path; for the new package: a local package reference and product in `cmux` (and
`cmuxTests`).

**Risk:** medium. This is how "resume after restart" for Claude/Codex and the Vault/search lists work. Wrong move
= sessions don't resume.

- ✅ Standard checks (build, `--version`, `config doctor`, `tree --all`; the clicking ones need a manual look).
- ✅ Start `claude` in a terminal, say something, ⌘Q, reopen: the agent resumes in the same terminal (scratch
  workspace; osascript quit, `test-app.sh --no-build`; the terminal ran `claude --resume <same id>` and showed the old turn).
- ✅ `vault sessions`, `vault search cmux`, `sessions list`: same session ids before and after (30 / 30 / 100).
  ⬜ ⌘P global search UI: manual.

### ✅ 9.6 Keep `terminal.paste` / `terminal.input`, cut them loose from Mobile (M, high risk if skipped)

Done (see `git log`, "Phase 9.6"). New `Sources/TerminalInput/` (3 files): `+TerminalPaste.swift` (`v2TerminalPaste`),
`+TerminalInput.swift` (`v2TerminalInput`), `+TerminalTargetResolution.swift` (moved from TC /
`+ControlTerminalBinding`: `MobileTerminalAliasUUID`, `mobileTerminalAliasUUID`, `mobileTerminalAliasValidationError`,
`mobileWorkspaceIDValidationError`, `mobileResolveWorkspaceAndSurface`, `mobileTerminalPanels`,
`mobileCanonicalTerminalTarget`; names kept, the phone files still call them). The new bodies are the mobile ones
minus input delivery/ack (`MobileHostTerminalInputApplier`), `applyMobileViewportReport`, `MobileTerminalByteTee`
(`terminal_seq`) and the `HostLatencyTrace` stamps; errors are the plain `.err` the no-ack branch returned. Took
the "cleaner" coordinator option: new `CmuxControlSocket/Coordinator/TerminalInput/` (`ControlTerminalInputContext`
in `ControlCommandContext`, `handleTerminalInput` before `handleMobileHost`, `handleTerminalInputAsync`); TC routes
`terminal.paste` there; the MobileHost coordinator keeps only `mobile.terminal.paste` / `mobile.terminal.input`
(still on `v2MobileTerminal*`), so 9.11 can delete `Coordinator/MobileHost/` whole. `mobileTerminalPasteInFlightSurfaceIDs`
→ internal `terminalPasteInFlightSurfaceIDs` (shared). Feed "send text" (`AppDelegate`) and notification reply
(`AppDelegate+NotificationDeliverySeams`) now call `v2TerminalPaste`; the phone-reply inbox and `+MobileChat` still
use `v2MobileTerminalPaste`. `mobileDetachedGateError` untouched (only on the phone `mobileHostHandleRPC` path).
Package test stubs got a `ControlTerminalInputContext` extension (not run). Wire names unchanged.

**What it does:** the paste path the cmux agent uses stops depending on `Sources/Mobile` and `CmuxMobileHost`.

**Edits:**
- Find everything `v2MobileTerminalPaste`, `v2MobileTerminalInput` and their helpers need:
  `mobileWorkspaceIDValidationError`, `mobileTerminalAliasValidationError`, `mobileCanonicalTerminalTarget`,
  `mobileInputDelivery`, `mobileInputAdmissionAnswer`, `mobileTerminalPasteInFlightSurfaceIDs`,
  `applyMobileViewportReport`, `MobileHostTerminalInputApplier` (`Sources/Mobile/MobileHostTerminalInputApplier.swift`),
  `TerminalController+MobileInputDelivery.swift`.
- Move them to `Sources/TerminalInput/` (new folder). Drop the mobile-only parts: `applyMobileViewportReport`
  becomes a no-op (no phone viewport), `mobileDetachedGateError` returns `nil`.
- In `CmuxControlSocket/Coordinator/MobileHost/`: keep the `terminal.paste` and `terminal.input` cases and
  `ControlMobileHostContext`'s two members they use. Removing the rest of that coordinator happens in 9.11.
  Keep `terminal.paste` in `ControlCommandExecutionPolicy.swift` (~149) and `TerminalController+Capabilities.swift` (~99).
- Optional: rename `v2MobileTerminalPaste` → `v2TerminalPaste`. The wire name `terminal.paste` must stay.

**Risk:** **high if you skip this step.** `cmux_send` in `cmux-tools.ts` (line ~790) uses `send --paste` for
multi-line text, and `cmux paste` uses `terminal.paste` too. Deleting `Sources/Mobile` without this step breaks
the cmux agent, and only for multi-line messages, so it's easy to miss.

- ✅ Standard checks (build, `--version`, `config doctor`, `tree --all`, `terminal.input`/`terminal.paste` still in
  `system.capabilities`). ⬜ Multi-line `cmux_send` from the cmux agent itself: manual (it is `send --paste`, checked below).
- ✅ `printf 'one\ntwo\n' | "$T" paste --surface <id>` (or `send --paste`) lands as one paste; with `--submit` it
  runs. Through the NIGHTLY CLI too: `"/Applications/cmux NIGHTLY.app/Contents/Resources/bin/cmux" send --paste …`
  from a test-app terminal. (Scratch workspace: `cat` got both lines; a zsh prompt got `echo p1\necho p2` as one
  bracketed paste, ran both on Return; `paste --submit` ran; same with the NIGHTLY CLI via `CMUX_SOCKET_PATH`.
  `rpc terminal.paste` payload `delivery`/`submitted`, `submit_key: none` → `submitted: false`, `Unsupported
  submit_key`, `not_found`, `Conflicting terminal identifiers`, `Missing or invalid workspace_id`; `terminal.input`
  → `queued: false`; `mobile.terminal.paste` still works.) ⬜ Feed reply / notification reply UI: manual.

### ✅ 9.7 Stub: sidebar, footer, right sidebar, TabManager (M, medium risk)

Done (see `git log`, "Phase 9.7"). As planned, plus: the `.upgrade` footer case and `isUpgradeVisible` went with
`SidebarProBadge`; `SidebarFooterButtons` lost its account flow / billing-plan refresh. The DEBUG "Footer Icon Balance
Lab" (cmuxApp.swift, ~770 lines; it balanced the account/mobile/help icons and used `SidebarAccountAvatar` and the
Pro label) is deleted with its menu items, the `__sidebar_footer_icon_balance` v1 command and hidden CLI command; the
DEBUG "Pro Badge Style…" window went with `ProBadgeStyle.swift`. `SidebarFooterProfile*DebugSettings` went too; the
help-icon debug settings stay. Cloud badge: the SwiftUI row no longer renders it; the AppKit row cell still has its
accessory slot (label is nil without cloud/device workspaces; goes with 9.9). `CloudWorkspaceSelectionState` callers
outside TabManager were cut too: `performNewCloudWorkspaceOn{Resolved,Current}MachineAction` now just return
`false`, the Cloud composition's create uses `focus = false`, the Devices create lost its revision fence, and the
`recordCloudWorkspaceSelection:` arguments in `MachinesPanelView`/`ContentView` went. `CloudTreeRowContentView` no
longer shows presence heads. `availableModes`/`isAvailable` lost their `machinesEnabled`/`devicesEnabled`
parameters; `RightSidebarPanelView` lost `devicesModel` and `cloudActivationCoordinator` (`.machines` → `Color.clear`;
ContentView still holds its `devicesModel` for 9.14). `cmux right-sidebar --help` no longer lists `cloud|devices`.
`TabManager` `.cloudVMLoading` default title left for 9.8. Footer/compact sidebar not looked at by eye.

**What it removes:** the cloud and account pieces of the sidebar code. The footer, rows and right sidebar no longer
import `CmuxCloud`, `CmuxCloudMachines`, `CmuxAuthRuntime` or `CmuxWorkspacePresence`.

**Edits:**
- `VerticalTabsSidebar+EmptyAreasAndFooter.swift`: remove `SidebarAccountButtonVisual`, `SidebarAccountButtonPresentation`,
  `SidebarAccountAvatar`, `SidebarMobileConnectButton`, the `.account`, `.mobileConnect`, `.cloud` footer cases,
  `SidebarFooterMobileIconDebugSettings`. Delete `SidebarAccountMenuButtonStyle.swift`, `SidebarAccountTeamPopover.swift`,
  `SidebarCloudWorkspaceBadgeView.swift`, `Sources/Sidebar/SidebarWorkspacePresenceHeadsView.swift`,
  `SidebarProBadge.swift`, `ProBadgeStyle.swift`, `ProBadgeActions.swift`.
- `TabManager.swift`: drop `import CmuxCloudMachines`; delete `TabManager+CloudWorkspaceSelection.swift`;
  `CloudWorkspaceSelectionState` uses go. `TabManager.swift` ~1519 `.cloudVMLoading`: treat like an unknown panel.
- `RightSidebarPanelView.swift`, `RightSidebarMode+Availability.swift`, `RightSidebarMode+ProductFeature.swift`:
  `machines` never available; `from(cliArgument:)` no longer maps `cloud`/`machines`/`devices`. Keep the `.machines`
  case (rule 3; the positional digit shortcuts must not shift).
- `ProductAnalytics+App.swift`, `AppDelegate+NewWorkspaceContextMenu.swift`, `RightSidebarMode+Availability.swift`:
  replace `CloudMachinesFeature` checks with `false`.

**Stub returns:** cloud badge → none, presence heads → none, account → signed out (no button), machines tab →
unavailable.

**Risk:** medium. The footer layout and the compact sidebar (`Resources/sidebars/compact.js`) must look the same.

- ✅ Standard checks (build, `--version`, `config doctor`, `tree --all`). ⬜ ⌘Q/reopen, agents: manual.
- ⬜ Footer looks as before (minus the hidden buttons). Compact sidebar rows unchanged: manual. ✅ `right-sidebar
  files/find/vault/dock` open those modes (`right-sidebar mode`); `right-sidebar machines`/`cloud` → unknown command,
  and the app's `right_sidebar set machines`/`cloud` → "Unknown right sidebar mode". ⬜ Tab shortcuts: manual.

### ✅ 9.8 Stub: terminal, image paste, file explorer, browser (M, high risk)

Done (see `git log`, "Phase 9.8"). Built after each group (terminal + image paste, file explorer, browser).
- Terminal: `cloudTerminalSourcePlacement` → `nil`; both Cloud branches in `Workspace.swift` gone. Kept
  `cloudPaneCreationFailureStore` and `rejectCloudTerminalCreation`/`routeCloudPane*` (still called from
  `Sources/Cloud`, `RemoteTui`, `Devices` and `Surfaces/*Cloud*`; they go with those folders).
- `GhosttyTerminalView`: no `CmuxCloud`/`CmuxCloudBannerCore` import, no `.pasteCloudImages`, no reconnect overlay
  (hit test, frame, observer, presentation; `synchronizeCloudTerminalReconnectOverlay()` is a no-op kept for the
  `Sources/Cloud` callers; `TerminalPortalReconciliation` no longer anchors it). `let cloudTerminalOverlay` stays as
  the Cloud TUI mirror session holder until `Sources/Cloud` goes. `MobileHostDiagnostics.log` → a new app-local ring
  `TerminalWorkDiagnosticLog.log` (in `TerminalGeometryDiagnostics.swift`; a `Logger` cannot feed
  `TerminalSurfaceWorkDiagnostics`); only `iroh_diag`/mobile export read the old ring.
- Image paste: `.cloud` target and `.pasteCloudImages` plan gone everywhere (planner, executor, prepared transfer,
  runtime clipboard read, composer paste, `TextBoxInput` cloud dispatch events and command-template guard).
  Deleted the three files. `attachFileURLs` (local + SSH composer attach) moved to `TextBoxInputContainer+Paste.swift`.
- File explorer: `FileExplorerWorkspaceRoot.remoteCloud` gone; a Cloud binding or projection resolves to `.none`
  (the legacy `ssh:` binding still gives `.remoteSSH`); `FileSearchScope.remoteCloud` gone; header retry is nil.
  Deleted the 9 cloud files. **Plan was wrong:** `CloudFilePreviewCache`/`CloudFilePreviewLease` also serve SSH
  file previews, so they stay (only the cloud-only capacity check went).
- Browser: `BrowserPanel` no longer uses `CloudBrowserRouting`/`CloudDesktopConnectionObserver` (proxy config,
  favicon, replacement web view, desktop observer script), no SSH-TUI loopback routing (`navigate`, resume, nav
  delegate), no `rebindCloudRouteIfNeeded`/`privateAddressRouteProvider`; profile switch/restore no longer configure a
  Cloud browser. No trusted sign-in origin: `BrowserAuthCallbackNavigationPolicy(trustedSourcePageOrigin: nil)` (all
  callbacks blocked), the four `BrowserAppLinkOpenRequest` split-open branches gone, `isNativeAppSessionSurface` →
  false. `+AppPricingRestore.swift` deleted. **Kept, differs from plan:** `BrowserPanel+CloudConnection.swift`
  (trimmed to the glue `Sources/Cloud`/`CmuxTuiSurfaceProvider` call; `preferredURLStringForSessionSnapshot` moved to
  `+PageRestoration`), `cloudAccess` (model always nil), `+MobileBrowserStreaming.swift` and `MobileBrowser*.swift`
  (their callers are in `Sources/Mobile`, 9.14), and `+MobileBrowserDialogs.swift`, which is **local**: it is the JS
  dialog broker behind `cmux browser dialog accept|dismiss` and the native alerts. Session restore of a saved
  `cloudResource` left for 9.9.
- Not done (left for 9.12): `TerminalPanel.cloudAttachment`, `CloudPaneCreationFailureView`,
  `MachineCreateLoadingContent`, `CloudVMLoadingPanel*`. Every `.cloudVMLoading` creator is a Cloud flow that no
  longer runs, and restore already returns `nil`; deleting them now would cascade into `Sources/Cloud`/`Surfaces`.

**What it removes:** the cloud branches inside the local terminal, paste, file explorer and browser code.

**Edits:**
- `Workspace.swift`: `cloudTerminalSourcePlacement(forPanel:)` → `nil`; delete the `routeCloudPaneTerminalTab` and
  `rejectCloudTerminalCreation` branches (~9367, ~9737) and `cloudPaneCreationFailureStore`. Keep the remote tmux
  branch and `newTerminalSurfaceLocal`.
- `GhosttyTerminalView.swift`: remove `.pasteCloudImages` handling (~10337–10430), `cloudTerminalOverlay` and the
  reconnect overlay (~10776, 11460–11710, 11894, 12612), `import CmuxCloud`, `import CmuxCloudBannerCore`. Replace
  `MobileHostDiagnostics.log` (~348) with a `Logger`. Keep `mobileViewportBorderOverlayView` for now if
  `CmuxTerminalSharing` still drives it.
- `TerminalImageTransfer.swift`: remove the `.cloud` target and `CloudImagePasteError`. Delete
  `TerminalSurface+CloudImagePaste.swift`, `TextBoxInputContainer+CloudImagePaste.swift`,
  `Sources/Cloud/CloudImagePasteInputLease.swift`.
- File explorer: `FileExplorerWorkspaceRootResolver.swift` drops `AuthenticatedTeamScope` / `ManagedCloudPolicy`;
  `FileExplorerStore.swift` never picks the cloud provider. Delete `FileExplorerSearchController+Cloud.swift`,
  `CloudFileExplorer*.swift`, `CloudVMFileExplorerProvider.swift`, `LiveCloudFileExplorerCommandRunner.swift`,
  `CloudFilePreviewCache.swift`, `CloudFilePreviewLease.swift`.
- Browser: `BrowserPanel.swift` loads URLs directly (no `CloudBrowserRouting`, no `CloudDesktopConnectionObserver`);
  delete `BrowserPanel+CloudConnection.swift`, `+MobileBrowserDialogs.swift`, `+MobileBrowserStreaming.swift`,
  `+AppPricingRestore.swift`, `Panels/MobileBrowser*.swift`; `BrowserNavigationDelegate.swift` and
  `BrowserPopupWindowController.swift`: no trusted sign-in origin (`nil`).
- `TerminalPanel.swift` (`CloudTerminalAttachmentStatus`), `Panels/CloudPaneCreationFailureView.swift`,
  `Panels/MachineCreateLoadingContent.swift`, `Panels/CloudVMLoadingPanel*.swift`: `.cloudVMLoading` panels are
  never created; restore returns `nil`.

**Risk:** high. This is the code every terminal runs. Change only cloud branches; build after each file group.

- ✅ Standard checks (build, `--version`, `config doctor`, `tree --all`). ⬜ ⌘Q/reopen, agents: manual.
- ✅ New tab (`new-surface`) and new split (`new-split right|down`) in a scratch workspace; `send` + `read-screen`
  round-trips in each. ⬜ ⌘T by keyboard and a remote tmux workspace: manual.
- ✅ Drop by socket (`debug.terminal.simulate_file_drop`): file URL on the text-destination and terminal routes
  inserts the escaped path; image data inserts a temp PNG path. ⬜ Screenshot paste into `claude`, real drag, plain
  text paste: manual.
- ✅ `right-sidebar files` opens Files. ⬜ Its content, Find, file preview: manual (no socket method shows them;
  screenshots fail from the worker).
- ✅ `open https://example.com` from a test-app terminal opens a cmux browser split. ✅ `browser open
  https://example.com`, `get url`/`get title`/`snapshot`/`eval`, `goto` another page, `back`/`forward` (URLs
  right; a `wait --url-contains` fired right after back/forward timed out once, then worked after it settled),
  `dialog accept` on a `confirm()`, `close-surface`. ⬜ Popup, download: manual.

### ✅ 9.9 Stub: session restore and workspace cloud binding (M, medium risk)

Done (see `git log`, "Phase 9.9"). Differs from plan:
- `Workspace.cloudVMBinding` is a stub (`get { nil }`, setter ignored) instead of gone: ~40 writers/readers in
  `Sources/Cloud`, `Surfaces` and `Devices` still name it (they go in 9.12/9.14). Every local reader (Workspace,
  sidebar directories, Files root, agent title, git-branch report, AppDelegate Base/new-workspace checks, the
  `remote.status` payload, which now always reports `cloud_vm_*` as null) dropped it. **Kept for now:**
  `WorkspaceCloudVMBinding*.swift` (the type) and `WorkspaceCloudBindingState.swift` (lost its `binding`; it
  still carries the device projection metadata the Surfaces/Devices code writes). The AppKit row's
  cloud/device badge slot stays until Devices goes (9.14).
- Session: `cloudVM`, `cloudMachineTeams`, `SessionCloudVMBindingSnapshot`, `restoredCloudVMBinding` gone (also
  from import trust, closed-history and `DisableCloud` restore policy). `surfaceProjections` **stays** (device
  projections, 9.14); restore no longer reserves Cloud terminal panes and only re-attaches a browser
  `cloudResource` for a device machine.
- `workspace.cloud_vm_open` / `cloud_vm_terminal_ready` / `cloud_vm_bind` always answer with the Cloud-disabled
  error; `managedCloudVMID` configs always suspend; `reconnectCloudTerminalSurface` only retries device panes.
- SSH-TUI: deleted `SessionRemoteWorkspaceSnapshot+TuiSSH`, `SSHTuiAgentStatusProjector` (its two statics moved into
  `RemoteTmuxAgentStatusProjector`), `SSHTuiAttachRetry`, `SSHTuiWorkspaceCoordinator`, `TerminalController+SSHTui`,
  `+SSHTuiSessions`, `Workspace+SSHTui`, `+SSHTuiStatus` (`tuiMirrorSession` moved to
  `Surfaces/Workspace+CloudManualMirror.swift`). `DetectedSSHSession+Workspace.swift` and
  `TerminalController+SSHWorkspaceResolution.swift` moved to `Sources/` (`fileOperationSSHOptions` is plain
  `sshOptions`). Native-SSH fork/respawn/upload/link/reconnect branches gone; `workspace.ssh.open` removed
  (dispatch, capabilities, execution policy); `ssh_session_attach.resolve`, `remote.pty_sessions`, `pty_close` use
  only the plain path. **Still in `RemoteTui/`:** `SSHTuiLinkManager`, `RemoteTuiLinkManaging`, `RemoteTuiMachine`
  (the Cloud surface provider uses them, 9.12). `CmuxCore` still writes `sshSessionOwner = "cmux-tui"` into saved
  SSH snapshots (harmless; 9.15+).
- **`routesThroughSSHTui` trap:** replaced by `WorkspaceRemoteConfiguration.isRelaylessSSHRecoveryDescriptor`
  (SSH, no relay, no daemon endpoint, `preserveAfterTerminalExit`). Such a config (a saved cmux-tui carrier now
  restores through the "preserve for recovery" branch) is stored **disconnected and never dials**, gets no
  startup command, and its terminals restore as placeholders, as before. Relay-less configs without
  `preserveAfterTerminalExit` now take the legacy `configureRemoteConnection` path (upstream's pre-TUI behaviour).
  Your session has none of these.

**What it removes:** cloud machine bindings in the saved layout, and (if decided) SSH-TUI.

**Edits:**
- `Workspace.swift` 211, 309, 327, 406, 1647, 3350, 7422, 8050, 10231, 10390: `cloudVMBinding` is always `nil`;
  remove the code that reads or writes it, and the cloud projection records.
- `SessionPersistence.swift`: drop `cloudVM`, `cloudMachineTeams`, `SessionCloudVMBindingSnapshot` (rule 2).
  `SessionSnapshotImportTrust.swift` 106–116: drop the two fields from the check; keep `remote`.
- Delete `WorkspaceCloudBindingState.swift`, `Sources/RemoteTui/WorkspaceCloudVMBinding*.swift`.
- `Workspace+RemoteSessionLifecycle.swift`, `TerminalController+WorkspaceCreate.swift`,
  `TerminalController+ControlWorkspaceContext.swift`: `CloudMachinesFeature` / `ManagedCloudPolicy` checks → local only.
- SSH-TUI goes (if decided): `Sources/RemoteTui/` except what remote tmux needs; check
  `SessionRemoteWorkspaceSnapshot+TuiSSH.swift` (a `remote` snapshot with `sshSessionOwner == "cmux-tui"` then
  restores as a plain SSH workspace or nothing).

**Risk:** medium. Your files have none of these fields, so restore is the same. The trap is a restore helper that
assumes the binding exists; test with `--seed`.

- ✅ Standard checks with `--seed` (build, `--version`, `config doctor` same as baseline). `tree --all` +
  `workspace.group.list`: same names, groups, order and pinned row as Personal's current session (13 workspaces;
  the baseline's 11 are all there, Personal has gained "Schjødt SWAT alts" and "Presentation" since). ⬜ Agents: manual.
- ✅ Quit (osascript), edit nothing, reopen with `--no-build` twice: identical each time.

### ✅ 9.10 Stub: app composition, auth and URL routing (M–L, high risk)

Done in two commits (see `git log`, "Phase 9.10 (1/2)" and "(2/2)"). Differs from plan:
- (1/2) `cmuxApp` builds no `MacAuthComposition`, Cloud workspace composition or `MacDevicesComposition`
  (both files deleted). **Trap:** `MacDevicesComposition` also built the Settings `UserDefaultsSettingsStore`; cmuxApp
  now builds it directly. `SettingsRuntime` gets no `accountFlow` (nil); `HostSettingsActions` gets no
  `computersActions` / `cloudActivationCoordinator`. `configure(…)` is down to tab manager, notification store,
  sidebar state, settings runtime, automation engine and browser import. Its body no longer wires Cloud
  telemetry/operations/tunnel, `VMClient`/`CoderouterClient.bootstrap`, `MobileHostService.configure(auth:)`, the
  phone-reply inbox, connectivity subscribers, paired-Mac backup, `attachAuth` or `auth.start()`; the no-op
  mobile-host settings observer went too.
- **Kept, differs from plan:** the AppDelegate properties (`auth`, `cloudMachinePinStore`,
  `cloudWorkspaceCoordinator`, `cloudWorkspaceOperationController`, `deviceWorkspaceCreationCoordinator`,
  `newMachineSheetPresenter`, `devicesRegistry`, `cloudTunnelCoordinator`, `cloudOperations`, the lazy
  `cloudActivationCoordinator`) and `TerminalController.shared.cloudTunnel` stay declared, always nil / never
  built, because `Sources/Cloud`, `Surfaces`, `Devices`, `Hive` and the `AppDelegate+Cloud*`/`+Account*`/`+Team*`
  files still read them (9.12–9.14 delete those readers). The files in the plan's "other users" list are
  untouched for the same reason; with nil they take their signed-out/unavailable paths.
  `ensureMobileWorkspaceListObserver` and `MobileTerminalRenderObserver.start()` are left for 9.14.
- (2/2) Quit path: no `CloudNotificationSyncHub` pending-writes gate or drain (only Cloud/Devices wrote it), no
  `MobileHostService.stop()`, `cloudWorkspaceOperationController?.cancelAll()`, presence goodbye, connectivity
  teardown, `CloudVMActionLauncher.terminateAll()`, tunnel teardown or WireGuard hub stop. Read
  `applicationShouldTerminate` → `deferTerminateForOwnedCleanupAndFreshSnapshot` (still saves the session before
  replying) and `applicationWillTerminate` (backstop save, history/profile flushes) end to end: save order
  unchanged. URL routing: `application(_:open:)` handles workspace/`ssh`/text links and files only, no auth
  callback branch; `handleAuthCallbackURLInProcess` (still called by the browser's callback policy, which blocks
  every callback since 9.8) returns `false`.

**What it removes:** the auth graph and cloud coordinators that `cmuxApp` builds and hands to `AppDelegate`.

**Edits:**
- `cmuxApp.swift` 97: no `MacAuthComposition()`. `configure(…)` (255–280) loses `auth`, `cloudMachinePinStore`,
  `cloudWorkspaceCoordinator`, `cloudWorkspaceOperationController`, `newMachineSheetPresenter`, `devicesRegistry`,
  `computersService`. Delete `cmuxApp+CloudWorkspace.swift`, `App/MacDevicesComposition.swift`.
  `hostSettingsActions.cloudActivationCoordinator` goes.
- `AppDelegate.swift`: the matching properties (842 `auth`, 847 `cloudActivationCoordinator`, 878, 1219
  `cloudTunnelCoordinator`, `cloudOperations`, `devicesRegistry`, …) and the body of `configure` from 2494 on.
  `TerminalController.shared.cloudTunnel` goes.
- URL routing (1548, 1579 `auth?.callbackRouter ?? AuthCallbackRouter()`): drop the auth callback branch; keep the
  workspace-link and `ssh://` handling in `AppDelegate+CmuxSSHURL.swift`.
- Quit path: remove the `CloudNotificationSyncHub` waits (~2088, ~2150) and `MobileHostService.shared.stop()` (2424).
  Read `applicationShouldTerminate` / `applicationWillTerminate` (2288, 2389) end to end afterwards: the session
  save must still run before exit.
- Other users of the auth/cloud objects: `HostSettingsActions.swift`, `HostSettingsActions+Cloud.swift`,
  `AppDelegate+ManagedPolicy.swift`, `ManagedPolicyEnforcementObserver.swift`, `AppDelegate+TeamScope.swift`,
  `AppDelegate+AccountSignInWorkspace.swift`, `AppDelegate+CloudMachineWorkspaceClosure.swift`,
  `AppDelegate+CloudTerminalNavigation.swift`, `AppDelegate+CloudTunnel.swift`, `AppDelegate+NewCloudWorkspace.swift`,
  `AppDelegate+CloudTeamPicker.swift`, `AppDelegate+NewDeviceWorkspace.swift`, `AccountAnalyticsState.swift`,
  `HostAccountFlow+Analytics.swift`, `Sources/Auth/PostHogIdentityObserver.swift`.

**Risk:** high. A mistake here stops the app from launching or from saving on quit. Do it in two commits if it
gets big: first `configure` and its callers, then the quit path and URL routing.

- ✅ Standard checks after each commit (build, `--version`, `config doctor` same as baseline, layout incl. groups
  matches Personal's current session; Personal had meanwhile moved the Schjødt group up). ✅ Quit (osascript)
  **three times in a row**, reopen with `--no-build` each time: identical layout. ⬜ Agents: manual.
- ✅ `open "cmux-dev-test://workspace/<id>"` (two different workspaces): the test app selects that workspace.
  ⬜ Clicking the link from Safari: manual.
- ⬜ Settings → App, Terminal, Sidebar, Automation, Keyboard Shortcuts all open: manual.

### ✅ 9.11 TerminalController and control socket: remove cloud, auth and mobile methods (M, medium risk)

Done (see `git log`, "Phase 9.11"). `system.capabilities` lost 149 methods, all in the allowed families: 73 `vm.*`,
43 `mobile.*`, 16 `auth.*`, 10 `coderouter.*`, 3 `remotes.*`, `workspace.cloud_vm_open` / `_terminal_ready` /
`_bind` (and `workspace.ssh.open`, gone since 9.9). Nothing was added. Differs from plan:
- **Plan was wrong: `auth.login` is local.** It is the socket-password acknowledgement (`SocketPasswordAuthorization`),
  not the cloud account, so it stays (dispatch and capability). Only the account `auth.status` / `sign_in_url` /
  `begin_sign_in` / `sign_out` / `auth.team.*` went.
- CodeRouter handoff: `coderouter.handoff.begin/arm/complete` were a framed handshake inside the socket connection
  loop. That handling went from the loop, `authorizedSocketCommand` (`AuthorizedSocketCommand` is just `command`
  now), `processSocketLine` (only the handoff used it), the worker switch and the init (`attachAuth`,
  `codeRouterHandoffService`, arm grant store). Deleted `Sources/Cloud/CodeRouterHandoffArmGrantStore.swift`,
  `CodeRouterHandoffClient.swift`, `CodeRouterSocketPeerVerifier.swift`, `CoderouterSocketCommands.swift`. The
  `CodeRouter*` types in `CmuxControlSocket` (line reader handshake budget, proof) stay unused (9.15+).
- **Kept, not in the allowed families:** the bare `terminal.create/replay/viewport/scroll/mouse/paste_image`
  (`paste_image` was already `method_not_found` on the control socket) and `aiAccounts.*`. `aiAccounts.*` now
  answers `cloud_disabled` from a stub in the worker switch (its handler lived in `VMClientSocketCommands.swift`;
  before this step `aiAccounts.list` crashed the test app). So `Coordinator/MobileHost/` and
  `TerminalController+ControlMobileHostContext.swift` stay, trimmed to those five `terminal.*` verbs; the
  `mobile.*` aliases, `handleMobileHostAsync` and the chat/task members went. The bodies they need stay:
  `+MobileWorkspaceList.swift`, `+MobileScrollPrefetch.swift` and a trimmed `+MobileSurfaces.swift` (surface
  descriptors, todo payload, `mobileNonEmpty`, and `mobileBrowserPanelCorrelation` for `Sources/Mobile`). The
  undocumented `chat.sessions.dump` (never advertised) went with `+MobileChat.swift`.
- The phone data-plane `mobileHostHandleRPC` (called only by `MobileHostService`, 9.14) is a `method_not_found`
  stub. Dead phone bodies in `TerminalController.swift` went (`v2MobileHostStatus`, `v2MobileWorkspaceAction`,
  `v2MobileTerminalSetFont`, compatible tags, dogfood, `v2MobileTerminalPasteImage`); `v2MobileTerminalInput` /
  `Paste`, the viewport governor and `v2MobileWorkspaceCreate`/`Move`/group variants stay for 9.14 (the phone-reply
  inbox and `Sources/Mobile` still name some of them).
- Deleted: `TerminalController+AuthTeam.swift`, 15 `TerminalController+Mobile*.swift` (all but `InputDelivery`,
  `WorkspaceList`, `ScrollPrefetch`, `Surfaces`), `Sources/Cloud/VMClientSocketCommands*.swift` (4),
  `Sources/Cloud/TerminalController+CloudDiagnostics.swift` (`vm.file_transfer_failure`, `v2CloudCall`), the async
  `vm.terminal_rename`/`vm.tab_rename` lane and its deadline helper. `noteAcceptedAgentInput` (Feed attention, local)
  moved to `Sources/TerminalInput/TerminalController+TerminalInput.swift`.
- **Plan was wrong: `TerminalController+RemoteRelay*Authorization.swift` are SSH remote-relay** (`CmuxRemoteWorkspace`,
  the remote daemon relay), not cloud. Kept.
- v1 `iroh_diag` removed (and from the policy's diagnostic-read set, now empty). DEBUG
  `mobile.dev_stack_auth.configure` removed (coordinator, system context, debug method list). `debug.mobile.*` and
  `debug.cloudtree.*` stay (not in the allowed families).
- `TerminalController+SharedSizing.swift`: no `MobileHostIdentity` or `import CmuxCloud`; the local sizing
  identity has no user and its device id hashes the stored `mobileHost.deviceID` default (fallback `local-mac`).
  The `MobileHostService` event emits stay until 9.14.
- `ControlCommandExecutionPolicy`: no `vm.`/`remotes.`/`coderouter.` prefixes, auth/mobile entries; `aiAccounts.`
  prefix kept for the stub. Package tests (`ControlCommandCoordinatorMobileHostTests`, policy tests) not updated (not run).
- `v2VmCall` stays: browser profiles, remote tmux and `Sources/Surfaces` use it; its `VMClientError` mapping goes
  with the Cloud package (9.15). `TerminalController.cloudTunnel` stays for `Sources/Cloud` (9.12).
- `cmux ssh` (plain path in `CLI/cmux.swift`) never called `workspace.ssh.open`: it uses `workspace.create`,
  `workspace.remote.configure/reconnect`, `remote.tmux.sessions`. Nothing in `~/Code/cmux-config` uses a removed method.

**What it removes:** the socket methods only upstream's servers, phone or cloud CLI used.

**Edits:**
- `TerminalController.swift`: `iroh_diag` (1509), `auth.*` (1742–1774), the `mobile.*` cases (1960–1988 and
  15480–15643, **except** the shared `terminal.*` aliases kept in 9.6), `vm.*` (2275), `remotes.*`, `phone_push.*`,
  `dogfood.feedback.submit`. Drop `import CmuxCloud`, `CmuxMobileHost`, `CmuxAuthRuntime` when nothing is left.
- Delete `TerminalController+AuthTeam.swift`, `TerminalController+Mobile*.swift` (~20, not the input files moved in
  9.6), `TerminalController+ControlMobileHostContext.swift`, `TerminalController+RemoteRelay*Authorization.swift`
  (check first: these may serve SSH relay; keep if `RemoteTmux*` or `cmux-tmux-agent.py` uses them),
  `Sources/Cloud/VMClientSocketCommands*.swift`, `Sources/Cloud/CoderouterSocketCommands.swift` (if the CodeRouter
  commit left it).
- `TerminalController+SharedSizing.swift`: no `MobileHostIdentity`.
- `CmuxControlSocket`: `Coordinator/MobileHost/` keeps only `terminal.paste` / `terminal.input`;
  `ControlCommandCoordinator+System.swift` (30 `auth.login`, 49 `mobile.dev_stack_auth.configure`);
  `ControlCommandExecutionPolicy.swift` mobile/vm entries; `TerminalController+Capabilities.swift` lists.

**Risk:** medium. The NIGHTLY CLI talks to this app. Compare `system.capabilities` with the baseline: only `vm.*`,
`auth.*`, `mobile.*`, `remotes.*`, `phone_push.*`, `dogfood.*`, `chief.*`, `coderouter.*` may disappear.

- ✅ Standard checks (build, `--version`, `config doctor` same as baseline, `tree --all`). ⬜ ⌘Q/reopen, agents: manual.
- ✅ `diff` the new `system.capabilities` against `/tmp/cmux-baseline/`: only the allowed families went. Every method in
  removal-plan.md's list is still there, plus `terminal.paste`, `terminal.input`, `surface.catalog`, `surface.project`,
  `surface.new_terminal`, `current.list`. `vm.list`, `auth.status`, `mobile.host.status`, `remotes.list`,
  `workspace.cloud_vm_open` → `method_not_found`; `auth.login` and `terminal.replay`/`viewport` still answer.
- ✅ pi-cmux verbs via the test CLI in a scratch workspace (closed after): `set-status` (`mykey`), `set-progress`, `log`,
  `notify`, `new-split right`, `respawn-pane --command`, plus `send --paste` multi-line. ⬜ From a real Pi session: manual.
  (`set-status pi run` answered OK but listed no entry; looks like the reserved agent key, not checked against Personal.)

### ⬜ 9.12 Delete `Sources/Cloud` and the top-level cloud files (M, medium risk)

**Decided order (coordinator, after the revert below):** delete from the leaves inward, one commit per folder, each
commit builds: (A) `Sources/Hive`, (B) `Sources/Devices`, (C) `Sources/Mobile` (9.14, incl. its `CmuxSettingsUI`
sections and the terminal-output hooks), (D) `Sources/Auth` (9.13), (E) the cmux-tui/Cloud provider files in
`Sources/Surfaces`, (F) `Sources/Cloud` plus the top-level cloud files (this step). A file that stays and names a
deleted type gets the reference stubbed or removed, even in folders a later commit deletes.

**Tried after 9.11 and reverted (needs a decision).** Deleting the 243 listed paths (all of `Sources/Cloud`, the
top-level files below, the four deferred `Panels` files, `Resources/CloudWelcome`; **not** `CloudFilePreviewCache`/
`Lease`, which serve SSH) is clean in the pbxproj, but the build then needs edits in about 70 files that name types
from the deleted files and many more that use their extension members. The blocker is the order: folders that later
steps delete still depend on `Sources/Cloud` and must compile in 9.12:
- `Sources/Mobile` (9.14): `PhonePushClient`/`PhonePushAdmission`/`PhoneForwardingMode`, `PresenceHeartbeatClient`,
  `MacPairedMacBackupPublisher`.
- `Sources/Devices` (9.14): `CloudVMSyncSubscriber`, `PresenceHeartbeatClient`, `CloudFeatureAvailabilityObserver`,
  `CloudTreeNodeActions`, `CloudWorkspaceOperationController`, `CloudNotificationSyncHub`/`LocalDelivery`, `CloudTreeRevealRequest`.
- `Sources/Hive` (9.14): `CloudFeatureAvailabilityObserver`. `Sources/Auth` (9.13): `CloudTeamScopeObserver`,
  `DeviceRegistryClient`, `ProUpgradePresenter`.
- `Sources/Surfaces`: the cmux-tui provider (`CmuxTuiSurfaceProvider*`, ~45 files) and `Cloud*`/`Workspace+Cloud*`
  files use `CloudTuiManualMirror*`, `CloudPortAccess*`, `CloudGuestURLService`, `CloudTreeNodeBuilder`; the local
  `SurfaceCatalog` (`surface.catalog`, `current.list`) is built with `CloudSidebarOrganizationStore`.
Options: (a) fold 9.13/9.14 (Auth, Mobile, Devices, Hive) and the Surfaces cmux-tui/Cloud files into this step (L);
(b) keep the handful of `Sources/Cloud` files those folders need until 9.14; (c) stub the uses inside the folders
that go later. The import grep below can only pass with (a) plus more: ~130 files outside Cloud/Mobile/Devices/Hive/Auth (Surfaces 70,
Panels 9, AppDelegate, TerminalController, Workspace, …) still `import CmuxCloud`.

**What it removes:** `Sources/Cloud/` (~230 files, ~37,500 lines) and `AppDelegate+Cloud*.swift`, `cmuxApp+CloudMenu.swift`,
`Cloud*.swift` at the top of `Sources/`, `CmuxFeatureFlags+Cloud.swift`, `CloudVMActionLauncher.swift`,
`CloudSizingPhoneRelaying.swift`, `CloudTerminal*.swift`, `PricingPlansScreen.swift`, `ProWelcomeChecklist.swift`,
`UpgradePromptImpression.swift`, `ProductAnalyticsEvent+Upgrade.swift`, `ContentView+ProCommandPalette.swift`,
`Sources/Debug/CloudWelcomeDebugMenu.swift`, `Resources/CloudWelcome/` (1.2 MB of videos), and `IrohTransportDebugMenuButtons.swift`.

**First:** `grep -rln "WorkspacePresenceController\|CloudTuiManualMirror" Sources` — the manual-mirror files in
`Sources/Cloud` use `CmuxTerminalSharing`; make sure nothing outside `Sources/Cloud` needs them.

**Build edits:** pbxproj file removals (use the script), the `CloudWelcome` folder resource.

**Risk:** medium: only compile errors, if 9.7–9.11 were complete. Each error points at a reference that was missed.

- ⬜ Standard checks.
- ⬜ `grep -rln "import CmuxCloud$" Sources CLI` → only files you plan to delete in 9.13/9.14.

### ✅ 9.13 Delete Account, sign-in and team screens (S–M, low risk)

Done in "Phase 9.13 (D)" (order (D) under 9.12). Deleted `Sources/Auth/` (34 files, incl. `BrowserAppSession/` and
the sign-in panel files), `AccountAnalyticsState.swift`, `HostAccountFlow+Analytics.swift`,
`AppDelegate+AccountSignInWorkspace.swift`, `AppDelegate+CloudTeamPicker.swift`; in `CmuxSettingsUI`
`Sections/AccountSection.swift`, the whole `Account/` folder (cards, `AccountFlow`, `AccountTeamSummary`, …),
`SettingsRuntime.accountFlow`, and the two tests on those types. `AppDelegate.auth` is gone (it was never set since 9.10).
Differs from the plan:
- **`.account` case removed from both `SettingsSectionID` (package) and `SettingsNavigationTarget` (app)**; each has a
  hand-written `init?(rawValue:)` that maps `"account"` to `.app`, so stored `selectedSectionRaw`, navigation
  notifications and `cmux settings open account` land on App (`OK target=app`). Account search entries/aliases went.
- Also deleted from `Sources/Cloud` (they named `HostAccountFlow`/`AccountSignInModel`/`AccountTeamSummary`):
  `MachinesPanelView` (+`Activation`, +`TeamScope`), `MachinesCloudStatus`, `CloudTeamPicker{Header,Menu,MenuAnchor,Row}`,
  `CloudCreateTeamSheet`(+`Presenter`), `CloudTeamInvitePopover`. The right sidebar `.machines` case renders nothing
  (mode stays for stored values). `CloudTeamPickerPresentation` kept as three flags (`FileExplorerState` holds it).
- Stubs: auth palette commands (sign in/out, team picker/members) removed from `ContentView+AuthCommandPalette.swift`
  (Cloud palette part stays for (F)); `.accountSignIn` panels render nothing; every `auth?.accountFlow…` read is
  `false`/`nil` (Cloud VM launcher, menus, welcome card, settings Cloud actions, pricing plan load without tokens);
  team scope lookups in the cmux-tui registry are `nil`; Cloud menu `CloudMenuAccount.teams` uses a local `CloudMenuTeam`.
- Browser: the app-session bootstrap (`beginAppSessionBootstrapIfNeeded`) always returns `false`
  (`isNativeAppSessionSurface` was already `false`), `signedInAppSessionRequest`/`adoptAppSessionStore`/
  `appSessionRequestProvider` went; the app-link handoff wiring in `Workspace`/`DockSplitStore` went (the
  `openAppLinkInBrowserSplit` closure was never invoked). Left for later: the now-unused `appSessionBootstrapTask`
  bookkeeping in `BrowserPanel`, `openAppLinkInBrowserSplit` properties on the panel/delegates, `CmuxBrowser`'s
  `AppSession/` package files, `AccountCatalogSection` keys in `CmuxSettings` (9.15).
- Checks: build, `--version`, `config doctor` (same as before), `tree --all`, 388 methods (no change),
  `surface.catalog`/`current.list` same keys. ⬜ Manual: Settings window opens on App (no Account row).

**What it removes:** `Sources/Auth/` (34 files), sign-in panel files,
`AppDelegate+AccountSignInWorkspace.swift` (if not gone), and in `CmuxSettingsUI`: `Sections/AccountSection.swift`,
the `.account` section case (move the compatibility mapping to `.app`), and `BrowserAppSession` (the web sign-in bridge).
`PanelType.accountSignIn` stays.

**Build edits:** pbxproj file removals.

- ✅ Standard checks (build, `--version`, `config doctor`, `tree --all`). ⬜ ⌘Q/reopen, Settings window: manual.
- ✅ `"account"` decodes as App (`cmux settings open account` → `OK target=app`); `selectedSectionRaw = "account"` goes
  through the same `init?(rawValue:)`.

### ✅ 9.14 Delete Mobile pairing, Devices and Hive (M, medium risk)

Done in three commits, "Phase 9.14 (A)", "(C)", "(B)" (in that order, see under 9.12). One deferral: the
`CmuxSettingsUI` Devices section pieces go with 9.12 (F), see (B) below.
- (A) `Sources/Hive` deleted ("Phase 9.14 (A)"). `HiveAccountTokenSource` users in `Sources/Devices`
  (`DeviceDirectory`, `DeviceLinkRuntime`, `DeviceSurfaceProviderRegistry`, `DeviceRegistryDirectoryClient`) and
  `Sources/Cloud/CloudVMSyncSubscriber` now throw `CancellationError` instead of fetching account tokens (all dead
  since 9.10); the `HiveComputersService: DeviceLinkAuthorizationSource` conformance went. `CmuxHive` package stays
  (9.16). Build + `--version`, `config doctor` (same as 9.11), `tree --all`, 396 methods (no change).
- (C) `Sources/Mobile` deleted ("Phase 9.14 (C)"), done **before** (B): Mobile named Devices types in ~80 places
  (`MobileHostIrxRuntime`), Devices named Mobile in two small files, so this order needed far fewer stubs. Also
  deleted: `MacPresenceDecisionCache.swift`, `MobileNotificationFeedWireItem.swift`,
  `TerminalController+ControlMobileHostContext/+MobileScrollPrefetch/+MobileInputDelivery.swift`, the
  `CmuxControlSocket` `Coordinator/MobileHost/` domain, and in `CmuxSettingsUI` `MobileSection`, the four
  `Iroh*` section files, `IrohSettingsModel`, the mobile pairing/phone-push bindings and environment types and their
  `SettingsHostActions` requirements (and `HostSettingsActions` witnesses). Differs from the plan:
  - **Moved, local:** `MobileTerminalByteTee` → `Sources/TerminalOutputByteTee.swift` (`TerminalOutputByteTee`,
    trimmed to the PTY fan-out `surface.wait_text_change` parks on; replay buffer, render-grid identities and
    `terminal.bytes` went). `TerminalTheme(ghosttyConfig:)` → `Sources/TerminalTheme+GhosttyConfig.swift`
    (agent chat theme). `Workspace+MobileAgentStatus.swift`, `TerminalController+MobileWorkspaceList/+MobileSurfaces`
    stay (local `workspace.group.*`/move/create answers use `v2MobileWorkspaceList`). `PIDPresence`,
    `PortTerminalDeviceLookup`, `MacPresenceMonitor` stay (local).
  - **Socket methods removed (8, all phone-only):** `terminal.create`, `terminal.replay`, `terminal.viewport`,
    `terminal.scroll`, `terminal.mouse`, `terminal.paste_image` (was already `method_not_found`), DEBUG
    `debug.mobile.transport.disconnect` / `reconnect_loop`. 396 → 388. `system.capabilities` `"capabilities"`
    (the phone feature flags such as `events.v1`, `feed.v1`) is now `[]`; nothing in `CLI/` reads it.
  - Terminal-output hooks: `MobileTerminalRenderObserver.start()` (AppDelegate) and the render/viewport calls in the
    removed verbs went; the tee callback now only feeds `TerminalOutputByteTee`. The viewport governor bodies in
    `TerminalController` stay (now never fed) for a later cleanup.
  - Stubs (later steps delete them): `performMobileConnectWorkspaceAction` returns nil (palette, menu,
    `workspace.action mobile_connect` answer unavailable as when hidden); `.mobilePairing` panels render nothing;
    `emitMobileSizeState`/`emitMobileDetached` no-ops; phone event emits (agent chat, feed, notifications) dropped;
    `MobileHostStatusObserverToken` (generic observer token in `HostSettingsActions`) keeps its name.
    In `Sources/Cloud`: mobile-host status observers stubbed, `isListeningEnabled` → `false`. In `Sources/Devices`:
    `DeviceWorkspaceLayoutHost` reduced to its three name constants.
  - `SettingsSectionID` `.mobile`/`.networking` cases **kept** (hidden since 9.1, raw values are persisted); only their
    slots and views went. `BrowserPanel+MobileBrowserStreaming` stays (woven into `BrowserPanel`); only the phone
    input replay went. JS dialogs untouched.
  - Checks: build, `--version`, `config doctor` (same as 9.11), `tree --all`, 388 methods (list above);
    scratch workspace: `yes | head -100000` then `vim` render (read-screen shows numbered lines, `~`, status),
    `surface.wait_text_change` woke ~60 ms after output, `send --paste` multi-line, closed after.
    `surface.catalog`/`current.list` answer. ⬜ Manual: Settings opens (no Mobile/Networking), browser JS dialogs.
- (B) `Sources/Devices` deleted ("Phase 9.14 (B)", 53 files incl. `Account/`, `Workspace+DeviceLayout`,
  `Workspace+DeviceMachineContext`, `SurfaceCatalog+DeviceNames`, `AppDelegate+NewDeviceWorkspace`), plus
  `Sources/Cloud/DeviceLinkDiagnosticsSection.swift`. Differs from the plan:
  - **Moved, local:** `DeviceTerminalAttachmentStatus` → `Sources/Panels/` (the "disconnected" overlay on restored
    relay-less SSH recovery placeholders, `restoreDeviceDisplayPanel`).
  - Removed refs: AppDelegate `devicesRegistry`, `deviceWorkspaceCreationCoordinator`, `openDevicesSidebarAndReveal`,
    the device branch of new-workspace routing; `ContentView.devicesModel`; `SurfaceCatalog.reconcileDeviceNames`
    calls (returned early for non-device machines); the device layout snapshot/keys on
    `workspacePaneGeometryDidChange`; `CloudTerminalPaneReservation.attach(DeviceTerminalInputRouter)`.
  - Stubs in `Sources/Cloud` (deleted in 9.12): `CloudVMSyncSubscriber` never connects (keeps `VMSyncRecord`);
    `MachinesPanelView` has no devices model; diagnostics views without the device section; tree "…" menu empty.
  - **Deferred to 9.12 (F):** the `CmuxSettingsUI` Devices pieces (`.computers` slot, `ComputersSection`,
    `ComputersSettingsRow`, `DevicesAccessToggleRow`, `ComputerAccessMenuItems`, `DeviceAccessControl`,
    `ComputersSettings*`, `HostSettingsActions+Computers`): `Sources/Cloud` tree files still use
    `DeviceAccessControl`/`ComputerAccessMenuItems`. The section is hidden since 9.1.
  - Checks: build, `--version`, `config doctor` (same as 9.11), `tree --all`, 388 methods (same as (C)); scratch
    workspace with a right split, `send`, read-screen, `surface.catalog`; closed after. ⬜ ⌘Q/reopen: manual.

**What it removes:** `Sources/Mobile/` (what's left after 9.5/9.6: pairing window, host service, Iroh/Irx runtime,
browser streaming, ~40 files), `Sources/Devices/` (53), `Sources/Hive/`, `MacPresenceDecisionCache.swift`,
`MacPresenceMonitor.swift`, `PIDPresence.swift` (check: is it used by agent liveness? keep if so),
`PortTerminalDeviceLookup.swift`, `MobileNotificationFeedWireItem.swift`, `Workspace+MobileAgentStatus.swift`,
`Workspace+DeviceLayout.swift`, `Workspace+DeviceMachineContext.swift`, and in `CmuxSettingsUI`: `MobileSection.swift`,
`DevicesAccessToggleRow.swift`, `IrohConnectionCheckCard.swift`, `IrohCustomRelayEditor.swift`,
`IrohNetworkingAttentionNote.swift`, `IrohNetworkingSection.swift`, the `.mobile`, `.computers`, `.networking` cases.
Also `Panels/MobilePairing*`. `PanelType.mobilePairing` stays.

**Risk:** medium. `MobileTerminalByteTee`, `MobileTerminalRenderObserver` and `MobileTerminalFramePacer` are hooked
into terminal output. Remove their hooks from `GhosttyTerminalView` / `TerminalController` in the same commit.

- ✅ Standard checks (build, `--version`, `config doctor`, `tree --all`). ⬜ ⌘Q/reopen, agents, Settings: manual.
- ✅ Run something chatty (`yes | head -100000`) and a full-screen app (`vim`): rendering is normal (read-screen).

### ⬜ 9.15 Delete the Cloud and Auth packages and Stack Auth (M, low risk)

**What it removes:** `Packages/macOS/CmuxCloud` (28,700 lines), `CmuxCloudBannerCore`, `CmuxCloudImagePaste`,
`CmuxCloudMachines`, `CmuxCloudResizeCore`, `CmuxCloudTui` (unless SSH-TUI stays), `CmuxCloudTunnelCore`,
`Packages/Shared/CMUXAuthCore`, `CmuxAuthRuntime`, `vendor/stack-auth-swift-sdk-prerelease`.

**Build edits:**
- pbxproj: 10 package references and their products from `cmux`, `cmuxTests` (and `cmux-cli` if anything is left).
- `cmux.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: remove `swift-crypto` and
  `swift-asn1` (only Stack Auth used them).

**Risk:** low once 9.12–9.13 build.

- ⬜ Standard checks. Stale-bundle check: no `swift-crypto_Crypto.bundle` in the app.
- ⬜ `grep -rlE "import (CmuxCloud|CMUXAuthCore|CmuxAuthRuntime|StackAuth)" Sources CLI Packages` → nothing.

### ⬜ 9.16 Delete the mobile, Iroh, Irx, Hive, presence and push packages (M, low–medium risk)

**What it removes:** `Packages/macOS/CmuxMobileHost` (or all of it except `AgentChat/` if you shrank it in 9.5),
`CmuxPhonePush`, `CmuxHive`, `Packages/Shared/CmuxIrohTransport` (30,400 lines), `CmuxIrxTransport` (13,900),
`CmuxWorkspacePresence`, `Packages/iOS/CmuxMobileRPC`, `CmuxMobileTransport`, `CmuxMobilePairedMac`,
`CmuxMobileShellModel`, `CmuxMobileSupport`, `CmuxMobileDiagnostics` (the whole `Packages/iOS/` folder once nothing
reaches it). The remote package `iroh-ffi` (`github.com/manaflow-ai/iroh-ffi`, product `IrohLib`).

**Check first:** walk every `Package.swift` `path:` dependency (as in Phase 4). `CMUXMobileCore`,
`CmuxTerminalSizing`, `CmuxTerminalSharing`, `CmuxAgentChat` must still be reachable and stay.

**Build edits:** pbxproj package refs and products (`IrohLib` appears twice, lines ~2440–2441), the
`XCRemoteSwiftPackageReference "iroh-ffi"` block; `Package.resolved`: remove `iroh-ffi`. A clean build no longer
downloads it.

**Risk:** low–medium. `IrohLib` is a binary; if a forgotten import remains, the link fails with a clear error.

- ⬜ Standard checks.
- ⬜ `rm -rf ~/Library/Developer/Xcode/DerivedData/cmux-test` once and do a clean `./scripts/test-app.sh --seed`
  (about 10 minutes). The log shows no `iroh-ffi`, `stack-auth`, `swift-crypto` fetch.

### ⬜ 9.17 Info.plist, build scripts, schema and docs (S–M, low risk)

**What it removes:** leftover build settings and keys.

**Edits:**
- `Resources/Info.plist`: remove `CMUX_IROH_V2_ENVIRONMENT`, `CMUX_IROH_V2_BASE_URL`, `CMUX_IROH_V2_FORCE_RELAY`
  (96–101), `CMUXIrohRelayPolicyKeyID`, `CMUXIrohRelayPolicyPublicKeyBase64`, `CMUXIrohRelayPolicyTrustKeys`
  (215–233), `NSSystemExtensionUsageDescription` (the Cloud network extension text, 139–140), the
  `com.cmux.cloud-sidebar-row` UTType (~347). **Keep** the `$(PRODUCT_BUNDLE_IDENTIFIER).auth` URL type with
  `$(CMUX_AUTH_CALLBACK_SCHEME)` (194–199): it's the app's own link scheme. Maybe add a comment saying so.
- pbxproj build settings (~19408–19463): remove `CMUX_IROH_RELAY_POLICY_*`; keep `CMUX_AUTH_CALLBACK_SCHEME`.
  Remove the unused `sentry-cocoa` package reference and its `Package.resolved` entry.
- `scripts/reload.sh`: the `CMUX_IROH_*` values (35–38, 1501–1517, 1589), their `set_plist_env` lines (~2054–2057),
  `CMUXCloudDogfoodEnabled` / `CMUX_DEV_CLOUD_ENABLED` (~2022–2027), `CMUX_VM_API_BASE_URL`, `--prod-auth` checks.
  Keep `CMUX_AUTH_CALLBACK_SCHEME`, socket, tag and CLI paths. Fork comments, as in Phase 1.
- `scripts/test-app.sh` 36, `scripts/install-personal.sh` 33: drop `CMUX_DEV_CLOUD_ENABLED=0` (and
  `CMUX_DEV_BACKEND_MODE=local` if reload.sh no longer reads it).
- `CmuxSettings`: the `cloud.beta.machines.enabled` key, `DevicesCatalogSection`, cloud/mobile `SettingCatalog`
  entries, `computerUse`-style leftovers. Schema (`CmuxConfigSchema.generated.swift`): the `cloud` object may go
  (your `cmux.json` has none). **Keep `chief`.**
- Docs: `removal-plan.md` (Phases 8, 9 ✅), `docs/overview.md`, `docs/architecture.md`, `docs/ideas.md`, README
  "What's different" row ("Builds without upstream's … team login or cmux-tui client" → "without Chief, Cloud,
  Account, Mobile and Iroh").

- ⬜ Standard checks. `plutil -lint Resources/Info.plist`. `config doctor` clean.
- ⬜ `strings "<test app>/Contents/MacOS/cmux DEV test" | grep -E "relay\.cmux\.dev|iroh\.link|stack-auth|api/client-config"` → nothing.

---

## Effort

| Steps | Size | Hours (incl. builds) |
|---|---|---|
| 8.1–8.4 Chief | S, M, M, S–M | ~10 |
| 9.0–9.3 baseline, hide, stop starts, CLI | S, M, S–M, M | ~10 |
| 9.4–9.6 moves (types, transcript registry, paste path) | M, M, M | ~10 |
| 9.7–9.11 stubs (sidebar, terminal, restore, composition, socket) | M, M–L, M, M–L, M | ~22 |
| 9.12–9.17 deletes and cleanup | M, S–M, M, M, M, S–M | ~16 |
| **Total** | | **~68 h, 9–10 working days** |

Roughly 270,000 lines leave the repo (packages ~190,000, app ~70,000, CLI ~11,000).

## The three biggest risks

1. **`cmux send --paste` runs through the mobile host.** `terminal.paste` is served by the MobileHost coordinator
   and `Sources/Mobile/MobileHostTerminalInputApplier.swift`. Deleting Mobile without step 9.6 breaks the cmux
   agent's multi-line `cmux_send`, and only that, so it's easy to miss.
2. **Local features live inside cloud and mobile code.** The agent transcript registry (resume after restart,
   Vault, search) is in `Sources/Mobile/AgentChat` + `CmuxMobileHost`; tab drag rules, current work and the file
   transfer policy are in `CmuxCloud`; the app's own link scheme is `AuthEnvironment.callbackScheme`. Steps 9.4–9.6
   move them first. Wrong order means sessions stop resuming or links stop working, not just compile errors.
3. **Startup and quit wiring.** `cmuxApp` builds the auth graph and passes it into `AppDelegate.configure`, and the
   quit path waits for the cloud notification store. A wrong cut in 9.2 / 9.10 stops the app from launching or from
   saving the layout on ⌘Q (which `install-personal.sh` relies on). Also: Settings opens on `.account` by default.

---

## Does keeping cmux Personal running make this harder?

Short answer: **no, with three small cautions.** The two apps have different bundle ids, sockets and saved
layouts. Personal runs the Nov 1 build and isn't touched until you install.

### What the two apps share

| Thing | Shared? | Does a step need care? |
|---|---|---|
| `~/.config/cmux/cmux.json` (and `sidebars/`, `.surface-resume-approval-secret`) | **Yes**, also with cmux and cmux NIGHTLY | Keep the `chief` schema key (8.2, 9.17). Don't add a step that writes new keys into `cmux.json`; the old Personal build would call them unknown. None of these steps do |
| `~/Library/Application Support/cmux/` | Folder shared, files mostly per bundle id: `session-<bundle>.json`, `agent-journal-<bundle>`, `notification-feed-history-<bundle>`, `closed-item-history-<bundle>`, `session-history/session-<bundle>-*` | `--seed` copies only Personal's `session-…mine.json` into the test app. Read-only for Personal. Fine |
| `…/cmux/terminal-history/surface-<id>.history`, `search.db` | **Yes**, keyed by surface id, not bundle | A seeded test app restores the same surface ids as Personal, so both apps' shells write the same history files. That's true today already; this plan doesn't change it |
| `…/cmux/mobile-host-device-id`, `mobileHost.deviceID` default | Leftovers | Harmless; delete by hand after the final install if you like |
| `~/.cmuxterm/` (`claude-hook-sessions.json`, `pi-hook-sessions.json`, `events.jsonl`, `workstream.jsonl`, `cmux-cli-shims/<surface-id>/`, `claude-settings/`) | **Yes**, all apps' hooks write here | None of these steps change those formats. Keep it that way. Same surface ids also share a shim folder (as today) |
| Sockets | No: `/tmp/cmux-debug-mine.sock` vs `/tmp/cmux-debug-test.sock`; `cmuxd-dev-<tag>.sock` | Never build with `--tag mine` |
| The NIGHTLY CLI (`/Applications/cmux NIGHTLY.app/…/bin/cmux`) | **Yes**: `cmux-tools.ts`, `pin-cmux-agent.sh`, `wipe-cmux-agent.sh` use it against whichever app the terminal runs in | The methods it calls must exist in both the old Personal and the new build. Steps 9.6 and 9.11 are the ones to watch (`terminal.paste`!). `pin-cmux-agent.sh` uses the app's own CLI for `set-agent-home`, so that keeps working |
| Keychain | Shared items: `com.cmuxterm.app.socket-control`, `com.cmuxterm.app.surface-resume-approvals`. Stack Auth tokens are per bundle id (`KeychainStackTokenStore.serviceName(bundleIdentifier:)`); you never signed in, so there are none | Nothing to do. Optional: after the final install, delete any `com.cmuxterm.app.auth*` items if Keychain Access shows them |
| UserDefaults | Per bundle id (`com.cmuxterm.app.debug.mine` vs `.debug.test`) | Settings you change in the test app don't reach Personal. Both have `chiefEnabled = 0` and no cloud keys |
| URL schemes | `cmux-dev-mine` vs `cmux-dev-test` | Keep the URL type (9.17). A workspace link opens in the app that made it |

### Does any step need care because of it?

- **Saved-layout compatibility when Personal gets the new build.** Safe. Personal's `session-…mine.json` has only
  terminal and browser panels, no Home group, no `chief` / `cloudVM` / `remote` fields, `version: 1`. The new build
  reads it the same (that's what `--seed` tests every step). Rolling back is also safe: the old build ignores fields
  it doesn't know, and the new build only removes optional fields. `install-personal.sh` backs up first.
- **The agent workspace after the install.** Personal's file has no `agentHomeCommand` yet (it's an older build).
  After the install, run `pin-cmux-agent.sh` once (palette: "cmux agent: open pinned workspace"). It sees
  `set-agent-home` in the new app CLI and sets it.
- **Install once, at the end.** Each step is checked in the test app; Personal gets everything in one
  `./scripts/install-personal.sh` after 9.17. Before that: finish or note running agent work (terminals restart),
  and after it do the stale-bundle check on `~/Applications/cmux Personal.app` (no `CmuxChief_*`, `CmuxMessagesLab_*`,
  `PostHog_*`, `swift-crypto_*` bundles). If something's wrong, restore from `personal-backups/<date>/`.
