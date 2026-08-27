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

/// Identifies one menu choice for a picker (Picture Mode, Color Preset).
private final class PickerChoice: NSObject {
    let controller: DisplayController
    let code: UInt8
    let value: UInt16
    init(controller: DisplayController, code: UInt8, value: UInt16) {
        self.controller = controller
        self.code = code
        self.value = value
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let gamma = GammaDimmer()
    private let hud = HUD()
    private let keyTap = MediaKeyTap()
    private var statusItem: NSStatusItem!
    private var controllers: [DisplayController] = []
    private var infoWindows: [ObjectIdentifier: InfoWindowController] = [:]
    private var accessibilityTimer: Timer?
    private var lastTrusted: Bool?
    private var pendingReconfigure: DispatchWorkItem?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start from the user's ColorSync gamma in case another tool left a display dimmed.
        gamma.restoreAll()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Candela")
        statusItem.button?.toolTip = "Candela"
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

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
        Log.app("Candela \(AppVersion.string) started with \(controllers.count) external display(s)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        gamma.restoreAll()
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
                controller.onChange = { [weak self, weak controller] in
                    guard let self, let controller else { return }
                    self.infoWindows[ObjectIdentifier(controller)]?.refresh()
                }
                next.append(controller)
                fresh.append(controller)
            }
        }

        for old in controllers where !next.contains(where: { $0 === old }) {
            gamma.restore(old.displayID)
            infoWindows.removeValue(forKey: ObjectIdentifier(old))?.close()
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

    // MARK: Brightness keys

    /// Watches for the Accessibility permission and starts the key tap once it is granted.
    /// macOS is asked to show its permission dialog only once ever (first launch); after that the
    /// menu offers "Enable Brightness Keys", so relaunching never nags.
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
            hud.show(level: level, on: screen)
        }
        return true
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if controllers.isEmpty {
            let item = NSMenuItem(title: "No external displays connected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        for (index, controller) in controllers.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            addControls(for: controller, to: menu)
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Re-detect Displays", #selector(redetect)))
        if !AXIsProcessTrusted() {
            menu.addItem(actionItem("Enable Brightness Keys (Accessibility)...", #selector(openAccessibilitySettings)))
        }
        let login = actionItem("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(actionItem("About Candela", #selector(showAbout)))
        menu.addItem(NSMenuItem(title: "Quit Candela", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func addControls(for c: DisplayController, to menu: NSMenu) {
        let plan = c.plan
        menu.addItem(viewItem(HeaderRow(title: c.name, status: plan.statusLine, tooltip: c.status.advice)))
        menu.addItem(viewItem(SliderRow(title: "Brightness", symbol: "sun.max", value: c.brightness) { [weak c] value in
            c?.setBrightness(value)
        }))
        for code in plan.sliders {
            menu.addItem(viewItem(SliderRow(title: MCCS.name(of: code), symbol: Self.symbol(for: code), value: c.percent(of: code)) { [weak c] value in
                c?.set(code: code, percent: value)
            }))
        }

        // The monitor's own preset modes, exactly as it lists them.
        for picker in plan.pickers {
            menu.addItem(pickerMenu(picker, controller: c))
        }

        let info = actionItem("Display Info...", #selector(showInfo(_:)))
        info.representedObject = c
        menu.addItem(info)
    }

    private func pickerMenu(_ picker: ControlPlan.Picker, controller: DisplayController) -> NSMenuItem {
        let submenu = NSMenu()
        for value in picker.values {
            submenu.addItem(choiceItem(MCCS.valueName(code: picker.code, value: value), code: picker.code, value: value,
                                       controller: controller))
        }
        let item = NSMenuItem(title: MCCS.name(of: picker.code), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    private func choiceItem(_ title: String, code: UInt8, value: UInt16, controller: DisplayController) -> NSMenuItem {
        let item = actionItem(title, #selector(choose(_:)))
        item.representedObject = PickerChoice(controller: controller, code: code, value: value)
        item.state = MCCS.isSameChoice(controller.currentValue(of: code), value) ? .on : .off
        return item
    }

    private func actionItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private static func symbol(for code: UInt8) -> String {
        switch code {
        case MCCS.contrast: return "circle.lefthalf.filled"
        case MCCS.saturation: return "drop.halffull"
        case MCCS.volume: return "speaker.wave.2"
        default: return "slider.horizontal.3"
        }
    }

    // MARK: Menu actions

    @objc private func choose(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? PickerChoice else { return }
        choice.controller.set(code: choice.code, value: choice.value)
    }

    @objc private func showInfo(_ sender: NSMenuItem) {
        guard let controller = sender.representedObject as? DisplayController else { return }
        let key = ObjectIdentifier(controller)
        let window = infoWindows[key] ?? InfoWindowController(controller: controller)
        infoWindows[key] = window
        window.present()
    }

    @objc private func redetect() {
        controllers.forEach { gamma.restore($0.displayID) }
        controllers.removeAll()
        infoWindows.values.forEach { $0.close() }
        infoWindows.removeAll()
        refreshDisplays()
    }

    /// Shows macOS's own permission dialog, which also adds Candela to the Accessibility list.
    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func openAccessibilitySettings() {
        requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
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

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let credits = NSAttributedString(
            string: "Brightness, contrast, saturation, picture modes and volume for external displays.\n\nDDC/CI timing and display matching adapted from MonitorControl (MIT License).",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }
}
