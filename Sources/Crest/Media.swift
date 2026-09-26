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
    private var refreshing = false
    private var artworkURL: String?
    private var generation = 0
    private let automation = PlayerAutomation()
    func configure(enabled: Bool, player: String) {
        timer?.invalidate(); timer = nil; generation += 1
        self.player = player; self.enabled = enabled; available = false
        title = "Nothing playing"; artist = "Connect a player in Settings"; playing = false; artwork = nil; artworkURL = nil
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
        let requestGeneration = generation
        if player == "System" {
            guard let getInfo else { status = "System player API unavailable. Select Music or Spotify."; return }
            getInfo(.main) { [weak self] dictionary in
                Task { @MainActor in
                    guard let self, self.enabled, self.generation == requestGeneration, self.player == "System" else { return }
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
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { title = "Open \(name) to play"; artist = ""; playing = false; artwork = nil; artworkURL = nil; available = false; return }
            guard !refreshing else { return }; refreshing = true
            Task { [weak self] in
                guard let self else { return }
                let track = await automation.metadata(player: name)
                refreshing = false
                guard enabled, generation == requestGeneration, player == name else { return }
                guard let track else { status = "Player metadata unavailable. Check playback and Automation permission."; available = false; playing = false; artwork = nil; artworkURL = nil; return }
                title = track.title; artist = track.artist; playing = track.playing; available = true
                status = "\(name) connected"
                if let data = track.image { artwork = NSImage(data: data) }
                else if let link = track.imageURL, link != artworkURL, let url = URL(string: link), url.scheme == "https" {
                    artworkURL = link; artwork = nil
                    var request = URLRequest(url: url); request.timeoutInterval = 8
                    if let (data, response) = try? await URLSession.shared.data(for: request),
                       (response as? HTTPURLResponse)?.statusCode == 200, data.count < 10_000_000,
                       artworkURL == link, enabled, generation == requestGeneration, player == name { artwork = NSImage(data: data) }
                } else if track.imageURL == nil { artwork = nil; artworkURL = nil }
            }
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
            Task { [weak self] in
                guard let self else { return }
                let success = await automation.command(player: name, verb: verb)
                if !success { status = "Player command unavailable. Check Automation permission." }
                refresh()
            }
        }
        refresh()
    }
}

private struct PlayerMetadata: Sendable { var title: String; var artist: String; var playing: Bool; var image: Data?; var imageURL: String? }
private actor PlayerAutomation {
    func metadata(player: String) -> PlayerMetadata? {
        let art = player == "Spotify" ? "artwork url of current track" : "data of artwork 1 of current track"
        let script = "with timeout of 4 seconds\ntell application \"\(player)\"\nset trackArt to missing value\ntry\nset trackArt to \(art)\nend try\nreturn {name of current track, artist of current track, (player state as string), trackArt}\nend tell\nend timeout"
        var error: NSDictionary?; let reply = NSAppleScript(source: script)?.executeAndReturnError(&error)
        guard error == nil, let reply else { return nil }
        return PlayerMetadata(title: reply.atIndex(1)?.stringValue ?? "Nothing playing", artist: reply.atIndex(2)?.stringValue ?? "", playing: reply.atIndex(3)?.stringValue == "playing", image: player == "Music" ? reply.atIndex(4)?.data : nil, imageURL: player == "Spotify" ? reply.atIndex(4)?.stringValue : nil)
    }
    func command(player: String, verb: String) -> Bool {
        var error: NSDictionary?
        NSAppleScript(source: "with timeout of 4 seconds\ntell application \"\(player)\" to \(verb)\nend timeout")?.executeAndReturnError(&error)
        return error == nil
    }
}
