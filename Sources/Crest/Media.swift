import AppKit
import Darwin

@MainActor final class MediaService: ObservableObject {
    @Published var title = "Nothing playing"
    @Published var artist = "Connect a player in Settings"
    @Published var playing = false
    @Published var artwork: NSImage?
    @Published var available = false
    @Published var status = "Music controls are off"
    @Published var player = "System"
    private typealias Info = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias Command = @convention(c) (Int, CFDictionary?) -> Bool
    private var getInfo: Info?
    private var command: Command?
    private var timer: Timer?
    private var enabled = false
    func configure(enabled: Bool, player: String) {
        timer?.invalidate(); timer = nil; self.player = player; self.enabled = enabled; available = false
        guard enabled else { status = "Music controls are off"; return }
        if player == "System" {
            if let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY), let info = dlsym(h, "MRMediaRemoteGetNowPlayingInfo"), let send = dlsym(h, "MRMediaRemoteSendCommand") {
                getInfo = unsafeBitCast(info, to: Info.self); command = unsafeBitCast(send, to: Command.self)
            }
            status = "System player adapter · compatibility depends on macOS"
        } else { status = "\(player) · Automation permission may be requested" }
        refresh(); timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
    }
    func refresh() {
        guard enabled else { return }
        if player == "System" {
            guard let getInfo else { status = "System player API unavailable. Select Music or Spotify."; return }
            getInfo(.main) { [weak self] dictionary in
                Task { @MainActor in
                    guard let self, self.enabled, self.player == "System" else { return }
                    let info = dictionary as? [String: Any] ?? [:]
                    self.title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? "Nothing playing"
                    self.artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "Open Music, Spotify, Podcasts, TV or IINA"
                    self.playing = (info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0) > 0
                    self.available = !info.isEmpty
                    self.artwork = (info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data).flatMap(NSImage.init(data:))
                    if info.isEmpty { self.status = "No system metadata received. Use a direct player adapter if playback is active." }
                }
            }
        } else {
            let name = player == "Spotify" ? "Spotify" : "Music"
            let bundle = name == "Music" ? "com.apple.Music" : "com.spotify.client"
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { title = "Open \(name) to play"; available = false; return }
            let script = "tell application \"\(name)\"\nreturn {name of current track, artist of current track, (player state as string)}\nend tell"
            var error: NSDictionary?; let reply = NSAppleScript(source: script)?.executeAndReturnError(&error)
            if error != nil { status = "Allow Crest to control \(name) in System Settings → Privacy & Security → Automation."; available = false; return }
            title = reply?.atIndex(1)?.stringValue ?? "Nothing playing"; artist = reply?.atIndex(2)?.stringValue ?? ""; playing = reply?.atIndex(3)?.stringValue == "playing"; available = true
        }
    }
    func control(_ action: String) {
        guard enabled else { return }
        if player == "System" {
            let id = action == "next" ? 4 : action == "previous" ? 5 : 2
            if command?(id, nil) != true { status = "This player did not accept the command." }
        } else {
            let name = player == "Spotify" ? "Spotify" : "Music"
            let verb = action == "next" ? "next track" : action == "previous" ? "previous track" : "playpause"
            var error: NSDictionary?; NSAppleScript(source: "tell application \"\(name)\" to \(verb)")?.executeAndReturnError(&error)
            if error != nil { status = "Player command unavailable. Check Automation permission." }
        }
        refresh()
    }
}
