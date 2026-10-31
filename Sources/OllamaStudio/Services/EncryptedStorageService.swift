import Foundation
import CryptoKit
import Security

/// Provides crash-safe, AES-GCM 256-bit encrypted persistence at rest for all chats, settings,
/// custom model specs, and soft-deleted Trash items, with automatic rolling backups.
public final class EncryptedStorageService {
    public static let shared = EncryptedStorageService()

    private let fileManager = FileManager.default
    private let keychainAccount = "com.ollamastudio.local.masterkey"
    private let queue = DispatchQueue(label: "com.ollamastudio.storage", qos: .userInitiated)

    public struct PersistedVault: Codable {
        public var schemaVersion: Int = 2
        public var savedAt: Date = Date()
        public var conversations: [Conversation]
        public var modelDefaultDials: [String: ModelDials]
        public var serverConfig: ServerConfig
        public var trashedItems: [TrashedEntity]
        public var savedBuilderSpecs: [ModelBuilderSpec]
    }

    public var appSupportDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("OllamaStudio", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public var vaultFileURL: URL {
        appSupportDirectory.appendingPathComponent("vault.enc")
    }

    public var backupsDirectoryURL: URL {
        let dir = appSupportDirectory.appendingPathComponent("Backups", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private init() {}

    // MARK: - Save & Load Encrypted Vault

    public func saveVault(_ vault: PersistedVault) throws {
        try queue.sync {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let plaintext = try encoder.encode(vault)
            let key = try loadOrCreateSymmetricKey()
            let sealedBox = try AES.GCM.seal(plaintext, using: key)
            guard let combined = sealedBox.combined else {
                throw NSError(domain: "OllamaStudioVault", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to seal encrypted archive."])
            }

            // Atomic write to prevent corruption if power or app dies mid-save
            let tempURL = appSupportDirectory.appendingPathComponent("vault.tmp")
            try combined.write(to: tempURL, options: .atomic)
            if fileManager.fileExists(atPath: vaultFileURL.path) {
                _ = try? fileManager.replaceItemAt(vaultFileURL, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: vaultFileURL)
            }
        }
    }

    public func loadVault() -> PersistedVault? {
        queue.sync {
            guard fileManager.fileExists(atPath: vaultFileURL.path),
                  let encryptedData = try? Data(contentsOf: vaultFileURL),
                  let key = try? loadOrCreateSymmetricKey(),
                  let sealedBox = try? AES.GCM.SealedBox(combined: encryptedData),
                  let plaintext = try? AES.GCM.open(sealedBox, using: key) else {
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try? decoder.decode(PersistedVault.self, from: plaintext)
        }
    }

    /// Creates a timestamped backup before major operations or updates (keeps last 10 snapshots)
    public func createAutomaticSnapshot() {
        queue.async { [weak self] in
            guard let self = self, self.fileManager.fileExists(atPath: self.vaultFileURL.path) else { return }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let dest = self.backupsDirectoryURL.appendingPathComponent("vault-\(stamp).enc")
            try? self.fileManager.copyItem(at: self.vaultFileURL, to: dest)

            // Prune old snapshots beyond 10
            if let files = try? self.fileManager.contentsOfDirectory(
                at: self.backupsDirectoryURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            ), files.count > 10 {
                let sorted = files.sorted { a, b in
                    let d1 = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    let d2 = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                    return d1 < d2
                }
                for fileToDelete in sorted.prefix(files.count - 10) {
                    try? self.fileManager.removeItem(at: fileToDelete)
                }
            }
        }
    }

    // MARK: - Keychain Master Key Management (Fallback to Local Protected Key if Keychain Prompts Are Restricted)

    private func loadOrCreateSymmetricKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let keyData = item as? Data, keyData.count == 32 {
            return SymmetricKey(data: keyData)
        }

        // Fallback file key in Application Support with 0600 POSIX permissions so CI/unsigned builds never hang on Keychain modal
        let fallbackKeyURL = appSupportDirectory.appendingPathComponent(".master_key")
        if let diskKeyData = try? Data(contentsOf: fallbackKeyURL), diskKeyData.count == 32 {
            return SymmetricKey(data: diskKeyData)
        }

        let newKey = SymmetricKey(size: .bits256)
        let rawData = newKey.withUnsafeBytes { Data($0) }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: rawData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        _ = SecItemAdd(addQuery as CFDictionary, nil)

        try? rawData.write(to: fallbackKeyURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fallbackKeyURL.path)
        return newKey
    }
}
