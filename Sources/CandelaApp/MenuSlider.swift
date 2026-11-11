import AppKit

/// A slider for a menu that keeps following the pointer while the button is held, wherever the
/// pointer goes, like sliders in windows. In a menu, AppKit stops sending a slider the drag once
/// the pointer leaves its menu item, so this one reads the drag itself until the button is up.
final class MenuSlider: NSSlider {
    override class var cellClass: AnyClass? {
        get { AccentSliderCell.self }
        set {}
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let cell = cell as? NSSliderCell else { return super.mouseDown(with: event) }
        let bar = cell.barRect(flipped: isFlipped)
        let knobWidth = cell.knobThickness
        // The knob's center travels from half a knob in from one end of the bar to the other.
        let start = bar.minX + knobWidth / 2
        let travel = bar.width - knobWidth
        let range = maxValue - minValue
        guard travel > 0, range > 0 else { return super.mouseDown(with: event) }

        // Where the knob is for the current value. AppKit's own knob rectangle can lag behind the
        // value while the knob animates to it, so it is not used here.
        let knobX = start + CGFloat((doubleValue - minValue) / range) * travel
        let press = point(of: event)
        // Pressing the knob drags it from where it was grabbed; pressing the bar moves it there first.
        let grab = abs(press.x - knobX) <= knobWidth / 2 ? press.x - knobX : 0

        func follow(_ x: CGFloat) {
            let fraction = Double(min(1, max(0, (x - grab - start) / travel)))
            let value = minValue + fraction * range
            guard value != doubleValue else { return }
            doubleValue = value
            sendAction(action, to: target)
        }

        follow(press.x)
        while let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture,
                                         inMode: .eventTracking, dequeue: true) {
            follow(point(of: next).x)
            if next.type == .leftMouseUp { break }
        }
    }

    /// The event's location in this view. Drags that leave the menu still belong to its window,
    /// but convert through the screen in case one does not.
    private func point(of event: NSEvent) -> NSPoint {
        guard let window else { return .zero }
        let inWindow: NSPoint
        if event.window === window {
            inWindow = event.locationInWindow
        } else if let other = event.window {
            inWindow = window.convertPoint(fromScreen: other.convertPoint(toScreen: event.locationInWindow))
        } else {
            inWindow = window.convertPoint(fromScreen: event.locationInWindow)
        }
        return convert(inWindow, from: nil)
    }
}

/// Fills the bar up to the knob with the accent color, like the slider in the Candela window.
/// Opening a menu does not make Candela the active app, so AppKit would draw the filled part in
/// gray, as for a slider in a window in the background. The empty part keeps the system's color.
private final class AccentSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let radius = rect.height / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        var filled = rect
        filled.size.width = max(0, knobRect(flipped: flipped).midX - rect.minX)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}
