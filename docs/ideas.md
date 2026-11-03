# My ideas

Things I've asked for or want. ✅ done · ⬜ open

## Goal

Full control over my own cmux: a small, fast Mac app that works the way I work, without upstream's cloud,
telemetry or update feed.

## ⌘P (Go to Workspace)

- ✅ Workspaces with something unread (a notification, or "Mark as Unread") come first.
- ✅ Then the rest, most recently used first. This is the app's default, not just a config setting.
- ✅ The red unread number, like in the sidebar.
- ✅ No "Workspace" label; instead a very short note on the last thing that happened: `waiting`, `running 3m`,
  `done 4m` (agent done, terminal command finished, notification).

## Sidebar

- ✅ The compact one-line sidebar (title left, `idle` / `run` / `wait` right, red unread number), built in.
- ✅ The same sidebar and display settings as my main cmux.
- ⬜ My groups (Home, Schjødt, Personal, Hoegh) and workspaces in cmux Personal.

## A proper app

- ✅ Starts from Spotlight and the Dock as **cmux Personal**, next to the official cmux.
- ⬜ A real own name everywhere (process name, bundle id), not upstream's "cmux DEV".

## Trimming (one at a time, keeping it building)

- ✅ Remove Computer Use.
- ✅ Remove the VPN tunnel extension.
- ✅ Remove Sentry and PostHog telemetry.
- ✅ Remove iOS Simulator panes.
- ✅ Remove the Sparkle update feed (and the Sparkle package).
- ✅ Stop the CodeRouter download in the build.
- ✅ Stop the remote feature-flag fetch to cmux.com.
- ✅ Delete the packages nothing links.
- ✅ Remove the VPN / Computer Use / Simulator leftovers.
- ✅ Remove Send Feedback.
- ⬜ Install all of the above into cmux Personal (removal plan Phase 0, then reinstall).
- ✅ Remove Chief and Chief Home (removal plan Phase 8).
- ✅ Remove Cloud, Account, Mobile, Devices, Iroh and Stack Auth (removal plan Phase 9, done in the test app).
- ⬜ Later cleanups after Phase 9: shrink `CmuxMobileHost` to the browser dialog broker, the hidden Cloud/Mobile
  Settings sections and `mobile.*` settings keys, the upstream iOS/Iroh/mobile dev scripts in `scripts/`, the
  orphaned `.xcstrings` keys (see the 9.17 note in chief-cloud-removal-plan.md).

## cmux agent (from `~/Code/cmux-config`)

- ✅ A pinned "cmux" workspace running a Pi agent that manages cmux, replacing Chief
  (`cmux-config/plans/cmux-agent.md`).
- ⬜ Run it in cmux Personal too.
