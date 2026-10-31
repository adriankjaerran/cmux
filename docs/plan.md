# Plan

Written 2026-10-31 from [next-steps.md](next-steps.md), after checking the code for each item.
Size: S = under an hour, M = a few hours, L = a day or more.

## Done today

- [x] Groups **Personal**, **Schjødt** and **Hoegh** and their workspaces were rebuilt in cmux Personal with
  `cmux workspace-group`. They open as fresh shells in the right folders. Agents still running in nightly
  stay there. The **Home** (Chief) group was left out on purpose; see step 2.
- [x] The pinned **cmux** row at the top: Pi `--preset cmux` in `~/Code/cmux-config`, coloured indigo. It was made by
  `~/Code/cmux-config/scripts/pin-cmux-agent.sh` with `CMUX_SOCKET_PATH=/tmp/cmux-debug-mine.sock`.
  `zsh/cmux.zsh` restarts it after an app restart.

## Ready now (no decision needed)

| # | What | Size | How |
|---|---|---|---|
| 1 | **Turn off Sentry** (it is probably on today) | S | Now: `defaults write com.cmuxterm.app.debug.mine sendAnonymousTelemetry -bool false`. In code: `MacSentryStartupPolicy.shouldStart` → false; `CMUX_CLI_SENTRY_DISABLED=1` in `LSEnvironment`. PostHog is already off in Debug builds. |
| 2 | **Turn off Sparkle** | S | Remove `SUFeedURL` and set `SUEnableAutomaticChecks=false` in `Resources/Info.plist`. Must come before a bundle id change, because a non-dev id turns update checks back on. |
| 3 | **Remove the Home (Chief) group for good** | S | In the group restore (`TabManager.swift:~7300`), drop the group when `externalID == cmux.chief.home` and Chief is off. Skip the Home Chief panel (`Workspace.swift:2426`). Make `isChiefHome`/`isChiefHomeGroup` false when Chief is off so unpin and delete work. Add a test. |
| 4 | **Skip the CodeRouter download** | S | Put `CMUX_SKIP_CODEROUTER=1` around `scripts/reload.sh:2153` and set it in `install-personal.sh`. |
| 5 | **⌥⌘↑ / ⌥⌘↓ for previous / next workspace** | S | Config only. `prevSidebarTab`/`nextSidebarTab` already exist (default ⌃⌘[ / ⌃⌘]); rebind them in `cmux.json`. |
| 6 | **Agents stop stealing focus (most cases)** | S | Config only. `export CMUX_FOCUS_NEW=0` in `zsh/cmux.zsh`. The CLI already reads it. |
| 7 | **Save ⌘P "done" times across restarts** | S | Add `lastCommandFinishedAt` to `SessionWorkspaceSnapshot`, then save and restore it. |
| 8 | **Remove the VPN TunnelExtension** | S–M | Only the Xcode project uses it: remove the target, the embed step and the dependency, then build. |

## Needs a decision first

| # | What | Size | Decision |
|---|---|---|---|
| 9 | **⌘O keyboard navigation of the compact sidebar** | M | The JS sidebar can't take keyboard focus (it isn't a web view), so this needs a "sidebar keyboard mode" in AppDelegate: ⌘O enters it, ↑/↓ select, ←/→ collapse/expand the group, Return/Esc go back to the terminal. Decide: should ↑/↓ skip collapsed groups, and do you want a visible focus ring? |
| 10 | **Wrong "waiting" state** | S–M | It comes from agent `needs_input` that never clears (interrupted prompt, killed session, non-blocking notification). Cheap fix: in `compact.js`, ignore it when the agent has had activity since or its process is gone. Proper fix: in the agent registry. Needs one repro to confirm which case. |
| 11 | **Global "never steal focus" setting** | S | After item 6: should the setting also block explicit focus requests (`workspace select`, `--focus true`), or only change the defaults? |
| 12 | **Browser tabs keep running in the background** | M | WebKit pauses hidden pages, and Memory Saver discards them. A `keepRendering()` already exists for the REPL. Decide: always (more CPU, uses a private API), or only while a `browser.*` command runs? |
| 13 | **Default browser viewport 1440×900** | S–M | `cmux browser set-viewport` already exists; this adds a `browser.defaultViewport` setting. Decide: all tabs or only agent-opened ones, and should it survive a restart? |
| 14 | **Own bundle id** (`no.datafabric.cmux`) | M | Set it at install time (PlistBuddy, simple) or in the Xcode project (cleaner)? Either way: migrate the session, journal and settings files and pin the socket path. Do it after 1–2. |
| 15 | **Chief** | M | Remove it, or only hide it? Item 3 fixes the Home group either way. |

## Later / large

- **Computer Use** removal (M: 16 files and the helper build in `reload.sh`).
- **Cloud and Auth**: stub them behind the existing feature flag rather than deleting them (L: 300+ importers).
- One home for `compact.js` (repo vs `~/.config/cmux/sidebars`), a smoke-test script, and a single writer for `cmux.json`.

## Suggested order

1 → 2 → 4 → 3 → 5 + 6 (config) → 9 → 10 → 7 → 8 → then the decisions in 11–15.
That order stops data from leaving the machine first, then makes the Home group go away for good, then makes the sidebar usable from the keyboard.
