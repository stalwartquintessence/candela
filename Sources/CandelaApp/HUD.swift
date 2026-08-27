import AppKit

private final class SegmentBar: NSView {
    var level: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let count = 16
        let gap: CGFloat = 2
        let width = (bounds.width - gap * CGFloat(count - 1)) / CGFloat(count)
        let filled = Int((level / 100 * Double(count)).rounded())
        for i in 0 ..< count {
            let rect = NSRect(x: CGFloat(i) * (width + gap), y: 0, width: width, height: bounds.height)
            (i < filled ? NSColor.labelColor : NSColor.labelColor.withAlphaComponent(0.2)).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
        }
    }
}

/// A floating overlay similar to the native brightness indicator.
final class HUD {
    private let panel: NSPanel
    private let icon = NSImageView(frame: NSRect(x: 50, y: 60, width: 100, height: 100))
    private let bar = SegmentBar(frame: NSRect(x: 20, y: 24, width: 160, height: 7))
    private var hideTask: DispatchWorkItem?

    init() {
        let size = NSSize(width: 200, height: 200)
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let blur = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 22
        blur.layer?.masksToBounds = true

        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 64, weight: .regular)
        icon.contentTintColor = .labelColor

        blur.addSubview(icon)
        blur.addSubview(bar)
        panel.contentView = blur
    }

    func show(level: Double, on screen: NSScreen) {
        bar.level = level
        let frame = screen.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 140))

        hideTask?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let task = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.3
                self?.panel.animator().alphaValue = 0
            }, completionHandler: {
                if self?.panel.alphaValue == 0 { self?.panel.orderOut(nil) }
            })
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: task)
    }
}
