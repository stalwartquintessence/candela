import AppKit
import ApplicationServices
import MonitorCore
import MonitorIO
import ServiceManagement

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// Candela runs in the background without a Dock or menu bar icon. Its controls live in one
/// window, shown when the user opens Candela (and again whenever they reopen it), but not when
/// macOS starts it at login.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let gamma = GammaDimmer()
    private let hud = HUD()
    private let keyTap = MediaKeyTap()
    private let model = AppModel()
    private let updates = UpdateChecker()
    private var controlsWindow: ControlsWindowController?
    private var accessibilityTimer: Timer?
    private var lastTrusted: Bool?
    private var pendingReconfigure: DispatchWorkItem?

    private var controllers: [DisplayController] {
        get { model.controllers }
        set { model.controllers = newValue }
    }

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let startedAtLogin = Self.launchedAsLoginItem

        // Start from the user's ColorSync gamma in case another tool left a display dimmed.
        gamma.restoreAll()
        NSApp.mainMenu = Self.makeMainMenu()

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        refreshDisplays()

        keyTap.handler = { [weak self] key, fine, isDown in
            self?.handleKey(key, fine: fine, isDown: isDown) ?? false
        }
        startKeyTap()
        updates.onBusyChange = { [weak self] busy in self?.model.isCheckingForUpdates = busy }
        updates.start()
        refreshSettings()
        if !startedAtLogin { showControls() }
        Log.app("Candela \(AppVersion.string) started\(startedAtLogin ? " at login" : "") with \(controllers.count) external display(s)")
    }

    /// Opening Candela while it is already running shows its window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls()
        return false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Launch at Login and the Accessibility permission can change in System Settings.
        refreshSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        gamma.restoreAll()
    }

    /// True when macOS opened Candela as a login item, so it starts quietly in the background.
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }

    /// The menu bar stays hidden for a background app, but its key equivalents still work:
    /// Command-W closes a window and Command-Q quits.
    private static func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Candela", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let main = NSMenu()
        for submenu in [appMenu, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }

    // MARK: Window

    private func showControls() {
        if controlsWindow == nil {
            controlsWindow = ControlsWindowController(model: model, actions: ControlsActions(
                setLaunchAtLogin: { [weak self] on in self?.setLaunchAtLogin(on) },
                setAutomaticUpdateChecks: { [weak self] on in
                    self?.updates.setAutomatic(on)
                    self?.model.checksForUpdatesAutomatically = on
                },
                enableBrightnessKeys: { [weak self] in self?.openAccessibilitySettings() },
                redetect: { [weak self] in self?.redetect() },
                checkForUpdates: { [weak self] in self?.updates.checkNow() },
                about: { [weak self] in self?.showAbout() }))
        }
        // A window that was closed opens again on its main page.
        if controlsWindow?.window?.isVisible != true { model.infoDisplay = nil }
        refreshSettings()
        controlsWindow?.present()
    }

    private func refreshSettings() {
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.checksForUpdatesAutomatically = updates.isAutomatic
        model.brightnessKeysEnabled = AXIsProcessTrusted()
    }

    // MARK: Displays

    /// Match currently connected displays to existing controllers. A controller is reused only when
    /// the same monitor is on the same connection, so switching cables triggers a fresh DDC probe.
    /// macOS can renumber a display after sleep or reconnection, so a matching display ID is
    /// preferred but not required.
    private func refreshDisplays() {
        let found = DisplayDiscovery.externalDisplays()
        let screens = NSScreen.screens
        var next: [DisplayController] = []
        var fresh: [DisplayController] = []

        for display in found {
            let name = screens.first { $0.displayID == display.displayID }?.localizedName ?? display.name
            let matches = controllers.filter { c in
                !next.contains { $0 === c } && Self.sameConnection(c.display, display)
            }
            if let existing = matches.first(where: { $0.displayID == display.displayID }) ?? matches.first {
                existing.update(display: display, name: name)
                next.append(existing)
            } else {
                let controller = DisplayController(display: display, name: name, gamma: gamma)
                next.append(controller)
                fresh.append(controller)
            }
        }

        for old in controllers where !next.contains(where: { $0 === old }) {
            gamma.restore(old.displayID)
        }
        // Leave Display Info when its display is gone.
        if let shown = model.infoDisplay, !next.contains(where: { $0 === shown }) {
            model.infoDisplay = nil
        }
        controllers = next
        fresh.forEach { $0.probe() }
        Log.app("displays: \(controllers.map(\.name).joined(separator: ", ")) (\(fresh.count) new)")
    }

    private static func sameConnection(_ a: ExternalDisplay, _ b: ExternalDisplay) -> Bool {
        a.settingsKey == b.settingsKey
            && a.avService?.edidUUID == b.avService?.edidUUID
            && a.avService?.transportUpstream == b.avService?.transportUpstream
            && a.avService?.transportDownstream == b.avService?.transportDownstream
            && a.hasDDCService == b.hasDDCService
    }

    @objc private func screensChanged() {
        // Reconfiguration sends bursts of notifications; act once things settle.
        pendingReconfigure?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refreshDisplays()
            self.reapplyDimming()
        }
        pendingReconfigure = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    @objc private func didWake() {
        // macOS restores ColorSync gamma on wake, which would undo software dimming.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.reapplyDimming() }
    }

    private func reapplyDimming() {
        gamma.restoreAll()
        controllers.forEach { $0.applySoftwareDimming() }
    }

    private func redetect() {
        controllers.forEach { gamma.restore($0.displayID) }
        controllers.removeAll()
        refreshDisplays()
    }

    // MARK: Brightness keys

    /// Watches for the Accessibility permission and starts the key tap once it is granted.
    /// macOS is asked to show its permission dialog only once ever (first launch); after that the
    /// window offers a button for it, so relaunching never nags.
    private func startKeyTap() {
        let askedKey = "didRequestAccessibilityOnce"
        if !AXIsProcessTrusted(), !UserDefaults.standard.bool(forKey: askedKey) {
            UserDefaults.standard.set(true, forKey: askedKey)
            requestAccessibility()
        }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            let trusted = AXIsProcessTrusted()
            if trusted != self.lastTrusted {
                Log.app("Accessibility permission: \(trusted ? "granted" : "not granted")")
                self.lastTrusted = trusted
                self.model.brightnessKeysEnabled = trusted
            }
            if trusted, self.keyTap.start() {
                Log.app("Brightness key tap started")
                timer.invalidate()
            }
        }
        accessibilityTimer?.fire()
    }

    /// Returns true when the key was handled (and should not reach macOS).
    private func handleKey(_ key: MediaKeyTap.Key, fine: Bool, isDown: Bool) -> Bool {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              let controller = controllers.first(where: { $0.displayID == screen.displayID }) else {
            return false // the built-in display: let macOS handle it
        }
        if isDown {
            let level = BrightnessMath.step(from: controller.brightness, up: key == .brightnessUp, fine: fine)
            controller.setBrightness(level)
            hud.show(level: level, name: controller.name, on: screen)
        }
        return true
    }

    /// Shows macOS's own permission dialog, which also adds Candela to the Accessibility list.
    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func openAccessibilitySettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Settings

    private func setLaunchAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        defer { refreshSettings() }
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            Log.error("Launch at login change failed: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove Candela to the Applications folder and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        // macOS can accept the login item but leave it switched off until the user approves it.
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Brightness, contrast, saturation, picture modes and volume for external displays.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
