import Testing
@testable import MonitorCore

@Suite("Menu bar icon")
struct MenuBarIconTests {
    @Test func lidStateFromClamshellValue() {
        #expect(LidState(clamshellClosed: true) == .closed)
        #expect(LidState(clamshellClosed: false) == .open)
        #expect(LidState(clamshellClosed: nil) == .noLid)
    }

    @Test func showsOnItsOwnOnlyWhileTheLidIsClosed() {
        #expect(MenuBarIcon.isShown(always: false, lid: .closed))
        #expect(!MenuBarIcon.isShown(always: false, lid: .open))
        #expect(!MenuBarIcon.isShown(always: false, lid: .noLid))
    }

    @Test func alwaysShowKeepsItThere() {
        #expect(MenuBarIcon.isShown(always: true, lid: .open))
        #expect(MenuBarIcon.isShown(always: true, lid: .closed))
        #expect(MenuBarIcon.isShown(always: true, lid: .noLid))
    }
}
