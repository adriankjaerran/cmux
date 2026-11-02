# cmux Personal

My own build of [cmux](https://github.com/manaflow-ai/cmux), the macOS terminal for running many coding agents
side by side. It is the upstream Mac app copied at commit `8fc656c`, with my own changes on top.
It runs next to the official cmux as **cmux Personal** (`~/Applications/cmux Personal.app`).

## Quick start

```bash
./scripts/install-personal.sh            # build, install to ~/Applications, open
./scripts/install-personal.sh --no-build # reinstall the last build
```

Then start **cmux Personal** from Spotlight or the Dock.

- Needs Xcode 26, the Metal toolchain, and Zig 0.16.0 in `~/.local/share/zig/` (used automatically).
- The first build downloads the prebuilt Ghostty library (`scripts/ensure-ghosttykit.sh`) and takes ~10 minutes;
  later builds take about a minute.
- The bundled CLI: `~/Applications/cmux\ Personal.app/Contents/Resources/bin/cmux`, socket `/tmp/cmux-debug-mine.sock`.

## Test app and updating the main app

There are two apps, built from this repo:

| App | Where it runs from | Saved layout (workspaces, groups, splits) | Socket |
|---|---|---|---|
| **cmux Personal**, the daily app | `~/Applications/cmux Personal.app` | `~/Library/Application Support/cmux/session-com.cmuxterm.app.debug.mine.json` | `/tmp/cmux-debug-mine.sock` |
| **cmux DEV test**, for trying changes | `~/Library/Developer/Xcode/DerivedData/cmux-test/Build/Products/Debug/cmux DEV test.app` | `…/session-com.cmuxterm.app.debug.test.json` | `/tmp/cmux-debug-test.sock` |

They have different bundle ids, so they run side by side and never share saved data. Both read
`~/.config/cmux/cmux.json`, so shortcuts and settings are the same.

### Try changes in the test app

```bash
./scripts/test-app.sh          # build, quit the old test app, open the new one
./scripts/test-app.sh --seed   # same, but first copy cmux Personal's layout into the test app
./scripts/test-app.sh --no-build
```

- The first build takes ~10 minutes (its own build folder). Later builds take about a minute.
- Without `--seed`, the test app keeps its own layout between builds.
- Don't use `reload.sh --tag mine` for testing. `mine` is cmux Personal's identity, so the two would share a
  socket and saved data.

### Update cmux Personal

When a change works in the test app, commit it and run:

```bash
./scripts/install-personal.sh
```

It builds, quits cmux Personal properly (so it saves its layout), backs up the saved layout to
`~/Library/Application Support/cmux/personal-backups/<date>/` (the 10 newest are kept), replaces the app and
opens it again. Your workspaces, groups and splits come back as before, because they're saved outside the app.
Terminals restart as fresh shells, so finish or note running agent work first.

To restore a backup: quit cmux Personal, copy the files from a `personal-backups/<date>/` folder back into
`~/Library/Application Support/cmux/`, then start it.

## What's different from upstream cmux

| Change | Where |
|---|---|
| ⌘P lists unread workspaces first, then by most recent use; past picks no longer reorder it | `CommandPaletteWorkspaceOrdering.swift`, `CommandPaletteSearchOrchestrator.swift` |
| ⌘P rows show the red unread number and a short activity note (`waiting`, `running 3m`, `done 4m`) instead of "Workspace" | `ContentView.swift`, `CommandPaletteWorkspaceActivity.swift`, `GhosttyTerminalView.swift` |
| The compact one-line sidebar is built in and is the default | `Resources/sidebars/compact.js`, `CmuxExtensionSidebarSelection.swift`, `CmuxMain.swift` |
| Groups are folders: the header only opens/closes; its former session is the first row inside and can be moved or removed like any other | `Resources/sidebars/compact.js`, `WorkspaceGroupCoordinator.swift` |
| The cmux agent workspace can't be closed or unpinned and stays on top; closing or killing its terminal starts a fresh agent (`cmux workspace-action --action set-agent-home --command <cmd>`, saved with the layout) | `TabManager+NonInteractiveClose.swift`, `Workspace+TerminalRespawn.swift`, `TabManager.swift` |
| Builds without upstream's git history, team login or cmux-tui client | `scripts/reload.sh`, `scripts/install-personal.sh` |

## Docs

| File | What it holds |
|---|---|
| [docs/overview.md](docs/overview.md) | What was copied from upstream and what wasn't (checklist) |
| [docs/architecture.md](docs/architecture.md) | Conceptual model: how the app is put together, where to change what |
| [docs/ideas.md](docs/ideas.md) | My ideas and wishes, done and open |
| [docs/next-steps.md](docs/next-steps.md) | Open work, collected from earlier sessions, in priority order |
| [docs/suggestions.md](docs/suggestions.md) | Suggested next steps |
| [docs/plan.md](docs/plan.md) | What is ready to build, what needs a decision, and in what order |
| [docs/removal-plan.md](docs/removal-plan.md) | What's left to remove from upstream, phase by phase, and what must keep working |

## Licence

GPL-3.0, like upstream. See [LICENSE](LICENSE) and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
