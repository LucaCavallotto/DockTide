# DockTide

A lightweight macOS menu bar app that hides the original Dock when windows need its space and brings it back when the area is free. Move the pointer to the bottom edge to reveal it temporarily.

Filled windows can extend into the space normally reserved for the Dock.

Requires macOS 13 or later, a single display, and the Dock positioned at the bottom.

## Build

With Xcode or Apple's Command Line Tools installed:

```sh
./scripts/build-app.sh
open dist/DockTide.app
```

## Use

1. Open the waves icon in the menu bar and choose **Grant Accessibility Permission…**.
2. Enable DockTide in **System Settings → Privacy & Security → Accessibility**.
3. Choose **Enable DockTide** and allow control of **System Events** when prompted.

Move windows normally, or drag one to the top edge to fill the desktop. **Pause DockTide** and **Quit DockTide** restore your original Dock auto-hide setting.

Quit the app before rebuilding. Locally signed updates may require removing and re-adding DockTide in Accessibility settings.

## Disclaimer

DockTide is an experimental prototype, not a production-ready release. It requires broad Accessibility permissions; compatibility, resource usage and recovery after failures have not been fully validated. A crash or force quit may leave Dock auto-hide changed. Review the source and use at your own risk. Locally built apps are not notarized by Apple.
