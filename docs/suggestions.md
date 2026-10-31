# Suggestions

Short and ordered: most useful first.

1. **Stop the network calls first.** Turn off Sentry, PostHog and Sparkle before anything else. They send data to
   upstream or could offer to "update" this app to upstream's build.
2. **Stop downloading CodeRouter on every build.** Skip `install-coderouter-client.sh` in `reload.sh` unless you use it.
3. **Give the app its own identity.** Own bundle id (e.g. `no.datafabric.cmux`), app and process name, icon.
   Do it once, early: settings and saved sessions are stored per bundle id.
4. **Trim packages in small steps.** Remove one feature per commit (Computer Use, tunnel, Cloud, …), build, run, commit.
   Fewer packages means faster builds and less code to understand.
5. **Keep a small smoke test.** One script that builds, launches, runs `echo` in a terminal over the socket and opens ⌘P
   (the checks done by hand so far). Run it after every trim.
6. **Make your sidebar config one source.** `compact.js` exists in both `cmux-config` and this repo; a file in
   `~/.config/cmux/sidebars` overrides the built-in one. Pick one home for it.
7. **Persist the "done" times.** Finished-command times for ⌘P are kept in memory and reset on restart; save them
   with the session if that matters.
8. **Copy two upstream skills as docs.** `skills/cmux-architecture` and `skills/cmux-dev-workflow` in
   `~/Code/cmux_github` explain the codebase well.
9. **Track upstream on purpose.** Keep `~/Code/cmux_github` as the reference clone; pull and cherry-pick fixes
   by hand rather than merging.
10. **Fix the incremental-build link step upstream-style.** `reload.sh` re-links the CLI's resource bundles after
    the build as a workaround; the real cause is the order of Xcode build phases.
