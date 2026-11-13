import AppKit
import SwiftUI

/// Candela's menu bar icon: a brightness slider for each external display, and the way to the
/// window for everything else. It shows while the lid is closed, when the brightness keys on the
/// MacBook's keyboard are out of reach, or all the time if the user asks for it.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let controllers: () -> [DisplayController]
    private let openWindow: () -> Void
    /// Made the first time the icon shows, then only hidden and shown again, so it keeps its place.
    private var statusItem: NSStatusItem?

    init(controllers: @escaping () -> [DisplayController], openWindow: @escaping () -> Void) {
        self.controllers = controllers
        self.openWindow = openWindow
    }

    var isVisible: Bool { statusItem?.isVisible == true }

    func setVisible(_ visible: Bool) {
        if visible, statusItem == nil { statusItem = makeStatusItem() }
        if !visible { statusItem?.menu?.cancelTracking() }
        statusItem?.isVisible = visible
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "Candela"
        item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Candela")
        item.button?.toolTip = "Candela"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
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
        for controller in displays {
            let row = NSHostingView(rootView: BrightnessMenuRow(controller: controller))
            row.frame.size = row.fittingSize
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open Candela", action: #selector(openCandela), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
    }

    @objc private func openCandela() {
        openWindow()
    }
}

/// The display's name and level above the system's own brightness slider, as a menu item view.
private struct BrightnessMenuRow: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(controller.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(Int(controller.brightness.rounded()))%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(get: { controller.brightness }, set: { controller.setBrightness($0) }),
                       in: 0 ... 100,
                       onEditingChanged: { pressed in
                           if pressed { MenuDrag.forwardRest(to: NSApp.currentEvent?.window) }
                       })
                    .labelsHidden()
                    .accessibilityLabel("\(controller.name) brightness")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(width: 280)
        // Opening a menu does not make Candela the active app, and the slider would draw its
        // filled part gray as if it were in a window in the background.
        .environment(\.controlActiveState, .key)
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
