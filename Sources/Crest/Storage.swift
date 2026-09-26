import AppKit
import CryptoKit
import Security
import LocalAuthentication
import CrestCore

struct TrayItem: Identifiable, Codable {
    var id = UUID()
    var path: String
    var bookmark: Data?
    var date = Date()
    var url: URL { if let bookmark { var stale = false; if let url = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, bookmarkDataIsStale: &stale) { return url } }; return URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }
}
@MainActor final class TrayService: ObservableObject {
    @Published var items: [TrayItem] = []
    @Published var error: String?
    @Published var feedback: String?
    @Published private(set) var canUndo = false
    var onInteraction: ((Bool) -> Void)?
    private var removed: [(Int, TrayItem)] = []
    private var unreadableData: Data?
    private var savedFileUnreadable = false
    private let file = CrestPaths.root.appendingPathComponent("tray.json")
    init() {
        if FileManager.default.fileExists(atPath: file.path) {
            do { let data = try Data(contentsOf: file); unreadableData = data; items = try JSONDecoder().decode([TrayItem].self, from: data); unreadableData = nil }
            catch { savedFileUnreadable = unreadableData == nil; self.error = savedFileUnreadable ? "The saved tray cannot be read. Changes will not be saved until file access is restored and Crest restarts." : "The tray could not be loaded. Its saved file will be backed up before any changes." }
        }
    }
    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && FileManager.default.fileExists(atPath: url.path) && !items.contains(where: { $0.url == url }) {
            items.insert(TrayItem(path: url.path, bookmark: try? url.bookmarkData(options: .minimalBookmark)), at: 0)
        }
        feedback = nil; save()
    }
    func remove(_ ids: Set<UUID>) { removed = items.enumerated().filter { ids.contains($0.element.id) }.map { ($0.offset, $0.element) }; items.removeAll { ids.contains($0.id) }; canUndo = !removed.isEmpty; save(); feedback = "Removed from tray. Originals are unchanged." }
    func undoRemoval() {
        for (index, item) in removed where !items.contains(where: { $0.id == item.id || $0.url == item.url }) { items.insert(item, at: min(index, items.count)) }
        removed = []; canUndo = false; save(); feedback = "Restored to tray."
    }
    func save() {
        guard !savedFileUnreadable else { return }
        do {
            if let unreadableData { try CrestPaths.save(unreadableData, to: CrestPaths.root.appendingPathComponent("tray-recovery-\(UUID().uuidString).json")); self.unreadableData = nil }
            try CrestPaths.save(JSONEncoder().encode(items), to: file); error = nil
        } catch { self.error = error.localizedDescription }
    }
    func choose() { onInteraction?(true); defer { onInteraction?(false) }; NSApp.activate(ignoringOtherApps: true); let panel = NSOpenPanel(); panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; if panel.runModal() == .OK { add(panel.urls) } }
    func copy(_ ids: Set<UUID>) {
        let urls = items.filter { ids.contains($0.id) && $0.exists }.map { $0.url as NSURL }
        guard !urls.isEmpty else { feedback = "The selected files are unavailable."; return }
        NSPasteboard.general.clearContents(); let success = NSPasteboard.general.writeObjects(urls)
        feedback = success ? "Copied \(urls.count) \(urls.count == 1 ? "item" : "items")." : "Could not copy the selected files."
    }
    func share(_ ids: Set<UUID>) { Sharing.airDrop(items.filter { ids.contains($0.id) && $0.exists }.map { $0.url }) }
}

@MainActor enum Sharing {
    static func airDrop(_ values: [Any]) {
        guard !values.isEmpty else { return }
        if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: values) { service.perform(withItems: values) }
        else if let view = NSApp.keyWindow?.contentView { NSSharingServicePicker(items: values).show(relativeTo: view.bounds, of: view, preferredEdge: .minY) }
    }
}

enum ClipboardKey {
    static func load(create: Bool, allowAuthentication: Bool = false) throws -> SymmetricKey {
        let context = LAContext(); context.interactionNotAllowed = !allowAuthentication
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.crest.clipboard", kSecAttrAccount as String: "local-v1", kSecReturnData as String: true, kSecUseAuthenticationContext as String: context]
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 { return SymmetricKey(data: data) }
        guard status == errSecItemNotFound && create else { throw NSError(domain: "Crest.Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Clipboard encryption key is unavailable. Existing history is preserved. Enable recording again in Settings to allow macOS to request access."]) }
        let key = SymmetricKey(size: .bits256); let bytes = key.withUnsafeBytes { Data($0) }
        var add = query; add.removeValue(forKey: kSecReturnData as String); add[kSecValueData as String] = bytes; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw NSError(domain: "Crest.Keychain", code: Int(added)) }; return key
    }
}
@MainActor final class ClipboardService: ObservableObject {
    @Published var items: [ClipItem] = []
    @Published var enabled = false
    @Published var loading = false
    @Published var error: String?
    @Published var feedback: String?
    @Published var days: Int = UserDefaults.standard.object(forKey: "retention") as? Int ?? 30 { didSet { UserDefaults.standard.set(days, forKey: "retention"); prune(); persist() } }
    @Published var exclusions: String = UserDefaults.standard.string(forKey: "exclusions") ?? "" { didSet { UserDefaults.standard.set(exclusions, forKey: "exclusions") } }
    private var key: SymmetricKey?
    private var timer: Timer?
    private var count = NSPasteboard.general.changeCount
    private var lastPrune = Date()
    private var loadGeneration = 0
    private let file = CrestPaths.root.appendingPathComponent("clipboard.aesgcm")
    func setEnabled(_ value: Bool, allowAuthentication: Bool = false) {
        loadGeneration += 1; let generation = loadGeneration
        timer?.invalidate(); timer = nil
        if !value { enabled = false; loading = false; key = nil; items = []; UserDefaults.standard.set(false, forKey: "clipboardEnabled"); return }
        loading = true; enabled = false; error = nil
        let archive = file
        Task { [self] in
            let result = await Task.detached { () -> Result<(SymmetricKey, [ClipItem]), Error> in
                Result {
                    let exists = FileManager.default.fileExists(atPath: archive.path)
                    let key = try ClipboardKey.load(create: !exists, allowAuthentication: allowAuthentication)
                    let items = exists ? try ClipboardArchive.decode(EncryptedArchive.open(Data(contentsOf: archive), key: key)) : []
                    return (key, items)
                }
            }.value
            guard loadGeneration == generation else { return }
            loading = false
            switch result {
            case .success(let (loadedKey, loadedItems)):
                key = loadedKey; items = loadedItems; prune(); enabled = true; count = NSPasteboard.general.changeCount
                UserDefaults.standard.set(true, forKey: "clipboardEnabled")
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.poll() } }
            case .failure(let failure): error = failure.localizedDescription; enabled = false; key = nil; items = []
            }
        }
    }
    private func poll() {
        if Date().timeIntervalSince(lastPrune) > 60 { prune(); persist(); lastPrune = Date() }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != count else { return }; count = pasteboard.changeCount
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard bundle != Bundle.main.bundleIdentifier, ClipboardPolicy.shouldCapture(bundle: bundle, types: types, exclusions: exclusions.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }) else { return }
        let item: ClipItem
        if let image = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff), image.count < 10_000_000 { item = ClipItem(image: image) }
        else if let text = pasteboard.string(forType: .string), !text.isEmpty, text.utf8.count < 1_000_000 { item = ClipItem(text: text) }
        else { return }
        if items.first?.text == item.text && items.first?.image == item.image { return }
        items.insert(item, at: 0); prune(); persist()
    }
    private func prune() {
        items = ClipItem.retained(items, days: days)
        var bytes = 0; var unpinned = 0
        items = items.filter { item in
            if item.pinned { return true }
            unpinned += 1; bytes += item.image?.count ?? item.text?.utf8.count ?? 0
            return unpinned <= 500 && bytes <= 100_000_000
        }
    }
    private func persist() {
        guard let key else { return }
        do { try CrestPaths.save(EncryptedArchive.seal(ClipboardArchive.encode(items), key: key), to: file) }
        catch { self.error = "History could not be saved: \(error.localizedDescription)" }
    }
    func pin(_ id: UUID) { if let index = items.firstIndex(where: { $0.id == id }) { items[index].pinned.toggle(); persist() } }
    func delete(_ ids: Set<UUID>) { items.removeAll { ids.contains($0.id) }; persist() }
    func copy(_ ids: Set<UUID>) {
        let selected = items.filter { ids.contains($0.id) }; let pasteboard = NSPasteboard.general
        guard !selected.isEmpty else { return }
        pasteboard.clearContents()
        if selected.allSatisfy({ $0.text != nil }) { pasteboard.setString(selected.compactMap(\.text).joined(separator: "\n"), forType: .string) }
        else {
            let objects = selected.map { clip -> NSPasteboardItem in
                let p = NSPasteboardItem(); if let image = clip.image, let bitmap = NSBitmapImageRep(data: image), let png = bitmap.representation(using: .png, properties: [:]) { p.setData(png, forType: .png) }
                if let text = clip.text { p.setString(text, forType: .string) }; return p
            }
            pasteboard.writeObjects(objects)
        }
        count = pasteboard.changeCount
        feedback = "Copied \(selected.count) \(selected.count == 1 ? "item" : "items")."
    }
    func share(_ ids: Set<UUID>) {
        let values: [Any] = items.filter { ids.contains($0.id) }.compactMap { item in if let text = item.text { return text }; if let data = item.image { return NSImage(data: data) }; return nil }
        Sharing.airDrop(values)
    }
}

struct DownloadActivity: Identifiable {
    var id: String { path }
    var path: String
    var bytes: Int64
    var bytesPerSecond: Double
}
@MainActor final class FolderService: ObservableObject {
    @Published var downloads: [DownloadActivity] = []
    @Published var status = "Choose folders in Settings to watch screenshots and downloads."
    private var snapshots: [String: (Int64, Date)] = [:]
    private var known = Set<String>()
    private var pending = Set<String>()
    private var timer: Timer?
    private var folder: URL?
    private var screenshots = false
    private var preferenceKey: String?
    private weak var tray: TrayService?
    func choose(tray: TrayService, screenshots: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel(); picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.message = screenshots ? "Choose your screenshot folder. Only new screenshots will be added." : "Choose Downloads. Partial download sizes and speed will be shown."
        if picker.runModal() == .OK, let url = picker.url { start(url, tray: tray, screenshots: screenshots) }
    }
    func start(_ url: URL, tray: TrayService, screenshots: Bool) {
        stop(); self.tray = tray; folder = url; self.screenshots = screenshots
        preferenceKey = screenshots ? "screenshotsBookmark" : "downloadsBookmark"
        if let bookmark = try? url.bookmarkData(options: .minimalBookmark), let preferenceKey { UserDefaults.standard.set(bookmark, forKey: preferenceKey) }
        known = Set(((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []))
        status = "Watching \(url.lastPathComponent)"; scan()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.scan() } }
    }
    func restore(tray: TrayService, screenshots: Bool) {
        let key = screenshots ? "screenshotsBookmark" : "downloadsBookmark"
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: .withoutUI, bookmarkDataIsStale: &stale) { start(url, tray: tray, screenshots: screenshots) }
        else { status = "Saved folder is unavailable. Choose it again." }
    }
    func stop() { timer?.invalidate(); timer = nil; folder = nil; downloads = []; snapshots = [:]; pending = []; status = "Folder watching off"; if let preferenceKey { UserDefaults.standard.removeObject(forKey: preferenceKey) }; preferenceKey = nil }
    private func scan() {
        guard let folder else { return }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey], options: .skipsHiddenFiles) else { status = "Folder access unavailable. Choose the folder again."; return }
        var active: [DownloadActivity] = []; let now = Date(); var next: [String: (Int64, Date)] = [:]
        let names = Set(urls.map(\.lastPathComponent))
        for url in urls {
            let name = url.lastPathComponent
            let temporary = ["crdownload", "part", "download"].contains(url.pathExtension)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true else { continue }
            let size = Int64(values?.fileSize ?? 0); let previous = snapshots[name]; next[name] = (size, now)
            if temporary && !screenshots && values?.isRegularFile == true {
                let speed = previous.map { max(0, Double(size - $0.0) / max(0.1, now.timeIntervalSince($0.1))) } ?? 0
                active.append(DownloadActivity(path: name, bytes: size, bytesPerSecond: speed)); pending.insert(url.deletingPathExtension().lastPathComponent)
            } else if !known.contains(name), values?.isRegularFile == true {
                let isScreenshot: Bool = {
                    guard screenshots else { return true }
                    if let item = MDItemCreate(nil, url.path as CFString), let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool, value { return true }
                    return (name.hasPrefix("Screenshot ") || name.hasPrefix("Screen Shot ")) && ["png", "jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased())
                }()
                if previous?.0 == size, size > 0, isScreenshot { tray?.add([url]); known.insert(name); pending.remove(name) }
            }
        }
        known.formIntersection(names); snapshots = next; downloads = active.sorted { $0.path < $1.path }
    }
}
