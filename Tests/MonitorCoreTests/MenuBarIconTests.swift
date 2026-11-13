import Testing
@testable import MonitorCore

@Suite("Menu bar icon")
struct MenuBarIconTests {
    @Test func lidStateFromClamshellValue() {
        #expect(LidState(clamshellClosed: true) == .closed)
        #expect(LidState(clamshellClosed: false) == .open)
        #expect(LidState(clamshellClosed: nil) == .noLid)
    }

    @Test func whileTheLidIsClosedShowsItOnlyThen() {
        #expect(MenuBarIcon.isShown(mode: .whileLidClosed, lid: .closed))
        #expect(!MenuBarIcon.isShown(mode: .whileLidClosed, lid: .open))
        #expect(!MenuBarIcon.isShown(mode: .whileLidClosed, lid: .noLid))
    }

    @Test func alwaysAndNeverIgnoreTheLid() {
        for lid in [LidState.open, .closed, .noLid] {
            #expect(MenuBarIcon.isShown(mode: .always, lid: lid))
            #expect(!MenuBarIcon.isShown(mode: .never, lid: lid))
        }
    }

    @Test func modesAreSavedByName() {
        // Saved in the preferences by raw value, so the names must not change.
        #expect(MenuBarIconMode.allCases.map(\.rawValue) == ["always", "whileLidClosed", "never"])
        #expect(MenuBarIconMode(rawValue: "sometimes") == nil)
    }
}
