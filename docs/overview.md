# Overview: what was copied from upstream

Source: `manaflow-ai/cmux` at commit `8fc656c` (local clone in `~/Code/cmux_github`).
Only the macOS app and what it needs to build were copied. Everything else stayed behind.

✅ copied · ⚠️ copied but slated for removal · ❌ not copied

## The Mac app

| | Path | What it is |
|---|---|---|
| ✅ | `cmux.xcodeproj` | Xcode project, `cmux` scheme, pinned package versions (`Package.resolved`) |
| ✅ | `Sources/` | The app itself (AppKit + SwiftUI) |
| ✅ | `CLI/` | The `cmux` command-line tool, talks to the app over a socket |
| ✅ | `Resources/` | Info.plist, entitlements, shell integration, bundled web views, `sidebars/compact.js` (new) |
| ✅ | `Assets.xcassets`, `AppIcon.icon` | Images and app icon |
| ✅ | `cmux-Bridging-Header.h`, `ghostty.h` | C headers for Ghostty |
| ✅ | `Packages/` | Local Swift packages (`macOS/`, `Shared/`, `iOS/`); the ones nothing linked were deleted later (see below) |
| ✅ | `Native/` | Rust/C helpers built during the app build (e.g. command-palette search) |
| ✅ | `vendor/stack-auth-swift-sdk-prerelease` | Vendored library |
| ✅ | `vendor/bonsplit` | Split-pane library, git submodule at `58b73fd` |
| ✅ | `ghostty` | Terminal engine, git submodule at `ef4f157` (must match the prebuilt download) |
| ✅ | `Examples/CmuxExtensionSidebarExamples` | Built-in sidebar providers the app links |
| ✅ | `workers/cmux-paste-text` | Plain-text paste helper bundled in the app |
| ✅ | `scripts/` | Build scripts (`reload.sh`, `ensure-ghosttykit.sh`, …) plus `install-personal.sh` (new) |
| ✅ | `LICENSE`, `THIRD_PARTY_LICENSES.md` | Required by the GPL |
| ❌ | `cmux.xcworkspace` | Not needed; the project opens on its own |
| ❌ | `*.entitlements` at the root | Unused; the app uses `Resources/cmux.entitlements` |

## Left behind

| | Path | Why |
|---|---|---|
| ❌ | `web/`, `services/`, `workers/*` (except `cmux-paste-text`) | Upstream's commercially licensed server side |
| ❌ | `ios/` | iPhone app |
| ❌ | `cmux-browser/`, `cmux-tui/`, `coderouter/`, `vault/`, `agent-chat/`, `daemon/` | Separate products and services |
| ❌ | `webviews/` | Sources for web views; the built output is already in `Resources/` |
| ❌ | `cmuxTests/`, `cmuxUITests/`, `cmuxCLITests/`, `cmuxCLITestSupport/`, `tests/`, `tests_v2/` | App test suites (package tests under `Packages/*/Tests` were kept) |
| ❌ | `docs/`, `design/`, `plans/`, `Prototypes/`, `experiments/`, `dogfood/`, `artifacts/`, `KeyboardPinningLab/` | Upstream docs and experiments |
| ❌ | `skills/` | Upstream's agent skills; `cmux-architecture` and `cmux-dev-workflow` are worth reading |
| ❌ | `Examples/` (except the sidebar examples), `schemas/`, `config/` | Samples and CI config |
| ❌ | `homebrew-cmux` | Homebrew tap (submodule) |
| ❌ | `README*.md`, `AGENTS.md`, `CLAUDE.md`, `CHANGELOG.md`, `TODO.md`, other root notes | Upstream docs |
| ❌ | `package.json`, `bun.lock`, `biome.json`, `skills.sh`, `glaeda.apple.json` | JS tooling for the parts left behind |

## Still inside the app, but tied to upstream's services

These build and ship today. They are the trimming list in [ideas.md](ideas.md).

| | Feature | Note |
|---|---|---|
| ⚠️ | Cloud, Auth, mobile pairing, `cmux vm` | `CmuxCloud*`, `CMUXAuthCore`, `CmuxAuthRuntime`, `CmuxMobile*`, Iroh (removal plan Phase 9) |
| ⚠️ | Chief and Chief Home | `CmuxChief`, `CmuxHomeCore`, `CmuxHomeRender`, `CmuxMessagesLab` (Phase 8) |
| ⚠️ | CodeRouter CLI commands | `cmux coderouter` / `cmux cr` and the guide panel are still in the app; the binary is no longer downloaded |
| ❌ | cmux-tui client (cloud Machines panel) | Skipped by `reload.sh` |

## Fork changes so far

See the table in the [README](../README.md#whats-different-from-upstream-cmux) and `git log`.

## Removed after the copy

| Feature | What went |
|---|---|
| iOS Simulator panes | `CmuxSimulator` package, File → New Simulator Pane, `cmux simulator` / `cmux ios` |
| Computer Use | `CmuxComputerUse`, the `cmux Computer Use.app` helper, `skills/cmux-cua`, its Settings section |
| VPN tunnel extension | `TunnelExtension/`, `vendor/WireGuardKit`, the wireguard-go build step |
| Telemetry | PostHog SDK and Sentry SDK; the app's call sites are now no-ops |
| CodeRouter download | `reload.sh` no longer fetches the `coderouter` binary (`edbd4f6`) |
| Sparkle update feed | `SU*` keys, "Check for Updates…" everywhere, `CmuxUpdater`, `CmuxUpdaterUI`, the Sparkle package, the update pill (`883957f`, `032f629`) |
| Remote feature flags | No more POST to `cmux.com/api/client-config`; flags use local defaults (`7cef649`) |
| Unlinked packages | 21 `Packages/iOS/*`, 6 `Packages/Shared/*`, `CmuxLiveEval` (`190efab`) |
| VPN / Computer Use leftovers | `cmux vpn`, Computer Use settings stubs, `ComputerUseHelper.icon` (`45ec320`) |
| Simulator leftovers | The five "Simulator: …" shortcuts, "New Simulator Pane", `simulator.*` socket stubs (`b9f12ee`); `PanelType.simulator` stays so old layouts load |
| Send Feedback | `CmuxFeedback`, the Help/sidebar items, `cmux feedback`, `feedback.open` / `feedback.submit` (`7e6c136`) |
