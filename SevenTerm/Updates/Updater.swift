import Foundation
import Sparkle

/// Sparkle, for "Check for Updates…" and its own scheduled checks. Updates
/// come from the appcast attached to the latest GitHub release and must be
/// signed with the key whose public half is in Info.plist (SUPublicEDKey).
///
/// Builds without that key (local development, tools/install.sh before the
/// key exists) don't start Sparkle at all, rather than show it failing.
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController?

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        controller = key.isEmpty || key.hasPrefix("$(")
            ? nil
            : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
