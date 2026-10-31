# cmux Personal — architecture in five minutes

A macOS terminal app. Swift, AppKit + SwiftUI. Ghostty draws the terminals.
Most code is in `Sources/` (≈1,600 files). Much of it has been moved into local
packages under `Packages/macOS/*`. The big files are `AppDelegate.swift`, `ContentView.swift`,
`TerminalController.swift`, `Workspace.swift`, `GhosttyTerminalView.swift` and `TabManager.swift`.
Each is 7k–21k lines. Use grep. Don't read them top to bottom.

Entry point: `Sources/CmuxMain.swift` (`@main`). `installPersonalDefaults` registers the fork's defaults.
`AppDelegate.shared` is the global hub for app state.

## 1. Core concepts and nesting

```
App (AppDelegate)
└─ Window            AppDelegate.MainWindowContext  (one per NSWindow)
   └─ Workspace      Workspace   (listed by TabManager; in code often called a "tab")
      └─ Pane tree   BonsplitController (splits → panes)
         └─ Surface  any Panel (TerminalPanel, BrowserPanel, MarkdownPanel, …) = one Bonsplit tab
```

| Concept | Main type | File(s) | Notes |
|---|---|---|---|
| Window | `AppDelegate.MainWindowContext` | `Sources/AppDelegate.swift` (`createMainWindow`, `registerMainWindow`) | Holds `tabManager`, `sidebarState`, `fileExplorerState`, `cmuxConfigStore`, `windowDock`. All windows: `AppDelegate.mainWindowContexts`. |
| Window UI | `ContentView` | `Sources/ContentView.swift` (+ `ContentView+*.swift`) | Root SwiftUI view: sidebar, workspace content, command palette. |
| Workspace list | `TabManager` | `Sources/TabManager.swift` | `tabs: [Workspace]`, `selectedTabId`, `workspaceGroups`. One per window. Some logic lives in `Packages/macOS/CmuxWorkspaces`. |
| Workspace | `Workspace` | `Sources/Workspace.swift` (+ `Workspace+*.swift`) | Doc comment: "Workspace represents a sidebar tab". Owns one `bonsplitController` and `panels: [UUID: any Panel]`. |
| Workspace view | `WorkspaceContentView` | `Sources/WorkspaceContentView.swift` | Renders `BonsplitView(controller: workspace.bonsplitController)`. |
| Splits/panes | `BonsplitController`, `BonsplitView` | `vendor/bonsplit` (submodule) | Split tree of panes. Each pane has a tab strip. Every Bonsplit tab maps to one Panel. |
| Surface/panel | `protocol Panel`, `enum PanelType` | `Sources/Panels/Panel.swift` | Types include terminal, browser, markdown, filePreview, rightSidebarTool, customSidebar, agentSession, notifications, … |
| Panel views | `PanelContentView` | `Sources/Panels/PanelContentView.swift` | Switches on the panel type → `TerminalPanelView`, `BrowserPanelView`, `MarkdownPanelView`, … |

The ID names are mixed up. Keep this in mind when reading:
- `tabId` usually means the **workspace** id. `CMUX_TAB_ID` = `CMUX_WORKSPACE_ID`.
- `surfaceId`/`panelId` is the **surface** id. `CMUX_PANEL_ID` = `CMUX_SURFACE_ID`.
- A Bonsplit "tab" is a **surface** inside a pane. It is not a workspace.

Create things with `TabManager.addWorkspace` / `addTab`, `Workspace.newTerminalSplit`, `newTerminalSurface`, `newBrowserSplit`.
Session save/restore: `Sources/SessionPersistence.swift`.

## 2. How a terminal works

- Ghostty is the terminal engine. It is compiled into `GhosttyKit.xcframework`. `scripts/ensure-ghosttykit.sh` downloads a pinned prebuilt copy. The source is the `ghostty/` submodule.
- `Sources/GhosttyTerminalView.swift` holds the bridge:
  - `GhosttyApp`: one `ghostty_app_t` per process. It loads the Ghostty config (`ghostty_config_load_default_files` + extra files) and builds a `ghostty_runtime_config_s` with C callbacks (`wakeup_cb`, `action_cb`, clipboard, …).
  - `action_cb` → `GhosttyApp.handleAction(target:action:)`. This is the big switch on `GHOSTTY_ACTION_*`: `NEW_SPLIT`, `SET_TITLE`, `PWD`, `DESKTOP_NOTIFICATION`, `RING_BELL`, `COLOR_CHANGE`, …. Desktop notifications go to `GhosttyDesktopNotificationIngress`.
  - `GhosttyNSView` (NSView): handles keyboard, mouse and IME for one surface.
  - `GhosttySurfaceScrollView`: the pane host that wraps it (scrollbar, overlays).
- `TerminalSurface` (`Packages/macOS/CmuxTerminal/.../Surface/TerminalSurface.swift`) owns the `ghostty_surface_t`. `ghostty_surface_new` is called in `TerminalSurface+RuntimeSurfaceCreation.swift`.
- `TerminalPanel` (`Sources/Panels/TerminalPanel.swift`) is the `Panel` wrapper. It has `let surface: TerminalSurface`.
- The shell gets these env vars: `CMUX_WORKSPACE_ID`, `CMUX_SURFACE_ID`, `CMUX_SOCKET_PATH`, … (`CmuxTerminal/.../Spawn/TerminalSurface+StartupEnvironment.swift`). The `cmux` CLI uses them to find "this" workspace/surface and the socket.

## 3. Sidebars

**Left (workspace) sidebar.** The setting `cmuxExtensionSidebarProviderId` picks which "provider" draws it. Logic: `Sources/CmuxExtensionSidebarSelection.swift`.
- Built-in: `VerticalTabsSidebar` (in `ContentView.swift`). Its provider id is `CmuxSidebarProviderDescriptor.defaultWorkspacesID`. Other built-in providers come from `Examples/CmuxExtensionSidebarExamples` (`SidebarExamples.providers`).
- Custom: files named `<name>.js|.swift|.json`. If two files share a name, the order of preference is js > swift > json. Provider id is `cmux.sidebar.custom.<name>`.
  - User dir: `~/.config/cmux/sidebars/` (`customSidebarsDirectory`). A user file overrides a bundled file with the same name.
  - Bundled (fork): `Resources/sidebars/*.js` → `Contents/Resources/sidebars`. They are copied by `scripts/build-app-bundled-resources.sh`.
  - **Fork default:** `cmux.sidebar.custom.compact` (`Resources/sidebars/compact.js`). Custom sidebars are on by default (`CmuxMain.installPersonalDefaults`).
  - Rendered by `CustomSidebarSurface` (`Packages/macOS/CmuxSidebarInterpreterService/.../CmuxSidebarRemoteRender`). JS runs in `SidebarJSRuntime` (JavaScriptCore, `Packages/macOS/CmuxSwiftRenderUI/.../Runtime`). Swift/JSON files go through `CmuxSwiftRender`. Sidebars run actions via `cmux(...)` calls, which become socket commands such as `workspace.reorder`.
- Visibility and width: `SidebarState` (`Sources/Sidebar/SidebarState.swift`). Other sidebar pieces live in `Sources/Sidebar/` and `Packages/macOS/CmuxSidebar*`.

**Right sidebar.** `RightSidebarPanelView` (`Sources/RightSidebarPanelView.swift`). Modes are listed in `RightSidebarMode.swift`: `files`, `find`, `sessions` ("Vault"), `feed`, `dock`, `machines` ("Cloud"), `customSidebar`.
- File explorer: `FileExplorerView.swift`, `FileExplorerStore.swift`, `FileExplorerState.swift` (per window), `FileExplorerSearchController.swift`.
- Custom mode mounts a `~/.config/cmux/sidebars/<name>` file through the same `CustomSidebarSurface`.

## 4. Command palette and ⌘P "Go to Workspace"

- ⇧⌘P = Command Palette. ⌘P = Go to Workspace. Defaults are in `Packages/macOS/CmuxSettings/.../Values/ShortcutAction+Defaults.swift`. The menu items are in `Sources/cmuxApp.swift` and post `.commandPaletteRequested` / `.commandPaletteSwitcherRequested`.
- The UI and state live in `ContentView.swift`: `openCommandPaletteCommands()`, `openCommandPaletteSwitcher()`. The overlay is `Sources/CommandPalette/CommandPaletteOverlay.swift`.
- Commands: `commandPaletteCommandContributions()` plus `registerCommandPaletteHandlers(_:)` in `ContentView.swift`. More are in the `ContentView+*CommandPalette.swift` files.
- Switcher rows: `commandPaletteSwitcherEntries(includeSurfaces:)`. It makes one `CommandPaletteCommand` per workspace (id `switcher.workspace.<uuid>`) across all windows. Fork: it adds `badgeCount` (unread) and an activity note.
- Switcher order: `commandPaletteOrderedSwitcherWorkspaces` → `CommandPaletteWorkspaceOrdering` (package). Unread workspaces come first, then by mode `recent` or `sidebar`. Setting: `goToWorkspaceOrder` (`AppCatalogSection`, fork default `.recent`).
- Package: `Packages/macOS/CmuxCommandPalette` holds the models (`CommandPaletteCommand`, `CommandPaletteCommandContribution`, `CommandPaletteHandlerRegistry`), search, policies and ordering.

## 5. Notifications, unread, agents

- `TerminalNotificationStore.shared` (`Sources/TerminalNotificationStore.swift`) is the single source of notifications and unread state. Keys are `tabId` (workspace) and an optional `surfaceId`.
  - API: `addNotification(...)`, `markRead/markUnread(forTabId:[surfaceId:])`, `unreadCount(forTabId:)`, `workspaceIsUnread(forTabId:)`. It also drives the Dock badge and the macOS user notifications.
  - Sources: Ghostty desktop-notification actions (OSC), `cmux notify` (socket `notify` / `notification.*`), agent hooks, todos.
- Agents (Claude Code, Codex, Gemini, Cursor, …) report to cmux through **hooks**. A hook is a shell command that runs `cmux hooks <agent> <event>`, or `cmux claude-hook …` for Claude.
  - The hook definitions per agent (config dir and file, events) are in `CLI/CMUXCLI+AgentHookCatalog.swift`. Install and parsing code is in `CLI/CMUXCLI+AgentHook*.swift`.
  - Session records are JSON files: `~/.cmuxterm/claude-hook-sessions.json` and `~/.cmuxterm/<agent>-hook-sessions.json` (`CMUX_AGENT_HOOK_STATE_DIR` overrides the dir). Types: `ClaudeHookSessionRecord` (`CLI/cmux.swift`), `RestorableAgentHookSessionRecord` (`Sources/`). Each record links an agent session to a workspace/surface/cwd/pid, for status and resume.
  - App side: `Sources/Agent*.swift`, `Sources/App/AgentHibernation*`, `Packages/macOS/CmuxAgent*`.

## 6. Control socket and the `cmux` CLI

- The app listens on a Unix socket. The server is `SocketControlServer` (`Packages/macOS/CmuxControlSocket/.../Server`), owned by `TerminalController` (`Sources/TerminalController.swift` plus about 136 `TerminalController+*.swift` files).
- Protocol, one line per request (`TerminalController.processCommand`):
  - **v1**: plain text, `cmd args` (e.g. `ping` → `PONG`). Some v1 domains go to `ControlCommandCoordinator` (`handleSidebarV1`, `handleBrowserPanelV1`, `handleDebugV1`). The rest go to a big `switch`.
  - **v2**: a JSON line `{"id","method","params"}` → `processV2Command`. Methods use dotted names: `workspace.list`, `surface.list`, `notification.dismiss`, …. Some run off the main thread in `ControlCommandCoordinator.handleSocketWorkerV2`. The method list is in `TerminalController+Capabilities.swift`.
  - **`debug.*`** methods (and v1 debug commands) exist only in DEBUG builds, behind `#if DEBUG`. The personal app is a Debug build, so it has them.
  - Access policy (off / cmuxOnly / password / allowAll) is applied in `withSocketCommandPolicy`.
- CLI: `CLI/cmux.swift` (`struct CMUXCLI`, `final class SocketClient`, ~46k lines) plus `CLI/CMUXCLI+*.swift`. It finds the socket via `CLI/CLISocketPathResolver.swift` and `CMUX_SOCKET_PATH`. It ships inside the app at `Contents/Resources/bin/cmux`.

## 7. Settings

- **Catalog**: `Packages/macOS/CmuxSettings/.../Keys/SettingCatalog.swift`. It is the single list of every setting, split into `*CatalogSection.swift` files (app, terminal, sidebar, notifications, betaFeatures, shortcuts, …).
  - Each key is `DefaultsKey(id: "app.goToWorkspaceOrder", defaultValue:, userDefaultsKey: "goToWorkspaceOrder")` and is stored in `UserDefaults.standard`.
  - SwiftUI reads keys with `@LiveSetting(\.section.key)` or `@AppStorage`.
- **File config**: `~/.config/cmux/cmux.json` (fallback `settings.json`). `CmuxSettingsFileStore` (`Sources/KeyboardShortcutSettingsFileStore.swift` + `CmuxSettingsFileStore+*.swift`) watches the file and writes its values into UserDefaults. It saves the old values and restores them when you remove a key. `CmuxConfigStore` (`Sources/CmuxConfig.swift`) reads the actions/commands/layouts from the same file.
- **Settings UI**: `Packages/macOS/CmuxSettingsUI` (`SettingsWindowRoot`, `Sections/*Section.swift`). It is hosted by `Sources/App/SettingsWindowFactory.swift` / `SettingsWindowPresenter.swift`.
- Keyboard shortcuts: `Sources/KeyboardShortcutSettings.swift` + `CmuxSettings/.../Values/ShortcutAction*.swift`.
- UI strings use `String(localized:defaultValue:)` → `Resources/Localizable.xcstrings`.

## 8. Build and install

| Script | What it does |
|---|---|
| `scripts/reload.sh --tag <t> [--launch]` | Runs xcodebuild for a Debug build into `~/Library/Developer/Xcode/DerivedData/cmux-<t>`. The result is "cmux DEV <t>.app" with bundle id `com.cmuxterm.app.debug.<t>`, socket `/tmp/cmux-debug-<t>.sock` and log `/tmp/cmux-debug-<t>.log`. Each tag has its own settings, socket and data, so it runs next to other cmux apps. It calls `ensure-ghosttykit.sh`. Fork: it sets `CMUX_ZIG` to a private Zig 0.16.0. |
| `scripts/install-personal.sh [--no-build] [--no-open]` | Runs `reload.sh --tag mine` (local backend, cloud off). It quits the running copy, rsyncs to `~/Applications/cmux Personal.app`, renames it to "cmux Personal", re-signs it ad hoc, and opens it. Bundle id `com.cmuxterm.app.debug.mine`, socket `/tmp/cmux-debug-mine.sock`. |
| `scripts/build-app-bundled-resources.sh` | An Xcode build phase. It copies Ghostty resources, terminfo, shell integration, helper binaries and `Resources/sidebars` into the app bundle. |
| `scripts/ensure-ghosttykit.sh` | Gets the GhosttyKit.xcframework that matches the `ghostty/` submodule commit. |

## 9. Where to change what

| Change | Look in |
|---|---|
| Workspace create/close/select/reorder | `Sources/TabManager.swift`, `Packages/macOS/CmuxWorkspaces` |
| Splits, pane behavior, surfaces in a workspace | `Sources/Workspace.swift` (`newTerminalSplit`, `newBrowserSplit`, …), `vendor/bonsplit` |
| Add a new surface type | `Sources/Panels/Panel.swift` (`PanelType`), new `*Panel.swift`, `PanelContentView.swift` |
| Terminal behavior / Ghostty action handling | `Sources/GhosttyTerminalView.swift` (`handleAction`), `Packages/macOS/CmuxTerminal` |
| Terminal env vars for child shells | `CmuxTerminal/.../Spawn/TerminalSurface+StartupEnvironment.swift` |
| Default left sidebar look (fork) | `Resources/sidebars/compact.js` |
| Your own sidebar without rebuilding | `~/.config/cmux/sidebars/<name>.js` |
| Sidebar selection/discovery logic | `Sources/CmuxExtensionSidebarSelection.swift` |
| Built-in Swift sidebar | `VerticalTabsSidebar` in `Sources/ContentView.swift`, `Sources/Sidebar/` |
| Right sidebar modes / file explorer | `Sources/RightSidebarMode.swift`, `RightSidebarPanelView.swift`, `FileExplorer*.swift` |
| Command palette commands | `ContentView.swift` (`commandPaletteCommandContributions`, `registerCommandPaletteHandlers`), `ContentView+*CommandPalette.swift` |
| ⌘P switcher rows/order | `ContentView.swift` (`commandPaletteSwitcherEntries`, `commandPaletteOrderedSwitcherWorkspaces`), `CmuxCommandPalette/.../CommandPaletteWorkspaceOrdering.swift` |
| Palette row rendering | `ContentView.swift` (`commandPaletteRenderResultLabelContent`), `Sources/CommandPalette/CommandPaletteOverlay.swift` |
| Unread/notification rules | `Sources/TerminalNotificationStore.swift` |
| Agent hook install/events | `CLI/CMUXCLI+AgentHookCatalog.swift`, `CLI/CMUXCLI+AgentHook*.swift` |
| New socket method | `Sources/TerminalController.swift` (v2 `switch`) or `TerminalController+<Domain>.swift`; `CmuxControlSocket/.../Coordinator`; list it in `TerminalController+Capabilities.swift` |
| New CLI subcommand | `CLI/cmux.swift` (the command `switch` near `case "claude-hook":`), `CLI/CMUXCLI+*.swift` |
| New setting | the matching `CmuxSettings/.../Keys/*CatalogSection.swift`, and a row in `CmuxSettingsUI/.../Sections/` |
| Keyboard shortcut default | `CmuxSettings/.../Values/ShortcutAction+Defaults.swift`, `Sources/KeyboardShortcutSettings.swift` |
| Menu bar items | `Sources/cmuxApp.swift` (+ `cmuxApp+*.swift`) |
| Fork-wide defaults | `Sources/CmuxMain.swift` (`installPersonalDefaults`) |
| Files bundled into the app | `scripts/build-app-bundled-resources.sh`, `Resources/` |
