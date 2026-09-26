import Foundation

public struct DownloadSize: Equatable, Sendable {
    public let bytes: Int64
    public let expected: Int64?
    public var fraction: Double? {
        guard let expected, expected > 0, bytes >= 0, bytes <= expected else { return nil }
        return Double(bytes) / Double(expected)
    }
    public init(bytes: Int64, expected: Int64? = nil) { self.bytes = bytes; self.expected = expected }
}

public enum DownloadInspection {
    public static let temporaryExtensions: Set<String> = ["crdownload", "part", "download"]
    /// Inspects the selected download folder only. Never opens browser databases or follows symlinks.
    public static func size(at url: URL) -> DownloadSize? {
        guard temporaryExtensions.contains(url.pathExtension.lowercased()),
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]), values.isSymbolicLink != true else { return nil }
        if values.isRegularFile == true { return DownloadSize(bytes: Int64(values.fileSize ?? 0)) }
        guard values.isDirectory == true, url.pathExtension.lowercased() == "download",
              let children = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey], options: .skipsHiddenFiles), children.count <= 128 else { return nil }
        var bytes: Int64 = 0
        var expected: Int64?
        for child in children {
            guard let value = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]), value.isRegularFile == true, value.isSymbolicLink != true else { continue }
            if child.lastPathComponent == "Info.plist" {
                // Safari metadata is optional and version-dependent. Unknown totals remain unknown.
                if (value.fileSize ?? 0) <= 262_144, let data = try? Data(contentsOf: child),
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let total = plist["DownloadEntryProgressTotalToLoad"] as? NSNumber,
                   CFGetTypeID(total) != CFBooleanGetTypeID(), total.int64Value > 0 { expected = total.int64Value }
            } else if child.lastPathComponent != "ResumeData" {
                let (sum, overflow) = bytes.addingReportingOverflow(Int64(value.fileSize ?? 0))
                guard !overflow else { return nil }; bytes = sum
            }
        }
        return DownloadSize(bytes: bytes, expected: expected)
    }
}
