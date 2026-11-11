import AppKit
import MonitorCore

/// Watches the pointer for a shake. Following pointer movement in other apps needs no permission
/// (unlike the brightness keys), and only turns are counted: where the pointer goes is not kept.
/// Clicks start the count over, so moving quickly between buttons is never a shake.
final class ShakeMonitor {
    /// Called on the main thread when the pointer is shaken.
    var onShake: (() -> Void)?

    private var detector = PointerShake()
    private var monitors: [Any] = []

    private static let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    /// Starts watching. Calling it again does nothing.
    func start() {
        guard monitors.isEmpty else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.events, handler: { [weak self] event in
            self?.handle(event)
        }) {
            monitors.append(global)
        }
        // A global monitor sees only events sent to other apps; this one covers Candela's window.
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.events, handler: { [weak self] event in
            self?.handle(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Stops watching the pointer.
    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        detector.reset()
    }

    private func handle(_ event: NSEvent) {
        guard event.type == .mouseMoved else { return detector.reset() }
        if detector.move(dx: Double(event.deltaX), dy: Double(event.deltaY), at: event.timestamp) {
            onShake?()
        }
    }
}
