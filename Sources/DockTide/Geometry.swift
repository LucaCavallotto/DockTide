import AppKit
import ApplicationServices
import DockTideCore

struct Geometry {

    struct FillRequest {
        let window: AXUIElement
        let original: CGRect
        let target: CGRect

        func hasSameSource(as other: FillRequest) -> Bool {
            CFEqual(window, other.window) && original == other.original && target == other.target
        }

        func apply() {
            // The user may move, minimize or replace the window during the Dock transition.
            guard Geometry.isFocusedNormalWindow(window), let now = Geometry.frame(window),
                  abs(now.minX - original.minX) < 2, abs(now.minY - original.minY) < 2,
                  abs(now.width - original.width) < 2, abs(now.height - original.height) < 2 else {
                Diagnostics.record("Resize cancelled: focus or geometry changed")
                return
            }
            var size = target.size
            guard let value = AXValueCreate(.cgSize, &size) else { return }
            let result = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
            Diagnostics.record("Set window size to \(target.size): AXError=\(result.rawValue); immediate frame=\(String(describing: Geometry.frame(window)))")
        }
    }

    private static func frame(_ window: AXUIElement) -> CGRect? {
        guard let point: CGPoint = attribute(window, kAXPositionAttribute, type: .cgPoint),
              let size: CGSize = attribute(window, kAXSizeAttribute, type: .cgSize) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func isFocusedNormalWindow(_ window: AXUIElement) -> Bool {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            Diagnostics.record("Fill rejected: window is not in frontmost app")
            return false
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused, CFEqual(window, focused) else {
            Diagnostics.record("Fill rejected: focused window unavailable or changed")
            return false
        }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &role)
        guard role as? String == kAXStandardWindowSubrole else {
            Diagnostics.record("Fill rejected: subrole=\(String(describing: role))")
            return false
        }
        for key in [kAXMinimizedAttribute, "AXFullScreen"] {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(window, key as CFString, &value)
            if value as? Bool == true {
                Diagnostics.record("Fill rejected: \(key)=true")
                return false
            }
        }
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
        if result != .success || !settable.boolValue {
            Diagnostics.record("Fill rejected: size settable=\(settable.boolValue), AXError=\(result.rawValue)")
        }
        return result == .success && settable.boolValue
    }

    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.2)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            Diagnostics.record("No focused Accessibility window")
            return nil
        }
        return (value as! AXUIElement)
    }

    static func workArea() -> CGRect? {
        guard let screen = NSScreen.screens.first else { return nil }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        let visible = screen.visibleFrame
        // AppKit uses bottom-left origin; Accessibility uses top-left origin.
        return CGRect(x: visible.minX, y: bounds.maxY - visible.maxY,
                      width: visible.width, height: visible.height)
    }

    static func fillRequest(for window: AXUIElement, reservedWorkArea: CGRect?) -> FillRequest? {
        guard let original = frame(window), let liveWorkArea = workArea() else {
            Diagnostics.record("Fill unavailable: cannot read window/work area")
            return nil
        }
        Diagnostics.record("Fill input window=\(original); live=\(liveWorkArea); reserved=\(String(describing: reservedWorkArea)); mouseButtons=\(NSEvent.pressedMouseButtons)")
        guard isFocusedNormalWindow(window) else { return nil }
        let bounds = CGDisplayBounds(CGMainDisplayID())
        // During the top-edge drag the Dock can already have hidden, changing visibleFrame.
        guard let target = FillExpansion.target(window: original, liveWorkArea: liveWorkArea,
                                              reservedWorkArea: reservedWorkArea, screen: bounds) else {
            Diagnostics.record("Fill rejected: geometry does not match work area; screen=\(bounds)")
            return nil
        }
        Diagnostics.record("Fill recognized; target=\(target)")
        return FillRequest(window: window, original: original, target: target)
    }

    static func dockRect() -> CGRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        guard let list = findList(root, depth: 0),
              let size: CGSize = attribute(list, kAXSizeAttribute, type: .cgSize),
              let position: CGPoint = attribute(list, kAXPositionAttribute, type: .cgPoint) else { return nil }
        let screen = CGDisplayBounds(CGMainDisplayID())
        guard size.width > 10, size.height > 10, size.width <= screen.width, size.height < screen.height / 3 else { return nil }
        // A hidden Dock moves beyond the edge. Anchor its resting size to the screen.
        return CGRect(x: max(screen.minX, min(position.x, screen.maxX - size.width)),
                      y: screen.maxY - size.height, width: size.width, height: size.height)
    }

    private static func findList(_ element: AXUIElement, depth: Int) -> AXUIElement? {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if role as? String == kAXListRole { return element }
        guard depth < 3 else { return nil }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        for child in children as? [AXUIElement] ?? [] {
            if let list = findList(child, depth: depth + 1) { return list }
        }
        return nil
    }

    private static func attribute<T>(_ element: AXUIElement, _ key: String, type: AXValueType) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            Diagnostics.record("Cannot read AX geometry attribute \(key)")
            return nil
        }
        let ax = value as! AXValue
        if type == .cgSize {
            var size = CGSize.zero
            return AXValueGetValue(ax, type, &size) ? size as? T : nil
        }
        var point = CGPoint.zero
        return AXValueGetValue(ax, type, &point) ? point as? T : nil
    }

    static func visibleWindows() -> [CGRect]? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let pids = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isHidden }.map(\.processIdentifier))
        return list.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pids.contains(pid),
                  pid != ProcessInfo.processInfo.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 1, rect.height > 1 else { return nil }
            return rect
        }
    }
}
