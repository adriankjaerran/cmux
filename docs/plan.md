# Plan

Updated 2026-10-31. Chosen to build: the four "ready" items, the two config changes, ⌘O sidebar navigation,
focus stealing, the "waiting" fix, and a new red/blue "agent needs you" mark.
Size: S = under an hour, M = a few hours, L = a day or more. Background: [next-steps.md](next-steps.md).

## Done

- [x] Groups **Personal**, **Schjødt** and **Hoegh** and their workspaces rebuilt in cmux Personal. Home (Chief) was left
  out on purpose.
- [x] The pinned **cmux** row at the top (Pi `--preset cmux`, indigo) via `cmux-config/scripts/pin-cmux-agent.sh`.

## What the unclear items actually are

| Thing | What it is | What it does in your build today | After the change |
|---|---|---|---|
| **Sentry** | An error and crash reporting service. When the app crashes or hits an error, it sends a report (stack trace, app version, macOS version, sometimes file paths) to the **cmux team's** Sentry account. | **On.** Your reports go to the cmux team, and you can't see them. The app and the `cmux` CLI each have their own Sentry. | Nothing is sent. You lose nothing: macOS still writes crash logs locally (Console → Crash Reports). |
| **PostHog** | Usage analytics: which features are used and how often. | Already off in your build (it only runs in official releases). | Kept off in code, so a release build can't turn it on. |
| **Sparkle** | The auto-updater. It checks the cmux team's update feed and offers to install a new version. | Asleep, only because your bundle id looks like a dev build. If you ever give the app its own id, it wakes up and could offer to **replace cmux Personal with the official cmux**, losing your changes. | The feed is removed, so it can never offer an update. You update by rebuilding (`install-personal.sh`). |
| **CodeRouter** | A separate command-line tool from the cmux team (`cmux coderouter` / `cmux cr`), bundled into the app. I couldn't confirm exactly what it does, but nothing in your setup uses it. | Each build checks for it and downloads a new copy (~tens of MB) from GitHub whenever upstream bumps the version. | The build skips it: faster and works offline. If you ever run `cmux cr`, it offers to install itself. |
| **Logs** | cmux writes its own logs locally (the debug log, notification history, agent journal in `~/Library/Application Support/cmux`). These never leave the machine. | Unchanged. | Unchanged. |

## Phase 1: stop data leaving the machine (S, one build)

1. Sentry off in the app (`MacSentryStartupPolicy.shouldStart` → false) and in the CLI (`CMUX_CLI_SENTRY_DISABLED=1`
   in the app's `LSEnvironment`).
2. PostHog `isEnabled` → false.
3. Sparkle: remove `SUFeedURL`, set `SUEnableAutomaticChecks=false` (`Resources/Info.plist`).
4. CodeRouter: `CMUX_SKIP_CODEROUTER=1` around `scripts/reload.sh:2153`, set in `install-personal.sh`.
5. Check: build, launch, then confirm no connection to `sentry.io` (`nettop` / Little Snitch) while forcing an error.

## ✅ Phase 2: the Home group goes away for good (S)

Done by removal plan step 8.1 (`bf3a1d0`): the `cmux.chief.home` group and Chief panels are dropped on restore,
`isChiefHome` / `isChiefHomeGroup` were false, and later steps (8.3, 8.4) deleted Chief altogether. No unit test
(the `cmuxTests` folder isn't in this repo).

1. On restore (`TabManager.swift:~7300`): drop the group with `externalID == cmux.chief.home` when Chief is off.
2. Don't restore the Home Chief panel when Chief is off (`Workspace.swift:2426`). A Home workspace left with no panels
   is dropped.
3. `isChiefHome` / `isChiefHomeGroup` → false when Chief is off, so unpin and delete work.
4. Unit test: a session with a Home group restores without it when Chief is off.

## Phase 3: config only, no build (S, in `~/Code/cmux-config`)

1. ⌥⌘↑ / ⌥⌘↓ → `prevSidebarTab` / `nextSidebarTab` in `cmux.json`.
2. `export CMUX_FOCUS_NEW=0` in `zsh/cmux.zsh`: CLI commands from agents no longer bring windows forward.

## Phase 4: never steal focus (S)

1. A `cmux.json` setting, `automation.stealFocus: false`.
2. When off: the app sets `CMUX_FOCUS_NEW=0` in every terminal it starts. The three CLI commands that default to
   `--focus true` (`project open`, `surface project`) follow it. `socketCommandAllowsInAppFocusMutations` refuses
   focus changes that come from a socket command (decision A below).
3. Your own clicks and keyboard shortcuts still move focus as usual.

## Phase 5: ⌘O sidebar navigation (M)

1. ⌘O (`focusSidebar`) with the compact sidebar turns on a "sidebar keyboard mode" for that window, and the terminal
   stops receiving keys.
2. ↑/↓ move the selection through visible workspaces, skipping members of collapsed groups (decision C).
3. ← collapses the selected workspace's group, → expands it.
4. Return opens the workspace and puts focus in its terminal. Esc goes back to where you were. A mouse click or any
   other key ends the mode.
5. `compact.js` draws a thin focus ring on the selected row while the mode is on.
6. Test by hand plus a unit test for the key handling.

## Phase 6: fix "wait" and add the red / blue marks (M)

**The bug:** an agent's "needs input" state never clears in three cases: you interrupt a question or permission prompt
with Esc or Ctrl-C, the session is killed, or Claude sends a plain notification. The row then says `wait` forever.

1. Log the agent events for one session that shows the wrong `wait`, to confirm which case it is.
2. Fix it in the agent registry (`AgentChatSessionRegistry+Lifecycle.swift`): any later activity (prompt, tool use,
   stop) clears the state. Only real question and permission events set it. Sessions whose process is gone count as ended.
3. Record **why** the agent is waiting: `question` (AskUserQuestion, plan approval) or `permission` (asking to run a
   tool), and pass it to the sidebar.
4. `compact.js` shows the mark (colours are decision B):
   - **ask**: the agent asked you a question.
   - **perm**: the agent wants permission to run something.
   - `run` and `idle` as today. The "finished while you were away" dot stays.
5. Optionally a macOS notification when a question arrives (decision D).
6. Pi agents report differently (Pi's "your turn" isn't a question), so Phase 6 covers Claude Code first. Pi follows
   if pi-cmux sends the same events.

## Later (not chosen yet)

- Background browser tabs keep running for agents, and a default 1440×900 browser viewport.
- Save the ⌘P "done" times across restarts. Remove the TunnelExtension and Computer Use.
- Own bundle id (do it after Phase 1). Remove or hide Chief. Stub Cloud and Auth.

## Order

Phase 1 → 2 (one build) → 3 (config) → 4 → 5 → 6. Commit after each phase and reinstall to try it.
