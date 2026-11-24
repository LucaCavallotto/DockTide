import AppKit
import ApplicationServices
import DockTideCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let status = NSMenuItem(title: "Paused", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "Enable DockTide", action: #selector(toggleActive), keyEquivalent: "")
    private let monitor = WindowMonitor()
    private let control = DockControl()
    private var lastFillAttempt: Geometry.FillRequest?
    private var pendingFill: Geometry.FillRequest?
    private var fillReadyAt: TimeInterval = 0
    private var reservedWorkArea: CGRect?
    private var lastScreenBounds: CGRect?
    private var baseline: Bool?
    private var current: Bool?
    private var active = false
    private var busy = false
    private var quitting = false
    private let recoveryKey = "originalDockAutohide"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "water.waves", accessibilityDescription: "DockTide")
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        menu.addItem(NSMenuItem(title: "DockTide \(version)", action: nil, keyEquivalent: ""))
        menu.addItem(status)
        menu.addItem(.separator())
        toggle.target = self
        menu.addItem(toggle)
        let permissions = NSMenuItem(title: "Grant Accessibility Permission…", action: #selector(requestPermission), keyEquivalent: "")
        permissions.target = self
        menu.addItem(permissions)
        menu.addItem(.separator())
        let diagnostics = NSMenuItem(title: "Copy Diagnostics", action: #selector(copyDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit DockTide", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        Diagnostics.record("Started paused; displays=\(NSScreen.screens.count); workArea=\(String(describing: Geometry.workArea()))")
        monitor.onChange = { [weak self] in self?.evaluate() }
        monitor.onWindowSettled = { [weak self] in
            guard let self, self.active else { return }
            self.monitor.resizedWindow = Geometry.focusedWindow()
            self.evaluate()
        }
        if let saved = UserDefaults.standard.object(forKey: recoveryKey) as? Bool {
            baseline = saved
            restore()
        }
    }

    @objc private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func toggleActive() {
        guard !busy else { return }
        if active {
            active = false
            monitor.stop()
            pendingFill = nil
            toggle.title = "Enable DockTide"
            restore()
            return
        }
        guard AXIsProcessTrusted() else { requestPermission(); status.title = "Accessibility permission needed"; return }
        busy = true
        control.run("get autohide") { [weak self] result in
            guard let self else { return }
            self.busy = false
            switch result {
            case .success(let value):
                if self.baseline == nil { self.baseline = value }
                UserDefaults.standard.set(self.baseline!, forKey: self.recoveryKey)
                self.current = value
                Diagnostics.record("Enabled; initial auto-hide=\(value)")
                if self.quitting { self.restore(); return }
                self.active = true
                self.toggle.title = "Pause DockTide"
                self.monitor.start()
            case .failure(let error): self.fail(error)
            }
        }
    }

    private func evaluate() {
        guard active, !busy else {
            if active && monitor.resizedWindow != nil { Diagnostics.record("Fill check deferred: Dock control in flight") }
            return
        }
        let preferences = UserDefaults.standard.persistentDomain(forName: "com.apple.dock") ?? [:]
        guard NSScreen.screens.count == 1, (preferences["orientation"] as? String ?? "bottom") == "bottom" else {
            pendingFill = nil
            lastFillAttempt = nil
            reservedWorkArea = nil
            monitor.resizedWindow = nil
            Diagnostics.record("Unsupported configuration: displays=\(NSScreen.screens.count), orientation=\(preferences["orientation"] ?? "bottom")")
            status.title = "Requires one display and bottom Dock"
            setHidden(baseline ?? false)
            return
        }
        let screenBounds = CGDisplayBounds(CGMainDisplayID())
        if lastScreenBounds != screenBounds {
            lastFillAttempt = nil
            lastScreenBounds = screenBounds
            reservedWorkArea = nil
            pendingFill = nil
        }
        if let area = Geometry.workArea(), screenBounds.maxY - area.maxY > 20 {
            reservedWorkArea = area
        }
        guard AXIsProcessTrusted(), let dock = Geometry.dockRect(), let windows = Geometry.visibleWindows() else {
            Diagnostics.record("Evaluation blocked: Dock/window geometry unavailable; trusted=\(AXIsProcessTrusted())")
            status.title = "Cannot read Dock/window geometry"
            setHidden(baseline ?? false)
            return
        }
        if let request = pendingFill {
            let remaining = fillReadyAt - ProcessInfo.processInfo.systemUptime
            if remaining > 0 {
                monitor.schedule(after: remaining)
                return
            }
            pendingFill = nil
            if current == true { request.apply() }
            // Re-read window geometry after the resize, rather than using the old snapshot.
            monitor.schedule()
            return
        }
        if let resized = monitor.resizedWindow {
            monitor.resizedWindow = nil
            let request = Geometry.fillRequest(for: resized, reservedWorkArea: reservedWorkArea)
            if request == nil { lastFillAttempt = nil }
            if let request, lastFillAttempt.map({ request.hasSameSource(as: $0) }) != true {
                // Some apps emit another resize notification even when rejecting our request.
                // Never keep retrying the same unchanged window geometry.
                lastFillAttempt = request
                pendingFill = request
                fillReadyAt = ProcessInfo.processInfo.systemUptime + 0.4
                status.title = "Active · expanding filled window"
                if current == true { monitor.schedule(after: 0.4) }
                else { setHidden(true) }
                return
            }
        }
        let hidden = Overlap.requiresHiding(dock: dock, windows: windows)
        status.title = hidden ? "Active · Dock auto-hides" : "Active · Dock stays visible"
        setHidden(hidden)
    }

    private func setHidden(_ hidden: Bool) {
        guard !busy, current != hidden else { return }
        busy = true
        control.run("set autohide to \(hidden ? "true" : "false")") { [weak self] result in
            guard let self else { return }
            self.busy = false
            switch result {
            case .success:
                self.current = hidden
                Diagnostics.record("Dock auto-hide set to \(hidden)")
                if self.quitting || !self.active { self.restore() }
                else { self.monitor.schedule() }
            case .failure(let error): self.fail(error)
            }
        }
    }

    private func restore() {
        guard !busy else { return }
        guard let baseline else { if quitting { NSApp.reply(toApplicationShouldTerminate: true) }; return }
        busy = true
        control.run("set autohide to \(baseline ? "true" : "false")") { [weak self] result in
            guard let self else { return }
            self.busy = false
            switch result {
            case .success:
                self.current = baseline
                self.baseline = nil
                UserDefaults.standard.removeObject(forKey: self.recoveryKey)
                self.status.title = "Paused · original setting restored"
                if self.quitting { NSApp.reply(toApplicationShouldTerminate: true) }
            case .failure(let error): self.fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        active = false
        pendingFill = nil
        monitor.stop()
        toggle.title = "Enable DockTide"
        status.title = "Control failed · try enabling again"
        let alert = NSAlert()
        alert.messageText = "DockTide could not control the Dock"
        alert.informativeText = error.localizedDescription + "\nCheck Privacy & Security → Automation. Your original setting is retained for recovery on next launch."
        alert.runModal()
        if quitting { NSApp.reply(toApplicationShouldTerminate: true) }
    }

    @objc private func copyDiagnostics() {
        Diagnostics.record("Snapshot active=\(active); busy=\(busy); auto-hide=\(String(describing: current)); screen=\(CGDisplayBounds(CGMainDisplayID())); workArea=\(String(describing: Geometry.workArea())); reserved=\(String(describing: reservedWorkArea))")
        if let focused = Geometry.focusedWindow() {
            _ = Geometry.fillRequest(for: focused, reservedWorkArea: reservedWorkArea)
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Diagnostics.report(), forType: .string)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitting = true
        active = false
        pendingFill = nil
        monitor.stop()
        if baseline == nil && !busy { return .terminateNow }
        restore()
        return .terminateLater
    }
}
