import AppKit
import MonitorCore
import MonitorIO

/// Asks GitHub whether a newer Candela has been released. This is the only network request
/// Candela makes, and only when the user clicks Check for Updates.
final class UpdateChecker {
    /// Called with true while a check is running, so the window can show it.
    var onBusyChange: ((Bool) -> Void)?

    private var busy = false {
        didSet { onBusyChange?(busy) }
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral // no cookies, nothing cached on disk
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// Check for Updates: always shows the result.
    func checkNow() {
        fetch { [weak self] result in self?.present(result) }
    }

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
                self?.busy = false
                completion(result)
            }
        }.resume()
    }

    private func present(_ result: UpdateCheckResult) {
        let alert = NSAlert()
        var page: URL?
        switch result {
        case let .upToDate(current):
            alert.messageText = "Candela is up to date"
            alert.informativeText = "Version \(current) is the newest version available."
        case let .available(version, releasePage):
            page = releasePage
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
