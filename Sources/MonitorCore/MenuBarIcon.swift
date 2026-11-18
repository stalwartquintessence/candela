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

/// Where the user wants Candela's icon: the window's Show in Menu Bar choice.
public enum MenuBarIconMode: String, CaseIterable, Sendable {
    case always
    /// The default. With the lid closed, the brightness keys on the MacBook's keyboard are out
    /// of reach, so the icon appears on its own.
    case whileLidClosed
    /// Also what removing the icon from the menu bar chooses.
    case never
}

public enum MenuBarIcon {
    public static func isShown(mode: MenuBarIconMode, lid: LidState) -> Bool {
        switch mode {
        case .always: return true
        case .whileLidClosed: return lid == .closed
        case .never: return false
        }
    }
}
