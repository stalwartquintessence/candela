import AppKit
import MonitorCore
import SwiftUI

/// Candela's menu bar icon: a panel with each external display's sliders and presets, and the
/// way to the window for everything else. It shows while the lid is closed, when the brightness
/// keys on the MacBook's keyboard are out of reach, or all the time if the user asks for it.
///
/// On macOS 27 and later the panel opens through the status item's expanded interface session,
/// so the menu bar treats it like one of its own menus: the icon stays highlighted, keyboard
/// focus moves to the panel, and opening another menu closes it. Earlier versions open it on a
/// click and highlight the icon themselves.
final class MenuBarController: NSObject {
    private let controllers: () -> [DisplayController]
    private let openWindow: () -> Void
    private let removedByUser: () -> Void
    /// Made the first time the icon shows, then only hidden and shown again, so it keeps its place.
    private var statusItem: NSStatusItem?
    private var visibility: NSKeyValueObservation?
    /// True while Candela itself shows or hides the icon, so only the user's removal is reported.
    private var isChangingVisibility = false
    fileprivate let panel = MenuBarPanel()
    /// The macOS 27 session delegate, kept here because the status item holds it weakly.
    fileprivate var expandedInterface: AnyObject?
    /// True while the brightness indicator has the icon highlighted, so only that highlight is
    /// taken away when it goes.
    private var highlightedForIndicator = false
    /// Draws the icon's symbol while it turns into a display and back. The button cannot animate
    /// a change of symbol itself.
    private var symbolView: NSImageView?
    /// The symbol the indicator last asked for, so a late hand-back never undoes a newer change.
    private var showsDisplaySymbol = false

    init(controllers: @escaping () -> [DisplayController], openWindow: @escaping () -> Void,
         removedByUser: @escaping () -> Void) {
        self.controllers = controllers
        self.openWindow = openWindow
        self.removedByUser = removedByUser
        super.init()
        panel.onClose = { [weak self] in self?.dismissPanel() }
    }

    var isVisible: Bool { statusItem?.isVisible == true }

    func setVisible(_ visible: Bool) {
        if visible, statusItem == nil { statusItem = makeStatusItem() }
        if !visible {
            dismissPanel()
            resetIndicatorLook()
        }
        isChangingVisibility = true
        statusItem?.isVisible = visible
        isChangingVisibility = false
    }

    /// Displays came or went: show the ones connected now if the panel is open.
    func displaysChanged() {
        guard panel.isShown else { return }
        showPanel()
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "Candela"
        item.button?.image = Self.sunSymbol
        item.button?.toolTip = "Candela"
        if !useExpandedInterface(for: item) {
            item.button?.target = self
            item.button?.action = #selector(iconClicked)
            item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        // Command-dragging the icon out of the menu bar removes it, like Apple's own items.
        // AppKit then sets isVisible to false, and Candela takes that as the user's choice.
        item.behavior = .removalAllowed
        visibility = item.observe(\.isVisible) { [weak self] item, _ in
            guard let self, !self.isChangingVisibility, !item.isVisible else { return }
            self.removedByUser()
        }
        return item
    }

    // MARK: Panel

    fileprivate func showPanel() {
        guard let button = statusItem?.button else { return }
        // The panel takes over the icon. Its highlight stays: the menu bar has just put it there.
        resetIndicatorLook(unhighlight: false)
        panel.show(MenuPanelContent(displays: controllers(), openCandela: { [weak self] in
            self?.dismissPanel()
            self?.openWindow()
        }), below: button)
    }

    /// Closes the panel, and on macOS 27 ends the session so the menu bar knows it is closed.
    private func dismissPanel() {
        if endExpandedInterfaceSession() { return } // the session's end closes the panel
        panel.close()
        statusItem?.button?.highlight(false)
    }

    /// Before macOS 27: a click on the icon opens or closes the panel.
    @objc private func iconClicked() {
        if panel.isShown {
            dismissPanel()
        } else {
            showPanel()
            statusItem?.button?.highlight(true)
        }
    }
}

// MARK: Brightness indicator

/// The brightness indicator comes out of Candela's icon, the way the system's comes out of
/// Control Center's: the icon is highlighted and shows a display while the indicator is up.
extension MenuBarController: IndicatorSource {
    private static let sunSymbol = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Candela")
    private static let displaySymbol = NSImage(systemSymbolName: "display", accessibilityDescription: "Candela")

    func indicatorIconMidX(on screen: NSScreen) -> CGFloat? {
        // While the panel is open, the indicator leaves the icon to it.
        guard let item = statusItem, item.isVisible, !panel.isShown, let button = item.button,
              let itemWindow = button.window, let itemScreen = itemWindow.screen else { return nil }
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? button.bounds
        let symbol = itemWindow.convertToScreen(button.convert(imageRect, to: nil))
        // The status item is measured on one display's menu bar; the others show it in the same place.
        return IndicatorPlacement.iconMidX(distanceFromRightEdge: itemScreen.frame.maxX - symbol.midX,
                                           screenMaxX: screen.frame.maxX)
    }

    func setIconHighlighted(_ highlighted: Bool) {
        guard let button = statusItem?.button, !panel.isShown, highlighted != highlightedForIndicator else { return }
        highlightedForIndicator = highlighted
        button.highlight(highlighted)
    }

    func setIconShowsDisplay(_ showsDisplay: Bool) {
        guard let button = statusItem?.button, !panel.isShown,
              let sun = Self.sunSymbol, let display = Self.displaySymbol else { return }
        showsDisplaySymbol = showsDisplay
        guard #available(macOS 14.0, *) else {
            button.image = showsDisplay ? display : sun
            return
        }
        if showsDisplay {
            guard symbolView == nil else { return }
            let view = Self.symbolView(drawing: sun, like: button)
            button.addSubview(view)
            // Keep the button's own sun, so the button keeps its size, but draw it clear.
            button.contentTintColor = .clear
            symbolView = view
            view.setSymbolImage(display, contentTransition: .replace)
        } else if let view = symbolView {
            view.setSymbolImage(sun, contentTransition: .replace)
            // Hand the symbol back to the button once the transition is over.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self, weak view] in
                guard let self, let view, self.symbolView === view, !self.showsDisplaySymbol else { return }
                self.resetIndicatorLook()
            }
        }
    }

    /// A view that draws `symbol` over `button` exactly as the button draws its image, so the
    /// symbol can be swapped there with a transition.
    @available(macOS 14.0, *)
    private static func symbolView(drawing symbol: NSImage, like button: NSStatusBarButton) -> NSImageView {
        // The button centers its image in the cell's image rectangle, which can sit off the
        // middle of the button, and the image view centers it in its frame.
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? button.bounds
        let bounds = button.bounds
        let view = NSImageView(frame: bounds.offsetBy(dx: imageRect.midX - bounds.midX, dy: imageRect.midY - bounds.midY))
        view.image = symbol
        view.symbolConfiguration = button.symbolConfiguration ?? matchingConfiguration(for: button.font)
        view.imageScaling = .scaleNone
        view.setAccessibilityElement(false)
        return view
    }

    /// The configuration a status bar button gives a symbol when it has none of its own: sized
    /// to its font, drawn medium weight. Measured against the button's own drawing on macOS 27,
    /// in light and dark menu bars.
    private static func matchingConfiguration(for font: NSFont?) -> NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: font?.pointSize ?? NSFont.systemFontSize, weight: .medium, scale: .medium)
    }

    /// Puts the icon back as it is without the indicator, at once.
    private func resetIndicatorLook(unhighlight: Bool = true) {
        showsDisplaySymbol = false
        if let view = symbolView {
            view.removeFromSuperview()
            symbolView = nil
            statusItem?.button?.contentTintColor = nil
        }
        if let button = statusItem?.button, button.image !== Self.sunSymbol { button.image = Self.sunSymbol }
        if highlightedForIndicator {
            highlightedForIndicator = false
            if unhighlight, !panel.isShown { statusItem?.button?.highlight(false) }
        }
    }
}

// MARK: Expanded interface session (macOS 27)

// The API is in the macOS 27 SDK, which comes with Swift 6.4. Builds made with an older SDK
// open the panel on a click on every version of macOS.
#if compiler(>=6.4)
extension MenuBarController {
    private func useExpandedInterface(for item: NSStatusItem) -> Bool {
        guard #available(macOS 27.0, *) else { return false }
        let session = ExpandedInterface(begin: { [weak self] in self?.showPanel() },
                                        end: { [weak self] in self?.panel.close() })
        item.expandedInterfaceDelegate = session
        expandedInterface = session // the status item holds its delegate weakly
        return true
    }

    /// Returns true when a session was open and has been asked to end.
    private func endExpandedInterfaceSession() -> Bool {
        guard #available(macOS 27.0, *), let session = statusItem?.expandedInterfaceSession else { return false }
        session.cancel()
        return true
    }
}

/// Opens and closes the panel when the menu bar begins and ends the icon's session.
@available(macOS 27.0, *)
private final class ExpandedInterface: NSObject, NSStatusItemExpandedInterfaceDelegate {
    private let begin: () -> Void
    private let end: () -> Void

    init(begin: @escaping () -> Void, end: @escaping () -> Void) {
        self.begin = begin
        self.end = end
    }

    func statusItem(_ statusItem: NSStatusItem, didBegin expandedInterfaceSession: NSStatusItemExpandedInterfaceSession) {
        begin()
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        end()
    }
}
#else
extension MenuBarController {
    private func useExpandedInterface(for item: NSStatusItem) -> Bool { false }
    private func endExpandedInterfaceSession() -> Bool { false }
}
#endif
