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

## What's different from upstream cmux

| Change | Where |
|---|---|
| ⌘P lists unread workspaces first, then by most recent use; past picks no longer reorder it | `CommandPaletteWorkspaceOrdering.swift`, `CommandPaletteSearchOrchestrator.swift` |
| ⌘P rows show the red unread number and a short activity note (`waiting`, `running 3m`, `done 4m`) instead of "Workspace" | `ContentView.swift`, `CommandPaletteWorkspaceActivity.swift`, `GhosttyTerminalView.swift` |
| The compact one-line sidebar is built in and is the default | `Resources/sidebars/compact.js`, `CmuxExtensionSidebarSelection.swift`, `CmuxMain.swift` |
| Builds without upstream's git history, team login or cmux-tui client | `scripts/reload.sh`, `scripts/install-personal.sh` |

## Docs

| File | What it holds |
|---|---|
| [docs/overview.md](docs/overview.md) | What was copied from upstream and what wasn't (checklist) |
| [docs/architecture.md](docs/architecture.md) | Conceptual model: how the app is put together, where to change what |
| [docs/ideas.md](docs/ideas.md) | My ideas and wishes, done and open |
| [docs/next-steps.md](docs/next-steps.md) | Open work, collected from earlier sessions, in priority order |
| [docs/suggestions.md](docs/suggestions.md) | Suggested next steps |

## Licence

GPL-3.0, like upstream. See [LICENSE](LICENSE) and [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md).
