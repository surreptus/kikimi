import AppKit
import LangCore

/// Check for Updates: reads one small file from Kikimi's website, only when asked, and says what it finds. It never
/// installs anything; a newer version is a link to the download page. See the privacy policy for what is sent.
@MainActor
enum UpdateChecker {
    private static var checking = false

    static func run() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        var request = URLRequest(url: UpdateCheck.address, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        let outcome: UpdateCheck.Outcome
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            outcome = (response as? HTTPURLResponse)?.statusCode == 200 ? UpdateCheck.outcome(current: current, latest: data) : .failed
        } catch { outcome = .failed }
        show(outcome, current: current)
    }

    private static func show(_ outcome: UpdateCheck.Outcome, current: String) {
        let alert = NSAlert()
        switch outcome {
        case .upToDate:
            alert.messageText = String(localized: "Kikimi is up to date")
            alert.informativeText = String(localized: "You have the newest version, \(current).")
        case .failed:
            alert.messageText = String(localized: "Couldn't check for updates")
            alert.informativeText = String(localized: "Check your internet connection and try again later.")
        case .available(let version, let page):
            alert.messageText = String(localized: "Kikimi \(version) is available")
            alert.informativeText = String(localized: "You have \(current). The download page has the new version and what changed.")
            alert.addButton(withTitle: String(localized: "Open Download Page"))
            alert.addButton(withTitle: String(localized: "Not Now"))
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
            return
        }
        alert.runModal()
    }
}
