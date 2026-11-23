import AppKit
import MonitorCore

/// The 16-segment level bar macOS uses for brightness and volume. Fine steps (Option+Shift)
/// fill quarter segments, as in the system indicator.
private final class SegmentBar: NSView {
    static let segments = 16
    var level: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let gap: CGFloat = 2
        let count = Self.segments
        // Whole-point segments, centered, with every edge on a device pixel: fractional widths
        // leave uneven gaps and soft edges, most visibly on a 1x display.
        let width = ((bounds.width - gap * CGFloat(count - 1)) / CGFloat(count)).rounded(.down)
        let start = ((bounds.width - (width * CGFloat(count) + gap * CGFloat(count - 1))) / 2).rounded(.down)
        // Snap to quarter segments so rounding in the monitor's raw value never leaves a sliver.
        let filled = (min(max(level, 0), 100) / 100 * Double(count) * 4).rounded() / 4
        for i in 0 ..< count {
            let rect = backingAlignedRect(NSRect(x: start + CGFloat(i) * (width + gap), y: 0, width: width, height: bounds.height),
                                          options: .alignAllEdgesNearest)
            NSColor.labelColor.withAlphaComponent(0.22).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            let fraction = min(1, max(0, filled - Double(i)))
            guard fraction > 0 else { continue }
            NSColor.labelColor.setFill()
            let part = backingAlignedRect(NSRect(x: rect.minX, y: rect.minY, width: rect.width * CGFloat(fraction), height: rect.height),
                                          options: .alignAllEdgesNearest)
            NSBezierPath(roundedRect: part, xRadius: 1, yRadius: 1).fill()
        }
    }

}

/// The menu bar icon the indicator comes from, as the system's comes from Control Center's.
protocol IndicatorSource: AnyObject {
    /// The center of the icon on `screen`'s menu bar, or nil when the indicator cannot use it now.
    func indicatorIconMidX(on screen: NSScreen) -> CGFloat?
    func setIconHighlighted(_ highlighted: Bool)
    /// Turns the icon's symbol into a display, or back.
    func setIconShowsDisplay(_ showsDisplay: Bool)
}

/// Brightness indicator matching the one macOS has shown since version 26: a pill under the
/// menu bar with a sun and a 16-segment bar. Like the system's, which comes out of Control
/// Center's icon, it comes out of Candela's menu bar icon when that is shown: the icon is
/// highlighted and turns into a display, and the pill grows out from under it. Without the icon
/// it sits at the top right of the display being adjusted and only fades in and out.
/// It uses the system's own glass material where available, so it follows the current look of
/// macOS, and a blurred panel on earlier versions.
final class HUD {
    private enum Metrics {
        static let size = NSSize(width: 300, height: 64)
        static let cornerRadius = size.height / 2
        static let leading: CGFloat = 20
        static let trailing: CGFloat = 30
        static let iconSize: CGFloat = 28
        static let iconGap: CGFloat = 14
        static let barHeight: CGFloat = 4
        static let visibleFor: TimeInterval = 1.5
        /// How small the pill starts when it grows out of the icon, and ends when it goes back.
        static let collapsedScale: CGFloat = 0.5
        static let growDuration: TimeInterval = 0.35
        static let shrinkDuration: TimeInterval = 0.3
        /// The icon turns into a display while the pill grows, as Control Center's does.
        static let symbolDelay: TimeInterval = 0.15
    }

    /// Candela's menu bar icon. Set once at launch.
    weak var source: IndicatorSource?

    private let panel: NSPanel
    /// Holds the pill and scales it toward the icon while it grows and shrinks.
    private let container: NSView
    private let bar = SegmentBar()
    private var hideTask: DispatchWorkItem?
    /// Increases with every `show`, so a fade-out that finishes late never hides a newer update.
    private var generation = 0
    private var isHiding = false
    /// True while the icon shows that the indicator is up.
    private var usesIcon = false
    /// The point the pill grows out of and shrinks into, in the container's coordinates.
    private var origin: CGPoint?

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

        let pill: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = Metrics.cornerRadius
            glass.contentView = content
            panel.hasShadow = false // the glass draws its own edge
            pill = glass
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
            pill = blur
        }
        container = NSView(frame: frame)
        container.wantsLayer = true
        container.addSubview(pill)
        panel.contentView = container
    }


    /// Shows `level` (0 to 100) on `screen`. `name` is the display's name, read out by VoiceOver.
    func show(level: Double, name: String, on screen: NSScreen) {
        bar.level = level
        let area = screen.visibleFrame
        let iconMidX = source?.indicatorIconMidX(on: screen)
        let minX = IndicatorPlacement.minX(width: Metrics.size.width, iconMidX: iconMidX.map(Double.init),
                                           screenMinX: area.minX, screenMaxX: area.maxX)
        // On whole device pixels, so the bar's edges stay sharp.
        let pixel = screen.backingScaleFactor
        let x = (CGFloat(minX) * pixel).rounded() / pixel
        let y = ((area.maxY - Metrics.size.height - IndicatorPlacement.margin) * pixel).rounded() / pixel
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        // The top edge, under the icon: Core Animation measures from the container's bottom left.
        origin = iconMidX.map { CGPoint(x: $0 - x, y: Metrics.size.height) }

        generation += 1
        let current = generation
        let wasHidden = !panel.isVisible
        let appearing = wasHidden || isHiding
        isHiding = false
        if wasHidden {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        if appearing {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = origin == nil ? 0.15 : Metrics.growDuration
                panel.animator().alphaValue = 1
            }
            // From nothing, start small; while shrinking away, grow again from where it is now.
            scale(to: 1, from: wasHidden ? transform(scale: Metrics.collapsedScale) : nil,
                  duration: Metrics.growDuration, timing: CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1))
        }

        if origin != nil {
            source?.setIconHighlighted(true)
            if !usesIcon {
                usesIcon = true
                DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.symbolDelay) { [weak self] in
                    guard let self, self.usesIcon, !self.isHiding else { return }
                    self.source?.setIconShowsDisplay(true)
                }
            }
        } else {
            releaseIcon() // the icon went away while the indicator was up
        }

        hideTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.hide(generation: current) }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.visibleFor, execute: task)

        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(name) brightness \(Int(level.rounded())) percent",
                                        .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    /// Takes the highlight away, shrinks the pill back into the icon as it fades, and then turns
    /// the icon's symbol back into a sun, in the order Control Center does.
    private func hide(generation current: Int) {
        isHiding = true
        if usesIcon { source?.setIconHighlighted(false) }
        scale(to: Metrics.collapsedScale, from: nil, duration: Metrics.shrinkDuration, timing: CAMediaTimingFunction(name: .easeIn))
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Metrics.shrinkDuration
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == current else { return }
            self.isHiding = false
            self.panel.orderOut(nil)
            self.releaseIcon()
        })
    }

    private func releaseIcon() {
        guard usesIcon else { return }
        usesIcon = false
        source?.setIconHighlighted(false)
        source?.setIconShowsDisplay(false)
    }

    /// Scales the pill around `origin`, the point under the icon. Without the icon, or with
    /// Reduce Motion on, the pill keeps its size and only fades.
    /// `from` is where to start; nil starts from what is on screen now.
    private func scale(to scale: CGFloat, from start: CATransform3D?, duration: TimeInterval, timing: CAMediaTimingFunction) {
        guard let layer = container.layer else { return }
        let target = transform(scale: scale)
        let from = start ?? layer.presentation()?.sublayerTransform ?? layer.sublayerTransform
        layer.removeAnimation(forKey: "scale")
        layer.sublayerTransform = target
        guard !CATransform3DEqualToTransform(from, target) else { return }
        let animation = CABasicAnimation(keyPath: "sublayerTransform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = duration
        animation.timingFunction = timing
        layer.add(animation, forKey: "scale")
    }

    private func transform(scale: CGFloat) -> CATransform3D {
        guard let origin, scale != 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let layer = container.layer else { return CATransform3DIdentity }
        // sublayerTransform works around the layer's anchor point; move the origin there first.
        let anchor = CGPoint(x: layer.bounds.width * layer.anchorPoint.x, y: layer.bounds.height * layer.anchorPoint.y)
        let dx = origin.x - anchor.x, dy = origin.y - anchor.y
        var t = CATransform3DMakeTranslation(dx, dy, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        return CATransform3DTranslate(t, -dx, -dy, 0)
    }
}
