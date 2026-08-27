import AppKit

enum MenuMetrics {
    static let width: CGFloat = 300
    static let inset: CGFloat = 16
}

/// Display name plus up to two lines of status. The full explanation is available as a tooltip.
final class HeaderRow: NSView {
    init(title: String, status: String, tooltip: String?) {
        let textWidth = MenuMetrics.width - 2 * MenuMetrics.inset

        let detail = NSTextField(wrappingLabelWithString: status)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.cell?.truncatesLastVisibleLine = true
        detail.preferredMaxLayoutWidth = textWidth
        let measured = detail.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: textWidth, height: 1000)).height ?? 15
        let detailHeight = min(ceil(measured), 30)

        let height = 5 + detailHeight + 2 + 17 + 5
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: height))

        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        name.frame = NSRect(x: MenuMetrics.inset, y: 5 + detailHeight + 2, width: textWidth, height: 17)
        detail.frame = NSRect(x: MenuMetrics.inset, y: 5, width: textWidth, height: detailHeight)

        addSubview(name)
        addSubview(detail)
        toolTip = tooltip
        setAccessibilityLabel("\(title), \(status)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Icon, label, live value and a slider (0 to 100), used as a custom NSMenuItem view.
final class SliderRow: NSView {
    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let onChange: (Double) -> Void

    init(title: String, symbol: String, value: Double, onChange: @escaping (Double) -> Void) {
        self.onChange = onChange
        slider = NSSlider(value: value, minValue: 0, maxValue: 100, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 46))

        let icon = NSImageView(frame: NSRect(x: MenuMetrics.inset, y: 8, width: 18, height: 18))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = .secondaryLabelColor

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: MenuMetrics.inset, y: 28, width: 180, height: 14)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: MenuMetrics.width - MenuMetrics.inset - 50, y: 28, width: 50, height: 14)

        slider.frame = NSRect(x: MenuMetrics.inset + 26, y: 6, width: MenuMetrics.width - 2 * MenuMetrics.inset - 26, height: 22)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(changed)
        slider.setAccessibilityLabel(title)

        [icon, label, valueLabel, slider].forEach(addSubview)
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
