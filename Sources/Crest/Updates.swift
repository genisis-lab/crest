import Foundation
import Sparkle

@MainActor final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var configured = false
    @Published var status = "Updates are built in. This development build has no published update feed yet."
    @Published var automatic = UserDefaults.standard.object(forKey: "updateAutomatic") as? Bool ?? true { didSet { UserDefaults.standard.set(automatic, forKey: "updateAutomatic"); controller?.updater.automaticallyChecksForUpdates = automatic } }
    @Published var beta = UserDefaults.standard.bool(forKey: "updateBeta") { didSet { UserDefaults.standard.set(beta, forKey: "updateBeta"); controller?.updater.resetUpdateCycleAfterShortDelay() } }
    private var controller: SPUStandardUpdaterController?
    override init() {
        super.init()
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String, let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, Data(base64Encoded: key)?.count == 32 else { return }
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
        do { try controller?.updater.start(); configured = true; controller?.updater.automaticallyChecksForUpdates = automatic; status = "Signed updates enabled" }
        catch { status = "Updater could not start: \(error.localizedDescription)" }
    }
    func check() { if configured { controller?.checkForUpdates(nil) } }
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> { UserDefaults.standard.bool(forKey: "updateBeta") ? ["beta"] : [] }
}
