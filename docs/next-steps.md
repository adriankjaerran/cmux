# Next steps

Collected from my earlier Claude Code sessions (mostly `~/Code/cmux-config`, 2026-10-31) and this fork's work.
Only open or half-done items; finished ones are in [ideas.md](ideas.md). Roughly in priority order.

## 1. Keyboard navigation of the sidebar

- [ ] **⌘O focuses the sidebar, ↑/↓ moves, Return opens, Esc goes back to the terminal.** Bound in `cmux.json`
  (`focusSidebar: cmd+o`) but it doesn't work with the compact sidebar: custom JS sidebars don't get key presses.
  Fix in the fork: give the custom sidebar keyboard focus, or make the compact layout a native sidebar.
- [ ] **← collapses the current group, → expands it, Space/Enter opens the workspace.**
- [ ] Fallback: ⌥⌘↑ / ⌥⌘↓ for previous / next workspace without focusing the sidebar.

## 2. Sidebar

- [ ] **Remove the pinned "Home" (Chief) group.** Chief is off, but the group comes back from the saved session and
  unpin / delete don't stick. Fix it in the fork (drop it on restore, or remove Chief).
- [ ] **Fix the wrong "waiting" state** (a row showed `wait` when nothing was waiting) and make rows a bit more concise.
- [ ] **A "finished, not looked at yet" mark** that is clearer than the unread number (compact.js has a blue dot for this).
- [ ] Bring my groups (Home, Schjødt, Personal, Hoegh) and workspaces into cmux Personal.

## 3. Focus stealing

- [ ] **A global "never steal focus" setting.** Agents doing web or UI runs pull focus away from the terminal;
  today it can only be avoided with `--focus false` per command.
- [ ] Browser tabs pause when their workspace isn't in front, which blocks agent checks in the background.

## 4. Browser for agents

- [ ] A default browser viewport (e.g. 1440×900) for agent screenshots, instead of a hook and wrapper.

## 5. The cmux agent

- [ ] Run the pinned Pi "cmux" agent in cmux Personal too (it works per app).
- [ ] Ideas from `cmux-config/plans/cmux-agent.md`: a morning summary, start a Claude/Pi agent in a group with a task,
  a "which agents are waiting for me" view, block `cmux send` / `close` when run through bash.
- [ ] A simple overview of logs (a one-line error when the hub is down already exists).

## 6. Config

- [ ] Only one session at a time should edit `cmux.json`; parallel edits once caused duplicate `shortcuts` blocks.
  A fork could lock or validate on write.

## 7. Trimming (from the fork plan)

- [ ] Remove Sentry and PostHog telemetry, and the Sparkle update feed.
- [ ] Remove Computer Use and the VPN tunnel extension.
- [ ] Stub out Cloud, Auth and Chief; stop the CodeRouter download.
- [ ] Own bundle id and name everywhere.
