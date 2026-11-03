# Removal plan: what's left from upstream

Written 2026-11-02, against `61dca2e`. Phases 1–7 were done on 2026-11-02 (`edbd4f6` … `7e6c136`), each built and
smoke-tested in the test app (`--version`, `tree --all`, `config doctor`). Not yet installed into cmux Personal.
Phases 0, 8 and 9 are still open.
Model for how to do a removal: `git show --stat 61dca2e` (Simulator, Computer Use, VPN, PostHog, Sentry).

✅ done · ⬜ open · Size: S = under an hour, M = a few hours, L = a day or more.

## Read this first

- **cmux Personal hasn't got the last removal yet.** The installed app (`~/Applications/cmux Personal.app`)
  was built on Nov 1, 22:30, before `61dca2e`. It still has `PostHog_PostHog.bundle` and
  `CmuxSimulator_CmuxSimulatorWorker.bundle` inside. So: install `61dca2e` first (Phase 0) and use it for a
  day before you remove anything more.
- **Your own scripts use the official NIGHTLY CLI, even when they talk to cmux Personal.**
  `cmux-tools.ts`, `pin-cmux-agent.sh` and `wipe-cmux-agent.sh` pick `/Applications/cmux NIGHTLY.app/.../bin/cmux`
  if it exists. That CLI then talks to whichever app the terminal runs in (from `CMUX_SOCKET_PATH`). So the
  socket methods those commands use must keep working **as upstream defines them**. Removing upstream-only
  features is fine. Renaming or removing a general socket method is not.
- **`~/.config/cmux/cmux.json` is shared by three apps** (cmux, cmux NIGHTLY, cmux Personal). Never remove a
  config key from the schema that the file uses. It has `"chief": { "enabled": false }`, so the `chief` key must
  stay in the schema even after Chief is gone (otherwise `cmux config doctor` reports "unknown configuration key").

## Order at a glance

| # | Phase | Size | Risk | Touches Swift? |
|---|---|---|---|---|
| 0 | Install what's already committed | S | none | no |
| ✅ 1 | CodeRouter download off in the build | S | very low | no |
| ✅ 2 | Sparkle feed off, then Sparkle gone | S, then M | low | yes |
| ✅ 3 | Remote feature-flag fetch off (found while checking) | S | low | yes, 1 guard |
| ✅ 4 | Delete packages nothing links | S | very low | no (only folders) |
| ✅ 5 | Leftovers from the last removal (`cmux vpn`, Computer Use bits) | S | low | yes |
| ✅ 6 | The 5 "Simulator: …" shortcuts and `simulator.*` stubs | M | low–medium | yes |
| ✅ 7 | Send Feedback | S–M | low | yes |
| ✅ 8 | Chief and Chief Home | M–L | medium | yes |
| ✅ 9 | Cloud, Auth, mobile pairing, cmux-tui / Machines, `cmux vm` | L (several commits) | high | yes |

Each phase is one commit, one test build, one reinstall. Never two phases in one build.

---

## Don't break what's running

Everything in this section stays. A removal that touches any of it is wrong.

### The shell integration (`Resources/shell-integration/`)

When cmux starts a terminal, it sets environment variables (`CMUX_SOCKET_PATH`, `CMUX_WORKSPACE_ID`,
`CMUX_SURFACE_ID`, `CMUX_PANEL_ID`, `CMUX_SHELL_INTEGRATION_DIR`, …) and makes the shell load one of these
files. They are how the sidebar knows each terminal's folder, git branch, PR, ports and whether something is
running.

| File | What it does, in plain words |
|---|---|
| `.zshenv` (hidden) | The first thing zsh runs. cmux points `ZDOTDIR` here, this file puts your real `ZDOTDIR` back right away (so your own `.zshrc` and history load as normal), then loads the cmux zsh script. |
| `cmux-zsh-integration.zsh` | The main zsh hook (2,480 lines). Before and after each command it tells the app: the current folder (`report_pwd`), the tty (`report_tty`), the git branch, the PR for that branch, "a command is running / idle" (`report_shell_state`), and asks the app to rescan ports (`ports_kick`). It also puts the per-terminal shim folder first on `PATH` (see below), restores scrollback once after a restart, and keeps tmux in sync. The `*_via_relay` functions do the same over SSH for remote shells. |
| `cmux-bash-bootstrap.bash` | macOS's old bash 3.2 can't use Ghostty's bash hook, so cmux runs this once on the first prompt. It loads the bash script and leaves other prompt hooks (e.g. starship) alone. |
| `cmux-bash-integration.bash` | The bash version of the zsh script. |
| `fish/config.fish`, `nushell/*.nu` | The same for fish and nushell. |

You use zsh, so the zsh files matter most, but keep all of them. Also keep `Resources/ghostty/` (terminfo and
themes) and `Resources/terminfo-overlay/`.

### The agent wrappers and CLI shims (`Resources/bin/`, `~/.cmuxterm/cmux-cli-shims/`)

For every terminal, the app writes a private folder `~/.cmuxterm/cmux-cli-shims/<surface-id>/` with tiny
scripts named `claude`, `codex`, `pi`, `amp`, `hermes`, `agy`, and puts it first on `PATH`. So when you type
`claude` or `pi`, the shim runs first and hands over to the matching wrapper in the app bundle. The wrapper then
starts the real program.

| Wrapper | What it does |
|---|---|
| `cmux-claude-wrapper` | Adds `--session-id` and a settings file with hooks, so Claude Code reports back (`cmux hooks claude …`, `cmux hooks feed`). That's where the sidebar `run` / `wait` / `idle`, notifications and "resume after restart" for Claude come from. Outside cmux it just runs the real `claude`. |
| `cmux-pi-wrapper` | Loads cmux's Pi extension (posts the latest message and status to the sidebar), unless you already have a cmux-managed one or pass `--no-extensions`. |
| `cmux-codex-wrapper`, `cmux-amp-wrapper`, `cmux-hermes-*`, `agy`, `grok`, `muse` | The same idea for other agents. |
| `open` | `open https://…` inside cmux opens the page in cmux's browser; everything else goes to `/usr/bin/open`. |
| `cmux-sudo` | Small entry point for the sudo helper (Touch ID prompts). |
| `cmux-tmux-agent.py` | Agent hooks for tmux sessions over SSH. |
| `start-cmux-profiling`, `submit-cmux-profile` | Records an Instruments profile and drafts an email to the cmux founders. Upstream support tool; harmless, could go later. |

Your `cmux-agent.sh` strips `cmux-cli-shims` from `PATH` on purpose, to run the real `pi`. So the folder name
`cmux-cli-shims` must stay.

`Resources/bin/` in the built app also holds the `cmux` CLI, `ghostty`, `cmux-diff-sidecar`,
`cmux-paste-text-worker` and links to the package resource bundles (`*.bundle`). The CLI crashes at launch if a
bundle it needs is missing. The CLI links: CmuxAgentDeliveryCore, CmuxAgentJournal, CMUXAgentLaunch,
CmuxCloudResizeCore, CmuxControlSocket, CmuxCore, CMUXDebugLog, CmuxFoundation, CmuxSettings, CmuxSudoBroker,
CmuxSurfaceCatalogModel, CmuxTerminalCore, CmuxTerminalImport. Note `CmuxCloudResizeCore` is in that list: it
must be unlinked from the CLI before it can be deleted (Phase 9).

### The CLI commands and socket methods your setup uses

From `~/Code/cmux-config` (`scripts/`, `zsh/cmux.zsh`, `.pi/extensions/cmux-tools.ts`, `cmux/cmux.json`) and the
`pi-cmux` package your Pi loads (`~/.pi/agent/settings.json`):

| Used by | Commands |
|---|---|
| `cmux-tools.ts` (the cmux agent) | `identify`, `tree --all`, `top --all --format tsv`, `workspace list`, `workspace-group list / create / add`, `list-notifications`, `read-screen`, `vault sessions`, `vault search`, `new-workspace`, `rename-workspace`, `workspace-action` (pin, move-top, set-color, …), `agent message`, `send`, `send-key`, `close-workspace`, `config get / set / unset / preset` |
| `pin-cmux-agent.sh`, `wipe-cmux-agent.sh` | `tree`, `identify`, `new-workspace --command`, `send`, `workspace-action` (pin, clear-description, move-top, set-color), `clear-status`, `clear-log`, `clear-notifications`, `select-workspace`, `workspace select`, `close-surface` |
| `check.sh`, `refresh-docs.sh` | `config doctor`, `reload-config`, `--skill`, `docs <topic>`, `help <topic>`, `<command> --help`, `--version` |
| `cmux-browser.ts` (`~/.pi/agent/extensions`) | `browser …` |
| `pi-cmux` | `identify`, `list-panes`, `new-split`, `new-surface`, `respawn-pane`, `rename-tab`, `set-status`, `clear-status`, `set-progress`, `clear-progress`, `log`, `notify`, `trigger-flash` |
| `cmux.json` | the `commands` entry that runs `pin-cmux-agent.sh` from the command palette |

The socket methods behind them include `system.identify`, `system.tree`, `system.top`, `window.list`,
`workspace.list / create / select / rename / close / action / current`, `workspace.group.*`, `pane.list`,
`surface.list / split / create / new_terminal / respawn / send_text / send_key / read_text / close / focus`,
`notification.*`, `workspace.status.*`, `agent.message.*`, `vault.sessions / search / checkpoints / checkpoint / fork`,
`browser.*`, plus the old one-line commands the shell sends (`report_pwd`, `report_tty`, `report_shell_state`,
`report_git_branch`, `clear_git_branch`, `report_pr`, `clear_pr`, `ports_kick`).

**Don't touch:** these commands, these methods, `Sources/TerminalController.swift`'s routing for them,
`Sources/TerminalController+VaultCommands.swift` and `CmuxAgentSessionStore` (Vault is local, not cloud),
`AgentMessageCenter`, and the `hooks` commands the wrappers call.

`TerminalController.swift` imports `CmuxCloud`, `CmuxMobileHost`, `CmuxRemoteSession`, `CmuxAuthRuntime` and
`CmuxFeedback`. When those go, edit the imports and the cases for their own methods only.

### The saved layout (session restore)

- File: `~/Library/Application Support/cmux/session-com.cmuxterm.app.debug.mine.json` (+ `-previous.json`,
  `-scrollback`), written by `Sources/SessionPersistence.swift`, format `version: 1`.
- Today it holds panel types `terminal`, `browser` and `markdown`, splits, workspace groups (`workspaceGroups`,
  `externalID`, anchors), pins, colours, unread marks, agent resume bindings (`resumeBinding`, `agent`,
  `launchCommand`). No `chief`, `simulator`, `cloudVM` or `remote` data.
- Also restored from the same folder: `agent-journal-*.sqlite3`, `notification-feed-history-*`,
  `closed-item-history-*`, `search.db`, `session-history/`, `terminal-history/`.

**Rules for every phase:**

1. Don't change `SessionPersistence.currentVersion`.
2. Optional fields (`simulator`, `chief`, `cloudVM`, `remote`, `coderouterGuide`, …) can be removed: the JSON
   decoder ignores keys it doesn't know.
3. **Don't remove cases from `PanelType`** (`Sources/Panels/Panel.swift`) or other enums stored in the file
   unless the decoder falls back for unknown values. A stored value the app no longer knows can make the whole
   workspace fail to load. Keep `.chief`, `.simulator` etc. as cases that restore as nothing.
4. Test with `./scripts/test-app.sh --seed`, which copies your real layout into the test app.
5. `install-personal.sh` backs up the layout to `personal-backups/<date>/` before it replaces the app.

### Settings file and shortcuts

Keep these schema keys (`CmuxConfigSchema.generated.swift`): `schemaVersion`, `app`, `browser`, `sidebar`,
`sidebarAppearance`, `automation`, `customSidebars`, `settingPresets`, `chief`, `shortcuts`, `commands`, and the
shortcut names you bind (`reopenPreviousSession`, `openFolder`, `focusSidebar`, `focusUp`, `focusDown`,
`prevSurface`, `nextSurface`). Removing *unused* names (like `simulatorHome`) is fine.

### The build (`scripts/`)

`install-personal.sh` and `test-app.sh` both run `reload.sh --tag <tag> --no-global-cli-links` (since Phase 9.17
without `CMUX_DEV_BACKEND_MODE=local CMUX_DEV_CLOUD_ENABLED=0`: `reload.sh` no longer reads either). In order, `reload.sh`:

1. Checks the tools (Xcode, Metal, Zig) and skips the cmux-tui client (fork change).
2. `ensure-ghosttykit.sh`: downloads the prebuilt Ghostty terminal engine (checksum-checked). **Keep.**
3. Runs `xcodebuild`. Its build phases: Write Extension Point (sidebar extensions), Build Command Palette Nucleo
   FFI (Rust fuzzy search for ⌘P, `Native/CommandPaletteNucleoFFI`), Build Diff Sidecar (Rust diff viewer helper),
   `build-app-bundled-resources.sh` (copies shell integration, wrappers, sidebars into the app and links the
   `*.bundle` resources next to the CLI), Compress Markdown Viewer Assets, Build Plain Text Paste Worker, Copy CLI
   (also copies `setup-pam-tid.sh`, the Touch-ID-for-sudo helper). **Keep all of these.**
4. `build-ghostty-cli-helper.sh`: builds the `ghostty` helper with Zig. **Keep.**
5. Skips `cmuxd` (no `cmuxd/` folder here) and cmux-tui.
6. ~~`install-coderouter-client.sh`: downloads CodeRouter.~~ Call commented out in Phase 1, script deleted in `ccd7f4f`.
7. Re-links resource bundles, signs the app ad hoc, opens it.

The other ~250 files in `scripts/` are upstream CI, release, iOS and test tools that nothing in your build calls.

---

## Phase 0: install what's already committed (S)

`61dca2e` removed Simulator panes, Computer Use, the VPN tunnel, PostHog and Sentry, but only the test app has
it. Install it and use it for a day.

- ⬜ `./scripts/test-app.sh --seed`, check, then `./scripts/install-personal.sh`.
- ⬜ After install, `ls ~/Applications/cmux\ Personal.app/Contents/Resources/bin` has no `PostHog_PostHog.bundle`
  or `CmuxSimulator_*` link any more. If they're still there, `install-personal.sh` copied over an old bundle.

## ✅ Phase 1: CodeRouter download off (S, very low risk)

**What it is:** CodeRouter is a separate command-line tool from the cmux team (`cmux coderouter` / `cmux cr`).
Every build downloads it (`coderouter-darwin-arm64`, v0.3.16) from `manaflow-ai/coderouter-releases` on GitHub
into `Contents/Resources/bin/coderouter`. Nothing in your setup uses it.

**Where:** `scripts/install-coderouter-client.sh`, called once at `scripts/reload.sh:2142`.
`Resources/coderouter-cli.json` (version pin). In the app: `CLI/CMUXCLI+Coderouter.swift`,
`CLI/CMUXCLI+CoderouterPassthrough.swift`, a "CodeRouter guide" panel (`coderouterGuide` in the session file).

**Tangle:** the build step is 1 line. The app side is 54 files in `Sources`/`CLI` and 18 in packages that
mention it.

**Plan:**
1. Skip the call in `reload.sh` (a fork comment like the cmux-tui one, or `CMUX_SKIP_CODEROUTER=1` set by both
   wrapper scripts). Leave the app code alone. `cmux cr` then says it isn't installed.
2. ✅ Later, optional: remove the CLI commands and the guide panel (`ccd7f4f`). Keep `coderouterGuide` decodable or just drop the
   optional field (rule 2 above).

**Risk:** none for the running setup. An incremental build keeps the old `coderouter` binary in the app; that's
harmless. A clean build won't have it.

**Done in `edbd4f6`:** step 1 only (the call in `reload.sh` is commented out with a fork note).

**Step 2 done in `ccd7f4f`:** `CLI/CMUXCLI+Coderouter*.swift`, `CoderouterCommand` (`coderouter` / `cr`) and its
dispatch and help lines, the CLI's CodeRouter handoff/exec/capability-probe code and the `SocketClient`
arm-server identity checks in `CLI/cmux.swift`; the guide pane (`CoderouterGuidePanel`,
`Workspace+CoderouterGuidePane.swift`, `CoderouterGuidePanelView`, the `coderouterGuide` session field and the
"open as pane" action); `Resources/coderouter-cli.json`, `scripts/install-coderouter-client.sh` and the
commented-out call in `reload.sh`. `PanelType.coderouterGuide` stays and restores as nothing (rule 3).
`cmux coderouter` / `cmux cr` now say "Unknown command".
Left for Phase 9 (woven into Cloud): the Cloud sidebar's CodeRouter section and its "?" guide popover
(`Sources/Cloud/Coderouter*.swift`, `CodeRouter*.swift`, `CloudTree*`), `CoderouterAccountStore` in
`TabManager`, the `coderouter.*` socket methods, `CmuxCloud/Accounts/CoderouterClient.swift`, the
`CodeRouter*` types in `CmuxControlSocket` (also used by the app's handoff server), `SurfaceKind.coderouterGuide`,
the `cli.coderouter.*` / `coderouter.guide.*` strings in `Localizable.xcstrings`, and the CodeRouter section of
`Resources/en.lproj/cloud-agent-skill.md`. Dangling pbxproj refs to the already-deleted
`CLICoderouter*Tests.swift` test files were left as they were.

- ✅ Build; the log no longer shows a CodeRouter download, and `Resources/bin/coderouter` is gone from the built app.
- ⬜ Open the test app; a zsh terminal shows the folder and git branch in the sidebar (check by hand).
- ✅ The shims start `claude` and `pi` (`--version` through the shim folder). ⬜ `run` / `wait` / `idle` in the sidebar (check by hand).
- ⬜ `scripts/install-personal.sh`.

## ✅ Phase 2: Sparkle update feed (S first, then M)

**What it is:** the auto-updater. It reads upstream's feed
(`SUFeedURL = https://github.com/manaflow-ai/cmux/releases/latest/download/appcast.xml`) and can offer to install
the official cmux over cmux Personal. Today it stays quiet only because the bundle id looks like a dev build.

**Where:**
- `Resources/Info.plist`: `SUAutomaticallyUpdate`, `SUEnableAutomaticChecks` (true), `SUFeedURL`,
  `SUPublicEDKey` (`$(SPARKLE_PUBLIC_KEY)`).
- Packages `CmuxUpdater` (28 files, ~3,650 lines) and `CmuxUpdaterUI` (10 files, ~1,160 lines). `Sparkle` is a
  remote Swift package (`cmux.xcodeproj` + `Package.resolved`).
- App: `AppDelegate.swift` (`updateController`, `checkForUpdates`, relaunch handling around 1367 and 2110),
  `cmuxApp.swift` (menu "Check for Updates…", `InstallUpdateMenuItem`, debug update errors), `ContentView.swift`
  (~30 lines: `updateViewModel` passed through the sidebar footer, `UpdatePill`, palette command
  `palette.checkForUpdates`), `App/CmuxHelpCommands.swift`, `App/MenuBarExtraController.swift`,
  `HostSettingsActions.swift`, `VerticalTabsSidebar+EmptyAreasAndFooter.swift`, `Update/UpdateLogStore.swift`,
  `Update/UpdateTitlebarAccessory.swift`, managed policy key in `CmuxSettings`. No Settings section of its own.

**Tangle:** 9 app files import it, about 65 lines. The `updateViewModel` is threaded through several sidebar
views, which is the fiddly part.

**Plan:**
1. Step A (S): remove the four `SU*` keys from `Info.plist` and don't call `startUpdaterIfNeeded()`. Hide the
   menu items and the palette command. Nothing else moves.
2. Step B (M, separate commit): delete `CmuxUpdater`, `CmuxUpdaterUI`, the Sparkle package, the update pill and
   `Sources/Update/Update*.swift`. Keep the rest of `Sources/Update/` (notification popover, titlebar
   buttons: they're not about updates, despite the folder name).

**Risk:** low. The only real trap is the quit path: `AppDelegate` has Sparkle-specific relaunch handling. Make sure
⌘Q still saves the layout (that's what `install-personal.sh` relies on).

**Done in `883957f` (step A) and `032f629` (step B).** A: all six `SU*` keys gone from `Info.plist`, updater
never started, "Check for Updates…" removed from the app menu, Help menu, menu bar extra, sidebar help popover and
⌘⇧P (also "Apply Update" / "Attempt Update"). B: `CmuxUpdater`, `CmuxUpdaterUI` and the Sparkle package deleted
(pbxproj + `Package.resolved`); `updateViewModel` no longer threaded through the sidebar; update pill, debug
"Update Pill" menu and the relaunch-for-update quit path removed. Kept: `Sources/Update/UpdateTitlebarAccessory.swift`
(despite its name it is the titlebar controls and notifications popover, not Sparkle) and `UpdateLogStore.swift`
(a file logger the titlebar and UI-test code still write to; its `UpdateLogging` conformance is gone). The managed
policy key `DisableAutoUpdate` in `CmuxSettings` is left (harmless). `scripts/ci/package-test-lane.sh` still names
the two packages (upstream CI, not used).

- ✅ No "Check for Updates" in code for the app menu, menu bar extra, Help menu, sidebar help or ⌘⇧P. ⬜ Look once by hand.
- ✅ Quit (AppleScript quit) and reopen the test app: workspaces come back, "cmux" first and pinned.
- ⬜ Shells and agents in the test app work (folder, branch, `run`/`wait`) (check by hand).
- ⬜ `scripts/install-personal.sh`.

## ✅ Phase 3: remote feature flags off (S, found while checking)

**What it is:** at launch and every 30 minutes the app POSTs to `https://cmux.com/api/client-config` with an
anonymous install id, to fetch upstream's feature switches (`Sources/FeatureFlags.swift`, started at
`AppDelegate.swift:1820`). Only the MDM policy `DisableTelemetry` or UI-test mode stops it. This is data leaving the
machine that the earlier telemetry removal didn't catch.

**Plan:** don't call `CmuxFeatureFlags.shared.start()` (or make `refreshRemoteFlags` return early). Flags then use
their built-in defaults, which is what the code already does when the fetch fails.

**Confidence:** high that it's upstream-only. Check once that no flag you rely on is on only remotely: compare
Settings → Beta Features before and after.

**Done in `7cef649`:** `CmuxFeatureFlags.shared.start()` is no longer called (fork comment in `AppDelegate`).
Flags resolve from local overrides, the last cached remote value and the built-in defaults. Before the change, the
test app's only cached remote value was `sidebar-appkit-list-experiment = true`, which equals its default, so no
switch changes. (The cache stays authoritative and is never refreshed again; that is fine.)

- ✅ No open network connections from the test app after launch (`lsof -i -p <pid>`; short-lived ones would need
  Little Snitch or `nettop` to rule out).
- ⬜ Beta Features shows the same switches as before (check by hand). Shells and agents work.
- ⬜ `scripts/install-personal.sh`.

## ✅ Phase 4: delete packages nothing links (S, very low risk)

These folders are in `Packages/` but the Xcode project doesn't use them, directly or through another package. They
only add noise to searches.

- `Packages/iOS/*`, **except** `CmuxMobileRPC`, `CmuxMobileTransport` (linked by the app) and what they need:
  `CmuxMobileDiagnostics`, `CmuxMobileShellModel`, `CmuxMobileSupport`.
- `Packages/Shared/`: `CmuxAPIClient`, `CmuxClientConfig`, `CmuxSyncStore`, `CmuxTerminalClient`,
  `CmuxSentryTelemetry`, `CmuxSimulatorStreamKit`.
- `Packages/macOS/CmuxLiveEval`.
- Also `Packages/iOS/AGENTS.md`, `CLAUDE.md`.

Do **not** delete `CMUXMobileCore` (despite the name it is shared core code used by CmuxGit, CmuxTerminal,
CmuxSettingsUI and ~30 others), `CmuxAgentChat`, `CmuxTerminalPrediction` or `CmuxGhosttyKit`.

**Plan:** delete the folders, run a clean test build. If it fails, the error names the package to put back.

**Done in `190efab`:** 21 `Packages/iOS/*` folders (all except `CmuxMobileDiagnostics`, `CmuxMobilePairedMac`,
`CmuxMobileRPC`, `CmuxMobileShellModel`, `CmuxMobileSupport`, `CmuxMobileTransport`, which the app reaches),
`Packages/iOS/AGENTS.md` and `CLAUDE.md`, the six `Packages/Shared/` packages listed above and
`Packages/macOS/CmuxLiveEval`. Checked first with a script that walks the pbxproj package references and every
`Package.swift` `path:` dependency: exactly these were unreachable. Built incrementally (not from a clean
DerivedData); SwiftPM re-resolves the local package graph on every build, so a missing package would have failed.

- ✅ Builds; the test app opens; `--version`, `tree`, `config doctor` unchanged. ⬜ Shells and agents (by hand).
- ⬜ `scripts/install-personal.sh`.

## ✅ Phase 5: leftovers from the last removal (S, low risk)

- `cmux vpn` is still in the CLI: `CLI/CMUXCLI+VPN.swift`, `CLI/CMUXCLI+VPNAppManaged.swift` (the tunnel it
  controls is gone).
- Computer Use bits still in Settings: `CmuxSettingsUI/Sections/ComputerUseSettingsSnapshot.swift`,
  `ComputerUseSetupStatus.swift`, `Environment/SettingsHostActions+ComputerUse.swift`, and the
  `computerUseSettingFileURL` parameter in `CmuxTerminal/Spawn/TerminalSurface+AgentCommandShims.swift`
  (careful: this file writes the agent shims; remove only the parameter).
- `Resources/ComputerUseHelper.icon`.
- Data folder `~/Library/Application Support/cmux/cmux-cua` (not part of the repo; leave it, or delete by hand).

**Done in `45ec320`:** `CLI/CMUXCLI+VPN*.swift`, `VPNCommand` and its help text; the three Computer Use files in
`CmuxSettingsUI` and the matching `SettingsHostActions` requirements; the `computerUseSettingFileURL` parameter and
the dead `cmux_computer_use_*` lines it fed in the generated shim script (they set a shell variable nothing read);
`Resources/ComputerUseHelper.icon`. Not touched: the Cloud guide text that mentions `cmux vpn` (Phase 9), the
`computerUse` settings keys in `CmuxSettings`, and the `cmux-cua` MCP injection inside
`Resources/bin/cmux-claude-wrapper` (it finds no helper and skips; wrappers were out of scope).

**Later, in `ae3f768`:** the `cmux-cua` block in `Resources/bin/cmux-claude-wrapper` is gone (MCP config builder,
client and skill-link policy loaders, the managed-policy `disableSideloadFlags` probe that only gated it, skill
reconcile, the `--mcp-config` injection and the `CMUX_CUA_SOCKET_AUTH_TOKEN` unsets). `bash -n` / `zsh -n` pass;
`claude --version` and a hooked launch through the shim still work, with no `--mcp-config` added.
Still there: the same kind of block in `Resources/bin/cmux-codex-wrapper` (`cmux_computer_use_*`,
`mcp_servers.cmux-cua.*`), `scripts/strip-cmux-cua-rpaths.sh` and the `cmux-cua` steps in signing/CI scripts,
`ContentView+ComputerUseCommandPalette.swift`, and `CMUX_COMPUTER_USE_APP_ENABLED` in `CmuxTerminal`.

- ✅ `cmux vpn` says unknown command; new terminals get the shims (`agy amp claude codex hermes pi`), `claude
  --version` and `pi --version` run through them.
- ⬜ `scripts/install-personal.sh`.

## ✅ Phase 6: Simulator shortcuts and `simulator.*` stubs (M, low–medium risk)

**What it is:** five shortcuts that do nothing (Simulator: Home, Rotate Left, Rotate Right, Toggle Appearance,
Toggle Software Keyboard) in Settings → Keyboard Shortcuts, and socket methods `simulator.*` that answer
"unavailable".

**Where:**
- Shortcuts: `ShortcutAction` and its `+Defaults`, `+DisplayName`, `+Group`, `+PriorityRouting` in
  `Packages/macOS/CmuxSettings` (5 cases); `Sources/SimulatorCommandPaletteIntegration.swift`,
  `AppDelegate+SimulatorShortcutRouting.swift`, `AppDelegate+DockShortcutRouting.swift`,
  `KeyboardShortcutSettings.swift`, `KeyboardShortcutActionContext.swift`, `KeyboardShortcutContext.swift`,
  `CmuxSettingsUI/Bindings/ShortcutListModel.swift`; the shortcut names in `CmuxConfigSchema.generated.swift`.
- Also `.newSimulator` in the new-workspace menu and the tab-bar "+" actions
  (`AppDelegate+NewWorkspaceContextMenu.swift`, `CmuxSurfaceTabBarBuiltInAction.swift`, `Workspace.swift`).
- Socket stubs: `Packages/macOS/CmuxControlSocket/.../Coordinator/Simulator/` (~25 files),
  `Wire/ControlCommandExecutionPolicy+Simulator.swift`, the `simulator.*` cases in
  `ControlCommandCoordinator.swift`, `Sources/TerminalController+ControlSimulatorContext.swift`.
- Session: `Sources/Workspace+SimulatorSessionPersistence.swift`, `SessionSimulatorPanelSnapshot`.

**Tangle:** "simulator" appears in 129 non-test Swift files, but most are in the mobile/Iroh code (Phase 9).
For this phase: about 12 files for the shortcuts, about 30 for the socket stubs.

**Risk:**
- `CmuxSettings` and `CmuxControlSocket` are linked by the CLI too, so the CLI must build. Check
  `cmux --version` from the built app.
- Keep the `.simulator` value in `PanelType` and any stored enum (rule 3).
- After this, an old NIGHTLY CLI calling `simulator.*` gets "unknown method" instead of "unavailable". You don't
  call it, so that's fine.

**Done in `b9f12ee`:** the five `simulator*` cases in `ShortcutAction` and `KeyboardShortcutSettings.Action` and
every switch arm, their names in `CmuxConfigSchema.generated.swift`; `.newSimulator` in
`CmuxSurfaceTabBarBuiltInAction` (tab-bar "+", new-workspace menu) and the "New Simulator Pane" palette command
(`SimulatorCommandPaletteIntegration.swift` deleted); `Coordinator/Simulator/` (25 files),
`ControlCommandExecutionPolicy+Simulator.swift`, the `simulator.*` routing and `ControlSimulatorContext`
(`TerminalController+ControlSimulatorContext.swift` deleted); the optional `simulator` field in
`SessionPanelSnapshot` and `Workspace+SimulatorSessionPersistence.swift`. Kept: `PanelType.simulator` (rule 3), the
`simulatorFocus` shortcut-context atom and `.simulatorPanel` context (other shortcuts use them in "not focused"
clauses), `isSimulatorEnabled` / the flag definition, the `simulator_*` fields in `surface.list` output, and
`AppDelegate+SimulatorShortcutRouting.swift` (only its Simulator line went; the rest is the general
`isMenuBackedShortcutAction`).

- ✅ `cmux rpc simulator.context` → "Unknown method". ⬜ Settings → Keyboard Shortcuts has no "Simulator:" rows;
  ⌘O, ⌥⌘↑/↓ still work (check by hand).
- ✅ `"<test app>/Contents/Resources/bin/cmux" --version` works; `cmux config doctor` unchanged (clean).
- ⬜ Shells and agents in the test app work (by hand). `scripts/install-personal.sh`.

## ✅ Phase 7: Send Feedback (S–M, low risk)

**What it is:** a feedback form (sidebar footer button and Help menu) that uploads to
`https://cmux.com/api/feedback`. Package `CmuxFeedback` (~1,690 lines), 7 app files, e.g.
`TerminalController.swift` (import), the sidebar footer (`onSendFeedback`).

**Confidence:** high that you don't need it.

**Done in `7e6c136`:** the `CmuxFeedback` package (pbxproj), the composer sheet and its notification, "Send
Feedback" in the Help menu and the sidebar help popover (the footer itself has no separate button), the
`sendFeedback` shortcut (both enums, schema name), the "Send Feedback" button on the Cloud VM loading-failed panel,
`cmux feedback`, and the socket methods `feedback.open` / `feedback.submit`. `dogfood.feedback.submit` (a mobile
data-plane verb that only ever accepted `@manaflow.ai` accounts) now always answers "unauthorized", as it did for
you before; it goes with Phase 9. The profiling window keeps its saved email under the same defaults key. Kept:
`SettingsHostActions.sendFeedback()` (opens GitHub issues; nothing in Settings calls it).

- ✅ `cmux feedback` → unknown command; `feedback.open` → unknown method. ⬜ The help popover has no "Send Feedback"
  and nothing else in the footer moved (check by hand).
- ⬜ Shells and agents work. `scripts/install-personal.sh`.

## ✅ Phase 8: Chief and Chief Home (M–L, medium risk)

**Done** in four steps, see [chief-cloud-removal-plan.md](chief-cloud-removal-plan.md) Phase 8: Chief off for good
(`bf3a1d0`), commands, socket methods, Settings card and shortcut (`945611c`), Chief panes, Home navigation,
sidebar rows, drag-and-drop and `Sources/Chief/` (`7159ca8`), then the packages `CmuxChief`, `CmuxHomeCore`,
`CmuxHomeRender`, `CmuxMessagesLab`, `CmuxAgentQuestion` (Phase 8.4 commit). Kept: the `chief` config key and
`chief.*` settings parsing, `PanelType.chief`, `SurfaceKind.chief`, `DockSurfaceKind.chief` (all restore or create
nothing), `ChiefSettingsBridge.swift`, the agent home code.

**What it is:** Chief is upstream's built-in "manager" agent with its own pane, memory and a "Home" group
(`cmux.chief.home`) that can't be unpinned or deleted. You replaced it with the pinned cmux agent and have
`chief.enabled: false`. Home is the chat screen behind it (`CmuxHomeCore`, `CmuxHomeRender`, `CmuxMessagesLab`).

**Where:**
- `Packages/macOS/CmuxChief` (~8,100 lines), `Packages/Shared/CmuxHomeCore` (~6,300), `CmuxHomeRender` (~5,500),
  `CmuxMessagesLab` (~37,000, linked as `MessagesLabHome` and `MessagesLabSidebar`).
- `Sources/Chief/` (35 files), `AppDelegate+Chief.swift`, `ChiefHomeNavigation.swift`, `ChiefSettingsBridge.swift`,
  `DockSplitStore+ChiefPane.swift`, `TerminalController+Chief.swift`, `Workspace+ChiefPane.swift`,
  `CLI/CMUXCLI+Chief.swift`, `CLI/CMUXCLI+ChiefDispatch.swift`, `CLI/ChiefDispatchPlan.swift`,
  `CmuxSettingsUI/Sections/ChiefSettingsCard.swift`.
- `isChiefHome` / `isChiefHomeGroup`: 18 uses in `TabManager.swift`, `Workspace.swift`,
  `SidebarWorkspaceGroupDialogs.swift`, `VerticalTabsSidebar+WorkspaceGroups.swift`, `ChiefHomeNavigation.swift`.

**Tangle:** "chief" appears in 113 app files (~2,000 lines). 17 files import `CmuxChief`, 25 import `CmuxHomeCore`.

**Plan:** do `plan.md` Phase 2 first (Home group dropped on restore, `isChiefHome` false when Chief is off;
another agent may be working on this now: `TabManager.swift`, `Workspace.swift`, `SessionPersistence.swift`
have uncommitted changes). Then:
1. Make `isChiefHome` always false and remove the group guards in `TabManager`.
2. Remove the Chief menu items, Settings card, palette entries and the CLI `chief` commands.
3. Delete the packages and `Sources/Chief/`.

**Must keep:** the `chief` key in the config schema (accept and ignore it); `PanelType.chief`; the
`agent message` command and `agent.message.*` methods (they're separate from Chief and your cmux agent uses them).

- ✅ `scripts/test-app.sh --seed`; no Home group; all workspaces come back (checked with `tree --all`). ⬜ The
  pinned cmux row and unpinning/deleting a group (check by hand).
- ⬜ The pinned cmux agent restarts after an app restart (`zsh/cmux.zsh` → `cmux-agent.sh`) and can message an
  agent (`cmux_message_agent`).
- ✅ `cmux config doctor` is clean with `"chief": {"enabled": false}` still in `cmux.json`.
- ⬜ `scripts/install-personal.sh`.

## ✅ Phase 9: Cloud, Auth, mobile pairing, cmux-tui / Machines, `cmux vm` (L, high risk; several commits)

**Done** in steps 9.0–9.17 of [chief-cloud-removal-plan.md](chief-cloud-removal-plan.md) (see its "Done:" notes and
`git log`): entry points hidden, nothing cloud starts at launch, the cloud CLI commands and socket methods gone,
the local pieces (current work, surface move rules, managed policies, the app link scheme, the agent transcript
registry, `terminal.paste` / `terminal.input`) moved out first, then `Sources/Cloud`, `Mobile`, `Devices`, `Hive`,
`Auth`, `RemoteTui`, the cmux-tui provider and the packages (`CmuxCloud*`, `CMUXAuthCore`, `CmuxAuthRuntime`, Stack
Auth, `CmuxPhonePush`, `CmuxHive`, `CmuxIrohTransport`, `CmuxIrxTransport`, `CmuxWorkspacePresence`,
`Packages/iOS`, `iroh-ffi`) deleted. 9.17 cleaned `Info.plist`, the pbxproj build settings, `reload.sh` and the
cloud settings keys. Kept: `CmuxMobileHost` (the browser JS dialog broker lives there), `CMUXMobileCore`,
`CmuxAgentChat`, `CmuxTerminalSharing`, `CmuxSSHClipboardTrust`, remote SSH / remote tmux, the
`$(PRODUCT_BUNDLE_IDENTIFIER).auth` URL type and `CMUX_AUTH_CALLBACK_SCHEME` (the app's own link scheme), and the
stored enum cases (`PanelType`, `SettingsSectionID`, `RightSidebarMode.machines`). Not installed into cmux
Personal yet.

**What it is:** everything that talks to upstream's servers: cloud machines (VMs you rent from cmux), the Machines
panel and cmux-tui client, team sign-in (Stack Auth), the "Cloud" welcome screens, pairing an iPhone with the
Mac over Iroh relays (`*.relay.cmux.dev`, `*.cmux.iroh.link`), push to the phone, the Devices panel.

**Where (packages):** `CmuxCloud` (~28,700 lines), `CmuxCloudBannerCore`, `CmuxCloudImagePaste`,
`CmuxCloudMachines`, `CmuxCloudResizeCore`, `CmuxCloudTui`, `CmuxCloudTunnelCore`, `CMUXAuthCore`,
`CmuxAuthRuntime` (~8,800), `vendor/stack-auth-swift-sdk-prerelease`, `CmuxMobileHost`, `CmuxPhonePush`,
`CmuxHive` (Devices), `CmuxIrohTransport` (~30,400), `CmuxIrxTransport` (~13,900), `CmuxWorkspacePresence`,
`CmuxMobileRPC`, `CmuxMobileTransport`.

**Where (app):** `Sources/Cloud/` (204 files), `Sources/Mobile/` (40), `Sources/Auth/` (18),
`Sources/Devices/` (48), `Sources/RemoteTui/` (15), `AppDelegate+Cloud*.swift`, `cmuxApp+Cloud*.swift`,
`TerminalController+Mobile*.swift` (~20), `TerminalController+AuthTeam.swift`, `PricingPlansScreen.swift`,
`Resources/CloudWelcome/*.mp4`. CLI: `CLI/Commands/VMCommands.swift` and `CLI/CMUXCLI+VM*.swift` (~7,900 lines),
`CMUXCLI+Cloud*.swift`, `CMUXCLI+AuthTeam.swift`, `Commands/AuthCommands.swift`. Settings sections: Account,
Mobile, Cloud, Devices, Networking (Iroh) and their cards. Build: `CMUX_DEV_CLOUD_ENABLED`,
`CMUX_IROH_*` and `CMUX_AUTH_CALLBACK_SCHEME` in `reload.sh` and `Info.plist`.

**Tangle:** very high. 316 of the ~2,980 Swift files in `Sources`/`CLI` import `CmuxCloud`; 653 mention "cloud",
219 mention "mobile". 47 import `CmuxAuthRuntime`. `TerminalController.swift` and `AppDelegate.swift` import it.

**Plan (stub first, delete later):**
1. 9a: Hide the entry points. Remove Settings sections Account, Mobile, Cloud, Devices, Networking; the Cloud menu
   (`cmuxApp+CloudMenu.swift`), the sidebar cloud button and badge, "New Cloud Workspace", the welcome videos, the
   pricing screen. Don't start the mobile host (`MobileHostService.shared.start()` in `AppDelegate`; today it
   only listens when the Mobile setting is on).
2. 9b: Remove the CLI commands `cmux vm …`, `cloud`, `auth`, `team`. Unlink `CmuxCloudResizeCore` from the CLI.
3. 9c: Replace `CmuxCloud` and `CmuxAuthRuntime` uses with small local stubs (signed out, no team, no machines),
   one area at a time (sidebar, file explorer, terminal paste, session restore), each its own commit.
4. 9d: Delete the packages and Stack Auth, and the `CMUX_IROH_*` / `CMUX_AUTH_CALLBACK_SCHEME` keys in `Info.plist` and `reload.sh`.

**Risk:**
- The cloud code is woven into the terminal, sidebar, file explorer and image paste paths. A wrong cut breaks
  local terminals, not just cloud ones.
- Session restore: drop `cloudVM` and `cloudMachineTeams` (optional fields, rule 2). Your file has none.
- Keep `CMUXMobileCore`, `CmuxAgentChat`, `CmuxTerminalSharing` (it also runs local terminal sizing:
  `LocalTerminalSizingHost`) and `CmuxSSHClipboardTrust` (plain SSH).

- ✅ After each sub-step: `scripts/test-app.sh --seed`; all groups and workspaces come back (`tree --all`). ⬜ zsh
  folder/branch/PR, `claude`/`pi` states, `open https://…`, the cmux agent's tools: by hand (see "Manual checks left" in
  chief-cloud-removal-plan.md).
- ✅ `cmux --version` from the built app; `cmux config doctor`.
- ⬜ `scripts/install-personal.sh`.

## Other candidates (not planned yet)

| Candidate | What it is | Upstream-service-only? | Confidence |
|---|---|---|---|
| `CmuxProductAnalytics` (28 app files) | Event plumbing that used to feed PostHog. With PostHog gone it sends nothing. | Yes, but harmless now | High that it's useless; low value to remove |
| `CmuxRuntimeDebugCapture*` | Posts debug logs to a URL, only if `CMUX_RUNTIME_DEBUG_BASE_URL` is set | Yes | High; off unless you set the variable |
| `start-cmux-profiling`, `submit-cmux-profile` | Support profiling, drafts an email to upstream | Yes | Medium; harmless |
| Agent hooks you don't use (Campfire, Kiro, RovoDev, Glaeda, Amp, Hermes, …) | Integrations for other agents | No, local | Low; leave them |
| Remote SSH workspaces and remote tmux (`cmux ssh`, `RemoteTmux*` ~120 files, `CmuxRemoteSession`, `CmuxRemoteWorkspace`, `CmuxRemoteDaemon`) | Open a workspace on your own server over SSH, mirror its tmux | **No.** Works with your own machines, no cmux server | Keep. The zsh `*_via_relay` code and `cmux-tmux-agent.py` serve it |
| Local tmux / zellij (`CMUXCLI+LocalTmux*`) | Keeps processes alive across quits | No | Keep |
| Upstream-only scripts (`blacksmith-*`, `remote-tmux-*`, `ios-*`, `mobile-*`, `sparkle_*`, `release-*`, `run-iroh-*`, …) | CI, release, iOS tools | Yes | High; nothing in your build calls them. Delete in one commit after checking with `grep` that `reload.sh`, `test-app.sh`, `install-personal.sh` and the Xcode phases don't name them |

## Check list for every phase

- ⬜ One phase per commit; run the build after each step, as in `61dca2e`.
- ⬜ `./scripts/test-app.sh --seed` builds and opens **cmux DEV test** with your layout.
- ⬜ In the test app: a new zsh terminal shows folder and git branch in the sidebar; `claude` and `pi` start through
  the shims and show `run` / `wait` / `idle`; a notification shows the red number.
- ⬜ `"<test app>/Contents/Resources/bin/cmux" --version` and `config doctor` work.
- ⬜ ⌘Q and reopen the test app: everything comes back.
- ⬜ Commit, then `./scripts/install-personal.sh`. If something's wrong, restore from `personal-backups/<date>/`.
- ⬜ Update `docs/overview.md` (⚠️ → removed) and `docs/ideas.md`.
