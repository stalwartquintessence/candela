// When Candela shows its icon in the menu bar.

/// A MacBook's lid, as macOS reports it.
public enum LidState: Equatable, Sendable {
    case open
    case closed
    /// A desktop Mac, such as a Mac mini: it has no lid and no built-in keyboard.
    case noLid

    /// From macOS's `AppleClamshellState`, which only Macs with a lid report.
    public init(clamshellClosed: Bool?) {
        switch clamshellClosed {
        case true?: self = .closed
        case false?: self = .open
        case nil: self = .noLid
        }
    }
}

/// With the lid closed, the brightness keys on the MacBook's keyboard are out of reach, so the
/// icon appears on its own. Otherwise it shows only when the user asks for it.
public enum MenuBarIcon {
    public static func isShown(always: Bool, lid: LidState) -> Bool {
        always || lid == .closed
    }
}
