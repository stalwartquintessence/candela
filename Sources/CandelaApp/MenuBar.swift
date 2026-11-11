import AppKit

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

    /// Built each time it opens, so it lists the displays connected now at their current levels.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let displays = controllers()
        if displays.isEmpty {
            let item = NSMenuItem(title: "No external displays connected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for controller in displays {
            let item = NSMenuItem()
            item.view = BrightnessRow(name: controller.name, value: controller.brightness) { [weak controller] level in
                controller?.setBrightness(level)
            }
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

/// The display's name and level above a brightness slider (0 to 100), as a menu item view.
private final class BrightnessRow: NSView {
    private static let width: CGFloat = 280
    private static let inset: CGFloat = 14

    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let onChange: (Double) -> Void

    init(name: String, value: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        slider = NSSlider(value: value, minValue: 0, maxValue: 100, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 50))
        let inset = Self.inset

        let title = NSTextField(labelWithString: name)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: inset, y: 29, width: Self.width - 2 * inset - 50, height: 17)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: Self.width - inset - 44, y: 30, width: 44, height: 14)

        let icon = NSImageView(frame: NSRect(x: inset, y: 6, width: 16, height: 16))
        icon.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor

        slider.frame = NSRect(x: inset + 24, y: 3, width: Self.width - 2 * inset - 24, height: 22)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.setAccessibilityLabel("\(name) brightness")

        [title, valueLabel, icon, slider].forEach(addSubview)
        updateValueLabel()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func changed() {
        updateValueLabel()
        onChange(slider.doubleValue)
    }

    private func updateValueLabel() {
        valueLabel.stringValue = "\(Int(slider.doubleValue.rounded()))%"
    }
}
