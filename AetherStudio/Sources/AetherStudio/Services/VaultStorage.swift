import Foundation

public struct PersistedVault: Codable {
    public var conversations: [Conversation]
    public var modelDefaults: [String: SamplingDials]

    public init(conversations: [Conversation] = [], modelDefaults: [String: SamplingDials] = [:]) {
        self.conversations = conversations
        self.modelDefaults = modelDefaults
    }
}

public final class VaultStorage {
    public static let shared = VaultStorage()

    private let fileURL: URL

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let aetherDir = appSupport.appendingPathComponent("AetherStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: aetherDir, withIntermediateDirectories: true)
        self.fileURL = aetherDir.appendingPathComponent("vault.json")
    }

    public func loadVault() -> PersistedVault {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return PersistedVault()
        }
        return (try? JSONDecoder().decode(PersistedVault.self, from: data)) ?? PersistedVault()
    }

    public func saveVault(_ vault: PersistedVault) {
        guard let data = try? JSONEncoder().encode(vault) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
