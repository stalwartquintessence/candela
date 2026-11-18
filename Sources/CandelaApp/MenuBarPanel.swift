import AppKit
import MonitorCore
import SwiftUI

/// The panel under Candela's menu bar icon, laid out like the Sound and Display panels macOS
/// shows from the menu bar: the system's glass, the system's own sliders, and rows that light up
/// under the pointer like menu items. It is a window rather than a menu, because a slider in a
/// menu draws as a plain knob and stops following the pointer once it leaves its row.
final class MenuBarPanel {
    enum Metrics {
        static let width: CGFloat = 308
        static let cornerRadius: CGFloat = 14
        /// Space between the menu bar and the top of the panel, as under Sound.
        static let gapBelowMenuBar: CGFloat = 1
        /// Closest the panel comes to the side of the screen.
        static let screenMargin: CGFloat = 6
        /// Half the width of the capsule macOS draws behind a menu bar icon while its menu is
        /// open. The panel's left edge lines up with the capsule's, as under Sound.
        static let highlightHalfWidth: CGFloat = 21
    }

    /// Asked when the panel closes itself: the pointer clicked elsewhere, Escape, or an action.
    var onClose: (() -> Void)?

    private let panel = KeyPanel()
    private var outsideClicks: Any?

    var isShown: Bool { panel.isVisible }

    init() {
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle, .transient]
        panel.autorecalculatesKeyViewLoop = true
        panel.onCancel = { [weak self] in self?.onClose?() }
    }

    /// Shows `content` below `button`, the status item's button, lined up with its left edge.
    func show<Content: View>(_ content: Content, below button: NSStatusBarButton) {
        guard let itemWindow = button.window, let screen = itemWindow.screen ?? NSScreen.main else { return }

        let host = NSHostingView(rootView: content.frame(width: Metrics.width))
        host.frame.size = host.fittingSize
        panel.contentView = Self.background(around: host)
        panel.setContentSize(host.frame.size)

        // The status item's window reaches well below the menu bar, so place the panel by the
        // button, which fills the menu bar's height, and by its symbol, which the highlight
        // capsule is centered on.
        let item = itemWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? button.bounds
        let symbol = itemWindow.convertToScreen(button.convert(imageRect, to: nil))
        let size = panel.frame.size
        let area = screen.frame
        let left = symbol.midX - Metrics.highlightHalfWidth
        let x = min(max(left, area.minX + Metrics.screenMargin), area.maxX - size.width - Metrics.screenMargin)
        let top = item.minY.rounded(.down) - Metrics.gapBelowMenuBar
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)

        // Key without making Candela the active app, so Tab and Escape work like in a menu.
        panel.makeKeyAndOrderFront(nil)
        watchOutsideClicks()
    }

    func close() {
        if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
        outsideClicks = nil
        panel.orderOut(nil)
    }

    /// A click anywhere else, in another app or on the desktop, closes the panel like a menu.
    private func watchOutsideClicks() {
        guard outsideClicks == nil else { return }
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.onClose?()
        }
    }

    /// The system's glass on macOS 26 and later, the menu material before that.
    private static func background(around content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: content.frame)
            glass.cornerRadius = Metrics.cornerRadius
            glass.contentView = content
            return glass
        }
        let material = NSVisualEffectView(frame: content.frame)
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = Metrics.cornerRadius
        material.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        material.addSubview(content)
        return material
    }
}

/// A borderless panel that can still take the keyboard, and closes on Escape.
private final class KeyPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// MARK: Content

/// Everything in the panel: a section per display, then Open Candela.
struct MenuPanelContent: View {
    let displays: [DisplayController]
    let openCandela: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if displays.isEmpty {
                Text("No external displays connected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 15)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
            }
            ForEach(Array(displays.enumerated()), id: \.element.id) { index, display in
                if index > 0 { PanelSeparator() }
                DisplayPanelSection(controller: display)
            }
            PanelSeparator()
            PanelRow(title: "Open Candela", action: openCandela)
                .padding(5)
        }
        // A panel opened from the menu bar does not make Candela the active app, and the sliders
        // would draw their filled part gray as if they were in a window in the background.
        .environment(\.controlActiveState, .key)
    }
}

/// The display's name, a slider for each level control the window shows, and the monitor's own
/// presets (Picture Mode, Color Preset) as lists with a checkmark on the current choice, like
/// Output under Sound.
private struct DisplayPanelSection: View {
    @ObservedObject var controller: DisplayController

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(controller.name)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .frame(height: 16)
                .padding(.top, 13)
                .padding(.horizontal, 15)
            VStack(spacing: 4) {
                PanelSlider(display: controller.name, code: MCCS.brightness,
                            value: Binding(get: { controller.brightness }, set: { controller.setBrightness($0) }))
                ForEach(controller.plan.sliders, id: \.self) { code in
                    PanelSlider(display: controller.name, code: code,
                                value: Binding(get: { controller.percent(of: code) },
                                               set: { controller.set(code: code, percent: $0) }))
                }
            }
            .padding(.top, 5)
            .padding(.horizontal, 15)
            .padding(.bottom, 6)

            ForEach(controller.plan.pickers, id: \.code) { picker in
                Divider().padding(.horizontal, 15)
                Text(MCCS.name(of: picker.code))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(height: 16)
                    .padding(.top, 9)
                    .padding(.bottom, 3)
                    .padding(.horizontal, 15)
                VStack(spacing: 0) {
                    ForEach(picker.values, id: \.self) { value in
                        PanelRow(title: MCCS.valueName(code: picker.code, value: value),
                                 checked: MCCS.isSameChoice(controller.currentValue(of: picker.code), value)) {
                            controller.set(code: picker.code, value: value)
                        }
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 6)
            }
        }
    }
}

/// The system's slider between a small and a large symbol, like the volume slider under Sound.
private struct PanelSlider: View {
    let display: String
    let code: UInt8
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ControlSymbol.low(for: code))
                .frame(width: 18)
            Slider(value: $value, in: 0 ... 100)
                .labelsHidden()
                .accessibilityLabel("\(display) \(MCCS.name(of: code))")
                .accessibilityValue("\(Int(value.rounded())) percent")
            Image(systemName: ControlSymbol.high(for: code))
                .frame(width: 22)
        }
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .frame(height: 24)
    }
}

/// A full-width line between parts of the panel, like the one above Sound Settings.
private struct PanelSeparator: View {
    var body: some View {
        Divider().padding(.horizontal, 5)
    }
}

/// A row that lights up under the pointer like a menu item. With `checked`, it leaves room for a
/// checkmark and shows it on the current choice.
private struct PanelRow: View {
    let title: String
    var checked: Bool? = nil
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let checked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 12)
                        .opacity(checked ? 1 : 0)
                }
                Text(title)
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 22)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.1) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(checked == true ? .isSelected : [])
    }
}
