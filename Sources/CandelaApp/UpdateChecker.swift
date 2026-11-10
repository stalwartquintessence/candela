import AppKit
import MonitorCore
import MonitorIO

/// Asks GitHub whether a newer Candela has been released. This is the only network request
/// Candela makes: when the user clicks Check for Updates, or at most once a day if they turned on
/// Check for Updates Automatically (off by default).
final class UpdateChecker {
    private enum Key {
        static let automatic = "checkForUpdatesAutomatically"
        static let lastCheck = "lastUpdateCheck"
        static let lastAnnounced = "lastAnnouncedUpdate"
    }

    /// Called with true while a check is running, so the window can show it.
    var onBusyChange: ((Bool) -> Void)?

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var busy = false {
        didSet { onBusyChange?(busy) }
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral // no cookies, nothing cached on disk
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    var isAutomatic: Bool { defaults.bool(forKey: Key.automatic) }

    /// Call once at launch. The first automatic check waits a little, because right after login
    /// the network is often not up yet.
    func start() {
        schedule(firstCheckAfter: 30)
    }

    func setAutomatic(_ on: Bool) {
        defaults.set(on, forKey: Key.automatic)
        Log.app("update check: automatic \(on ? "on" : "off")")
        schedule(firstCheckAfter: 0)
    }

    /// Check for Updates: always shows the result.
    func checkNow() {
        fetch { [weak self] result in self?.present(result) }
    }

    // MARK: Automatic checks

    private func schedule(firstCheckAfter delay: TimeInterval) {
        timer?.invalidate()
        timer = nil
        guard isAutomatic else { return }
        // Wake up hourly and ask GitHub only when a day has passed: timers stop while the Mac
        // sleeps, so a single daily timer could slip by days.
        let timer = Timer(fire: Date().addingTimeInterval(delay), interval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func checkIfDue() {
        let lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
        guard isAutomatic, UpdateCheck.isDue(lastCheck: lastCheck, now: Date()) else { return }
        fetch { [weak self] result in self?.handleAutomatic(result) }
    }

    /// Automatic checks stay quiet unless there is a version the user has not been told about.
    private func handleAutomatic(_ result: UpdateCheckResult) {
        guard case let .available(version, _) = result,
              UpdateCheck.shouldAnnounce(version, lastAnnounced: defaults.string(forKey: Key.lastAnnounced)) else { return }
        present(result)
    }

    // MARK: Request

    private func fetch(_ completion: @escaping (UpdateCheckResult) -> Void) {
        guard !busy else { return }
        busy = true
        var request = URLRequest(url: UpdateCheck.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Candela/\(AppVersion.string)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, error in
            let result: UpdateCheckResult
            if let status = (response as? HTTPURLResponse)?.statusCode {
                result = UpdateCheck.result(statusCode: status, body: data ?? Data())
            } else {
                result = .failed(.offline(error?.localizedDescription ?? "no reply"))
            }
            DispatchQueue.main.async {
                Log.app("update check: \(result)")
                guard let self else { return }
                self.busy = false
                // Any answer from GitHub counts as a check; being offline does not, so the next
                // hourly wake-up tries again.
                if case .failed(.offline) = result {} else {
                    self.defaults.set(Date(), forKey: Key.lastCheck)
                }
                completion(result)
            }
        }.resume()
    }

    // MARK: Alerts

    private func present(_ result: UpdateCheckResult) {
        let alert = NSAlert()
        var page: URL?
        switch result {
        case let .upToDate(current):
            alert.messageText = "Candela is up to date"
            alert.informativeText = "Version \(current) is the newest version available."
        case let .available(version, releasePage):
            page = releasePage
            defaults.set(version.description, forKey: Key.lastAnnounced)
            alert.messageText = "Candela \(version) is available"
            alert.informativeText = "You have version \(UpdateCheck.currentVersion). Download the new version from GitHub, then replace Candela in your Applications folder."
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Not Now")
        case let .failed(failure):
            alert.alertStyle = .warning
            alert.messageText = "Could not check for updates"
            alert.informativeText = failure.message
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, let page {
            NSWorkspace.shared.open(page)
        }
    }
}
