import AppKit
import ApplicationServices

private func windowEvent(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Diagnostics.record("AX notification: \(notification)")
    let monitor = Unmanaged<WindowMonitor>.fromOpaque(context).takeUnretainedValue()
    if [kAXWindowResizedNotification, kAXWindowMovedNotification,
        kAXResizedNotification, kAXMovedNotification].contains(notification as String) {
        monitor.waitForWindowToSettle()
    }
    monitor.schedule(refresh: ![kAXWindowMovedNotification, kAXWindowResizedNotification, kAXMovedNotification, kAXResizedNotification].contains(notification as String))
}

final class WindowMonitor {
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var settling: DispatchWorkItem?
    private var running = false
    private var needsRefresh = true
    private var reportedSubscriptionErrors: Set<String> = []
    var resizedWindow: AXUIElement?
    var onChange: (() -> Void)?
    var onWindowSettled: (() -> Void)?

    func start() {
        guard !running else { return }
        running = true
        needsRefresh = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didWakeNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.schedule(refresh: true) })
        }
        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.schedule(refresh: true) })
        schedule()
    }

    func waitForWindowToSettle() {
        guard running else { return }
        settling?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            self.settling = nil
            Diagnostics.record("Window movement settled")
            self.onWindowSettled?()
        }
        settling = work
        // One trailing check, rather than inspecting an intermediate tiling animation frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func schedule(refresh: Bool = false, after delay: Double = 0.15) {
        guard running else { return }
        needsRefresh = needsRefresh || refresh
        guard pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            if self.needsRefresh {
                self.needsRefresh = false
                self.refreshObservers()
            }
            self.onChange?()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func refreshObservers() {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        let live = Set(apps.map(\.processIdentifier))
        for pid in Array(observers.keys) where !live.contains(pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observers.removeValue(forKey: pid)!), .commonModes)
        }
        for app in apps {
            let pid = app.processIdentifier
            let observer: AXObserver
            if let existing = observers[pid] { observer = existing }
            else {
                var created: AXObserver?
                let result = AXObserverCreate(pid, windowEvent, &created)
                Diagnostics.record("Observer pid=\(pid) result=\(result.rawValue)")
                guard result == .success, let created else { continue }
                observer = created
                observers[pid] = observer
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.2)
            let context = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
                AXObserverAddNotification(observer, element, name as CFString, context)
            }
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for window in windows {
                for name in [kAXWindowMovedNotification, kAXWindowResizedNotification, kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                             kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
                    let result = AXObserverAddNotification(observer, window, name as CFString, context)
                    if result != .success && result != .notificationAlreadyRegistered,
                       reportedSubscriptionErrors.insert("\(pid):\(name):\(result.rawValue)").inserted {
                        Diagnostics.record("Subscribe pid=\(pid) \(name): AXError=\(result.rawValue)")
                    }
                }
            }
        }
    }

    func stop() {
        running = false
        resizedWindow = nil
        settling?.cancel()
        settling = nil
        pending?.cancel()
        pending = nil
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observers.removeAll()
        reportedSubscriptionErrors.removeAll()
        for token in tokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            NotificationCenter.default.removeObserver(token)
        }
        tokens.removeAll()
    }
}
