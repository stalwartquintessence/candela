import AppKit
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
        if !visible { dismissPanel() }
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
        item.button?.image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Candela")
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
