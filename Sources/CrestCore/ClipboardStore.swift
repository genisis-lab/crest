import Foundation
import CryptoKit

public enum ClipboardStore {
    /// Read the archive before touching Keychain. An unreadable file is never treated as a new history.
    public static func load(from file: URL, keyProvider: (Bool) throws -> SymmetricKey) throws -> (SymmetricKey, [ClipItem]) {
        let encrypted: Data?
        do { encrypted = try Data(contentsOf: file) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { encrypted = nil }
        let key = try keyProvider(encrypted == nil)
        let items = try encrypted.map { try ClipboardArchive.decode(EncryptedArchive.open($0, key: key)) } ?? []
        return (key, items)
    }
}
