#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
# Replacing a running executable leaves macOS checking the old process identity.
if pgrep -x DockTide >/dev/null 2>&1; then
    printf '%s\n' 'Quit DockTide from its menu before building an update.' >&2
    exit 1
fi
SIGNING_IDENTITY=${DOCKTIDE_SIGNING_IDENTITY:--}
if [ "$SIGNING_IDENTITY" = '-' ]; then
    printf '%s\n' 'Warning: ad-hoc signing changes the app identity on every code update.' \
        'Existing Accessibility/Automation entries may need to be removed and granted again.' \
        'Set DOCKTIDE_SIGNING_IDENTITY to a code-signing certificate to preserve identity between builds.' >&2
else
    # Fail before replacing the previous app if the chosen certificate is unavailable.
    if ! security find-identity -v -p codesigning | /usr/bin/grep -F -- "$SIGNING_IDENTITY" >/dev/null; then
        printf 'Code-signing identity not found: %s\n' "$SIGNING_IDENTITY" >&2
        exit 1
    fi
fi
swift build -c release --product DockTide "$@"
BIN_DIR=$(swift build -c release --product DockTide "$@" --show-bin-path)
APP="dist/DockTide.app"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/DockTide" "$APP/Contents/MacOS/DockTide"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"
