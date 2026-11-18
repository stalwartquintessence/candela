import AppKit
import MonitorCore
import SwiftUI

/// Candela's menu bar icon: a brightness slider for each external display, and the way to the
/// window for everything else. It shows while the lid is closed, when the brightness keys on the
/// MacBook's keyboard are out of reach, or all the time if the user asks for it.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let controllers: () -> [DisplayController]
    private let openWindow: () -> Void
    private let removedByUser: () -> Void
    /// Made the first time the icon shows, then only hidden and shown again, so it keeps its place.
    private var statusItem: NSStatusItem?
    private var visibility: NSKeyValueObservation?
    /// True while Candela itself shows or hides the icon, so only the user's removal is reported.
    private var isChangingVisibility = false

    init(controllers: @escaping () -> [DisplayController], openWindow: @escaping () -> Void,
         removedByUser: @escaping () -> Void) {
        self.controllers = controllers
        self.openWindow = openWindow
        self.removedByUser = removedByUser
    }

    var isVisible: Bool { statusItem?.isVisible == true }

    func setVisible(_ visible: Bool) {
        if visible, statusItem == nil { statusItem = makeStatusItem() }
        if !visible { statusItem?.menu?.cancelTracking() }
        isChangingVisibility = true
        statusItem?.isVisible = visible
        isChangingVisibility = false
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "Candela"
        item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Candela")
        item.button?.toolTip = "Candela"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        // Command-dragging the icon out of the menu bar removes it, like Apple's own items.
        // AppKit then sets isVisible to false, and Candela takes that as the user's choice.
        item.behavior = .removalAllowed
        visibility = item.observe(\.isVisible) { [weak self] item, _ in
            guard let self, !self.isChangingVisibility, !item.isVisible else { return }
            self.removedByUser()
        }
        return item
    }

    // MARK: NSMenuDelegate

    /// Built each time it opens, so it lists the displays connected now.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let displays = controllers()
        if displays.isEmpty {
            let item = NSMenuItem(title: "No external displays connected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        // The same controls as the display's section in the window, from the same plan.
        for (index, controller) in displays.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            let sliders = NSHostingView(rootView: DisplayMenuSliders(controller: controller))
            sliders.frame.size = sliders.fittingSize
            let item = NSMenuItem()
            item.view = sliders
            menu.addItem(item)
            for picker in controller.plan.pickers {
                menu.addItem(pickerItem(picker, controller: controller))
            }
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Candela", action: #selector(openCandela), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
    }

    /// One of the monitor's own preset modes (Picture Mode, Color Preset) as a submenu of the
    /// choices it lists, with a checkmark on the current one.
    private func pickerItem(_ picker: ControlPlan.Picker, controller: DisplayController) -> NSMenuItem {
        let choices = NSMenu()
        let current = controller.currentValue(of: picker.code)
        for value in picker.values {
            let choice = NSMenuItem(title: MCCS.valueName(code: picker.code, value: value),
                                    action: #selector(choose(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = PickerChoice(controller: controller, code: picker.code, value: value)
            choice.state = MCCS.isSameChoice(current, value) ? .on : .off
            choices.addItem(choice)
        }
        let item = NSMenuItem(title: MCCS.name(of: picker.code), action: nil, keyEquivalent: "")
        item.submenu = choices
        return item
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? PickerChoice else { return }
        choice.controller.set(code: choice.code, value: choice.value)
    }

    @objc private func openCandela() {
        openWindow()
    }
}

/// One choice in a preset submenu.
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

/// The display's name above a system slider for Brightness and for each level control the
/// window shows (Contrast, Saturation, Volume), as one menu item view.
private struct DisplayMenuSliders: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(controller.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            MenuLevelRow(display: controller.name, code: MCCS.brightness,
                         value: Binding(get: { controller.brightness }, set: { controller.setBrightness($0) }))
            ForEach(controller.plan.sliders, id: \.self) { code in
                MenuLevelRow(display: controller.name, code: code,
                             value: Binding(get: { controller.percent(of: code) },
                                            set: { controller.set(code: code, percent: $0) }))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 300, alignment: .leading)
        // Opening a menu does not make Candela the active app, and the sliders would draw their
        // filled part gray as if they were in a window in the background.
        .environment(\.controlActiveState, .key)
    }
}

/// The control's symbol, the system's own slider (0 to 100) and the level.
private struct MenuLevelRow: View {
    let display: String
    let code: UInt8
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ControlSymbol.name(for: code))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Slider(value: $value, in: 0 ... 100, onEditingChanged: { pressed in
                if pressed { MenuDrag.forwardRest(to: NSApp.currentEvent?.window) }
            })
            .labelsHidden()
            .accessibilityLabel("\(display) \(MCCS.name(of: code))")
            Text("\(Int(value.rounded()))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

/// In a menu, AppKit stops passing a pressed slider the drag once the pointer leaves its menu
/// item, and the slider never even sees the button come up, so its knob stays pressed. Once a
/// slider starts tracking, this hands the rest of the drag to the menu's window, the way an
/// ordinary window delivers it, until the button is released.
private enum MenuDrag {
    private static var isForwarding = false

    static func forwardRest(to window: NSWindow?) {
        guard let window, !isForwarding else { return }
        // After the press has been handled, while the menu is still open.
        DispatchQueue.main.async {
            isForwarding = true
            defer { isForwarding = false }
            while true {
                guard let event = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                                  until: Date(timeIntervalSinceNow: 0.05),
                                                  inMode: .eventTracking, dequeue: true) else {
                    // Nothing queued: done if the button is already up, otherwise keep waiting.
                    if NSEvent.pressedMouseButtons & 1 == 0 { return }
                    continue
                }
                window.sendEvent(event)
                if event.type == .leftMouseUp { return }
            }
        }
    }
}
