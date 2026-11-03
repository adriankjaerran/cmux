#!/usr/bin/env bash
# Build and open the test app ("cmux DEV test") next to cmux Personal.
#
# Usage: ./scripts/test-app.sh [--seed] [--no-build] [--no-open]
#   --seed      copy cmux Personal's saved workspaces/groups into the test app
#               first (overwrites the test app's own saved layout)
#   --no-build  reopen the last test build
#   --no-open   build only
#
# The test app has its own bundle id (com.cmuxterm.app.debug.test), socket
# (/tmp/cmux-debug-test.sock) and saved data, so it can't touch cmux Personal.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="test"
BUNDLE_ID="com.cmuxterm.app.debug.${TAG}"
BUILT_APP="$HOME/Library/Developer/Xcode/DerivedData/cmux-${TAG}/Build/Products/Debug/cmux DEV ${TAG}.app"
SUPPORT="$HOME/Library/Application Support/cmux"
PERSONAL_SESSION="$SUPPORT/session-com.cmuxterm.app.debug.mine.json"
TEST_SESSION="$SUPPORT/session-${BUNDLE_ID}.json"

build=1
open_app=1
seed=0
for arg in "$@"; do
  case "$arg" in
    --seed) seed=1 ;;
    --no-build) build=0 ;;
    --no-open) open_app=0 ;;
    -h|--help) sed -n 2,12p "$0"; exit 0 ;;
    *) echo "error: unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$build" -eq 1 ]]; then
  (cd "$REPO_ROOT" && ./scripts/reload.sh --tag "$TAG" --no-global-cli-links)
fi
[[ -d "$BUILT_APP" ]] || { echo "error: no build at $BUILT_APP" >&2; exit 1; }

# Quit a running test app so the new build (and a seeded session) is picked up.
if osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null | grep -q true; then
  echo "==> Quitting running test app"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null | grep -q true || break
    sleep 0.5
  done
fi

if [[ "$seed" -eq 1 ]]; then
  [[ -f "$PERSONAL_SESSION" ]] || { echo "error: no saved layout at $PERSONAL_SESSION" >&2; exit 1; }
  echo "==> Copying cmux Personal's saved layout into the test app"
  cp "$PERSONAL_SESSION" "$TEST_SESSION"
fi

echo "==> Test app: $BUILT_APP"
if [[ "$open_app" -eq 1 ]]; then
  # Don't hand cmux Personal's CMUX_* environment (tag, socket, URL scheme) to the test app
  # when this runs from a Personal terminal.
  env $(env | awk -F= '/^CMUX_/{print "-u " $1}') open "$BUILT_APP"
fi
