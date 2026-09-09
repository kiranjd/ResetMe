import AppKit
import Foundation
import Sparkle

@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController
    private(set) var started = false

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var configurationIssue: String? {
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        guard let feed, let url = URL(string: feed), url.scheme == "https" else {
            return "This build has no HTTPS update feed."
        }

        let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        guard publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return "This build has no update-signing public key."
        }

        return nil
    }

    var canCheckForUpdates: Bool {
        configurationIssue == nil && started && controller.updater.canCheckForUpdates
    }

    func start() {
        guard !started else { return }
        guard configurationIssue == nil else {
            NSLog("ResetMe updater disabled: %@", configurationIssue!)
            return
        }

        controller.startUpdater()
        started = true
    }

    func checkForUpdates() {
        guard let issue = configurationIssue else {
            if !started { start() }
            guard started else { return }
            controller.checkForUpdates(nil)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Updates aren’t configured in this build"
        alert.informativeText = "\(issue) ResetMe has not published a signed update channel yet."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
