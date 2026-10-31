#!/usr/bin/env bash
# Build the personal cmux and install it as ~/Applications/cmux Personal.app.
#
# Usage: ./scripts/install-personal.sh [--no-build] [--no-open]
#   --no-build  install the last build without rebuilding
#   --no-open   don't launch the app afterwards
#
# It is the tagged debug build ("cmux DEV mine", bundle id
# com.cmuxterm.app.debug.mine) renamed to "cmux Personal". It runs next to the
# official cmux and keeps its own settings, socket and data.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="mine"
APP_NAME="cmux Personal"
BUILT_APP="$HOME/Library/Developer/Xcode/DerivedData/cmux-${TAG}/Build/Products/Debug/cmux DEV ${TAG}.app"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/${APP_NAME}.app"
BUNDLE_ID="com.cmuxterm.app.debug.${TAG}"

build=1
open_app=1
for arg in "$@"; do
  case "$arg" in
    --no-build) build=0 ;;
    --no-open) open_app=0 ;;
    -h|--help) sed -n 2,10p "$0"; exit 0 ;;
    *) echo "error: unknown option: $arg" >&2; exit 1 ;;
  esac
done

if [[ "$build" -eq 1 ]]; then
  (cd "$REPO_ROOT" && CMUX_DEV_BACKEND_MODE=local CMUX_DEV_CLOUD_ENABLED=0 \
    ./scripts/reload.sh --tag "$TAG" --no-global-cli-links)
fi
[[ -d "$BUILT_APP" ]] || { echo "error: no build at $BUILT_APP" >&2; exit 1; }

# Quit the running copy (installed or straight from the build folder); both use
# the same bundle id and socket.
if pgrep -f "/Contents/MacOS/cmux DEV" >/dev/null 2>&1 \
   && osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null | grep -q true; then
  echo "==> Quitting running ${APP_NAME}"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null | grep -q true || break
    sleep 0.5
  done
fi

echo "==> Installing to $DEST_APP"
mkdir -p "$DEST_DIR"
rsync -a --delete "$BUILT_APP/" "$DEST_APP/"

plist="$DEST_APP/Contents/Info.plist"
for key in CFBundleName CFBundleDisplayName; do
  /usr/libexec/PlistBuddy -c "Set :$key $APP_NAME" "$plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$key string $APP_NAME" "$plist"
done

# Editing Info.plist breaks the outer signature; re-sign it ad hoc and keep the
# entitlements the build gave it. Nested helpers keep their own signatures.
/usr/bin/codesign --force --sign - --timestamp=none \
  --preserve-metadata=entitlements,requirements,flags "$DEST_APP"
/usr/bin/codesign --verify --deep "$DEST_APP"

/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST_APP" >/dev/null 2>&1 || true

echo "==> Installed ${APP_NAME}"
if [[ "$open_app" -eq 1 ]]; then
  open "$DEST_APP"
fi
