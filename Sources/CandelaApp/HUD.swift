import AppKit

/// The 16-segment level bar macOS uses for brightness and volume. Fine steps (Option+Shift)
/// fill quarter segments, as in the system indicator.
private final class SegmentBar: NSView {
    static let segments = 16
    var level: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let gap: CGFloat = 2
        let count = Self.segments
        let width = (bounds.width - gap * CGFloat(count - 1)) / CGFloat(count)
        // Snap to quarter segments so rounding in the monitor's raw value never leaves a sliver.
        let filled = (min(max(level, 0), 100) / 100 * Double(count) * 4).rounded() / 4
        for i in 0 ..< count {
            let rect = NSRect(x: CGFloat(i) * (width + gap), y: 0, width: width, height: bounds.height)
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            let fraction = min(1, max(0, filled - Double(i)))
            guard fraction > 0 else { continue }
            NSColor.labelColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(fraction), height: rect.height),
                         xRadius: 1, yRadius: 1).fill()
        }
    }
}

/// Brightness indicator matching the one macOS has shown since version 26: a pill under the
/// menu bar at the top right of the display being adjusted, with a sun and a 16-segment bar.
/// It uses the system's own glass material where available, so it follows the current look of
/// macOS, and a blurred panel on earlier versions.
final class HUD {
    private enum Metrics {
        static let size = NSSize(width: 300, height: 64)
        static let cornerRadius = size.height / 2
        /// Distance from the right edge of the screen and from the menu bar.
        static let margin: CGFloat = 8
        static let leading: CGFloat = 20
        static let trailing: CGFloat = 30
        static let iconSize: CGFloat = 28
        static let iconGap: CGFloat = 14
        static let barHeight: CGFloat = 4
        static let visibleFor: TimeInterval = 1.5
    }

    private let panel: NSPanel
    private let bar = SegmentBar()
    private var hideTask: DispatchWorkItem?
    /// Increases with every `show`, so a fade-out that finishes late never hides a newer update.
    private var generation = 0

    init() {
        let frame = NSRect(origin: .zero, size: Metrics.size)
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let content = NSView(frame: frame)
        let icon = NSImageView(frame: NSRect(x: Metrics.leading, y: (Metrics.size.height - Metrics.iconSize) / 2,
                                             width: Metrics.iconSize, height: Metrics.iconSize))
        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        icon.contentTintColor = .labelColor

        let barX = Metrics.leading + Metrics.iconSize + Metrics.iconGap
        bar.frame = NSRect(x: barX, y: (Metrics.size.height - Metrics.barHeight) / 2,
                           width: Metrics.size.width - barX - Metrics.trailing, height: Metrics.barHeight)
        [icon, bar].forEach(content.addSubview)

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = Metrics.cornerRadius
            glass.contentView = content
            panel.hasShadow = false // the glass draws its own edge
            panel.contentView = glass
        } else {
            let blur = NSVisualEffectView(frame: frame)
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = Metrics.cornerRadius
            blur.layer?.masksToBounds = true
            blur.addSubview(content)
            panel.hasShadow = true
            panel.contentView = blur
        }
    }

    /// Shows `level` (0 to 100) on `screen`. `name` is the display's name, read out by VoiceOver.
    func show(level: Double, name: String, on screen: NSScreen) {
        bar.level = level
        let area = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.maxX - Metrics.size.width - Metrics.margin,
                                     y: area.maxY - Metrics.size.height - Metrics.margin))

        generation += 1
        let current = generation
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 1
        }

        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self.panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
            })
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.visibleFor, execute: task)

        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(name) brightness \(Int(level.rounded())) percent",
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}
