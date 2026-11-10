import AppKit
import MonitorIO
import Sparkle

/// In-app updates through Sparkle: it reads the update feed attached to the latest GitHub
/// release, and downloads, verifies, installs and relaunches a newer version. Candela asks for
/// the feed only when the user clicks Check for Updates, or once a day if they turned on Check
/// for Updates Automatically (off by default). No system profile is sent.
final class Updater: NSObject, SPUStandardUserDriverDelegate {
    /// Called on the main thread whenever a check becomes possible or impossible (for example
    /// while one is already running), so the window can enable its button.
    var onCanCheckChange: ((Bool) -> Void)?

    private var controller: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    /// Release builds carry the public key that update signatures are checked against. Builds
    /// without one (forks, local test builds) leave in-app updates off.
    static var isConfigured: Bool {
        !((Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String) ?? "").isEmpty
    }

    func start() {
        guard Self.isConfigured else {
            Log.app("updates: this build has no update key, in-app updates are off")
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let canCheck = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.onCanCheckChange?(canCheck) }
        }
        self.controller = controller
    }

    var checksAutomatically: Bool {
        controller?.updater.automaticallyChecksForUpdates ?? false
    }

    func setChecksAutomatically(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
        Log.app("updates: automatic checks \(on ? "on" : "off")")
    }

    /// Check for Updates: Sparkle shows the result, and for a newer version offers to install it.
    func checkNow() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    // MARK: SPUStandardUserDriverDelegate

    /// Sparkle asks background apps how they surface updates found by scheduled checks.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // Candela has no Dock or menu bar icon, so an update shown behind other windows would be
        // easy to miss. The user turned automatic checks on, so bring it to the front.
        guard handleShowingUpdate, !state.userInitiated else { return }
        Log.app("updates: found \(update.displayVersionString) in a scheduled check")
        NSApp.activate(ignoringOtherApps: true)
    }
}
