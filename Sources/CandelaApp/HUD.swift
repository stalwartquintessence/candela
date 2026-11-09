import AppKit

/// A rounded level bar: a faint track with a solid fill from the left.
private final class LevelBar: NSView {
    var level: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        guard level > 0 else { return }
        let width = max(bounds.height, bounds.width * CGFloat(min(level, 100) / 100))
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: bounds.height), xRadius: radius, yRadius: radius).fill()
    }
}

/// Brightness indicator in the style macOS has used since version 26: a small panel under the
/// menu bar, at the top right of the display being adjusted. It uses the system's own glass
/// material where available, so it follows the current look of macOS, and a blurred panel on
/// earlier versions.
final class HUD {
    private enum Metrics {
        static let size = NSSize(width: 240, height: 56)
        static let cornerRadius: CGFloat = 18
        /// Distance from the right edge of the screen and from the menu bar.
        static let margin: CGFloat = 8
        static let inset: CGFloat = 14
        static let visibleFor: TimeInterval = 1.5
    }

    private let panel: NSPanel
    private let title = NSTextField(labelWithString: "")
    private let bar = LevelBar()
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
        let width = Metrics.size.width - 2 * Metrics.inset

        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.frame = NSRect(x: Metrics.inset, y: 31, width: width, height: 16)

        let icon = NSImageView(frame: NSRect(x: Metrics.inset - 1, y: 9, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        icon.contentTintColor = .labelColor

        bar.frame = NSRect(x: Metrics.inset + 26, y: 14, width: width - 26, height: 8)

        [title, icon, bar].forEach(content.addSubview)

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

    /// Shows `level` (0 to 100) for the display called `name`, on `screen`.
    func show(level: Double, name: String, on screen: NSScreen) {
        title.stringValue = name
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
