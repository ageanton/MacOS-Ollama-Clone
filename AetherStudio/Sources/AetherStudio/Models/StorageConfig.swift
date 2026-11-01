import Foundation

public struct ExternalVolumeStatus: Equatable {
    public let isExternal: Bool
    public let volumeName: String
    public let mountPoint: String
    public let isMountedAndWritable: Bool
    public let freeSpaceGB: Double?
    public let totalSpaceGB: Double?

    public var statusText: String {
        if !isExternal {
            if let free = freeSpaceGB {
                return String(format: "Internal Drive · %.1f GB free", free)
            }
            return "Internal System Drive"
        }
        if isMountedAndWritable {
            if let free = freeSpaceGB, let total = totalSpaceGB {
                return String(format: "External '%@' Connected · %.1f / %.0f GB free", volumeName, free, total)
            }
            return "External '\(volumeName)' Connected & Ready"
        } else {
            return "External '\(volumeName)' Disconnected"
        }
    }
}

public struct StorageConfig: Codable, Equatable {
    public var modelsDirectoryPath: String
    public var isUsingExternalDrive: Bool
    public var rememberedExternalModelsPath: String
    public var rememberedExternalVolumeName: String
    public var hostAddress: String
    public var port: Int
    public var flashAttention: Bool

    public init() {
        let savedPath = UserDefaults.standard.string(forKey: "aether.modelsPath")
        let defaultPath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.ollama/models"
        self.modelsDirectoryPath = savedPath ?? defaultPath
        self.isUsingExternalDrive = UserDefaults.standard.bool(forKey: "aether.isExternal")
        self.rememberedExternalModelsPath = UserDefaults.standard.string(forKey: "aether.extPath") ?? ""
        self.rememberedExternalVolumeName = UserDefaults.standard.string(forKey: "aether.extVol") ?? ""
        self.hostAddress = "127.0.0.1"
        self.port = 11434
        self.flashAttention = false
    }

    public var baseURLString: String {
        "http://\(hostAddress):\(port)"
    }

    public mutating func updateModelsPath(_ newPath: String) {
        let clean = Self.normalizePath(newPath)
        self.modelsDirectoryPath = clean

        if clean.hasPrefix("/Volumes/") {
            self.isUsingExternalDrive = true
            self.rememberedExternalModelsPath = clean
            let parts = clean.components(separatedBy: "/").filter { !$0.isEmpty }
            if parts.count >= 2 {
                self.rememberedExternalVolumeName = parts[1]
            }
        } else {
            self.isUsingExternalDrive = false
        }
        save()
    }

    public func save() {
        UserDefaults.standard.set(modelsDirectoryPath, forKey: "aether.modelsPath")
        UserDefaults.standard.set(isUsingExternalDrive, forKey: "aether.isExternal")
        UserDefaults.standard.set(rememberedExternalModelsPath, forKey: "aether.extPath")
        UserDefaults.standard.set(rememberedExternalVolumeName, forKey: "aether.extVol")
    }

    public static func normalizePath(_ raw: String) -> String {
        var path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return raw }
        path = (path as NSString).standardizingPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue {
            // If user passed a file, use its parent directory
            path = (path as NSString).deletingLastPathComponent
        }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        let last = url.lastPathComponent.lowercased()
        let root = (last == "manifests" || last == "blobs") ? url.deletingLastPathComponent() : url

        // Check immediate manifests & blobs
        let m = root.appendingPathComponent("manifests", isDirectory: true)
        let b = root.appendingPathComponent("blobs", isDirectory: true)
        var md: ObjCBool = false, bd: ObjCBool = false
        if fm.fileExists(atPath: m.path, isDirectory: &md), md.boolValue,
           fm.fileExists(atPath: b.path, isDirectory: &bd), bd.boolValue {
            return root.path
        }

        // Check immediate /models subfolder
        let sub = root.appendingPathComponent("models", isDirectory: true)
        if fm.fileExists(atPath: sub.path, isDirectory: &isDir), isDir.boolValue {
            let sm = sub.appendingPathComponent("manifests", isDirectory: true)
            let sb = sub.appendingPathComponent("blobs", isDirectory: true)
            if fm.fileExists(atPath: sm.path, isDirectory: &md), md.boolValue,
               fm.fileExists(atPath: sb.path, isDirectory: &bd), bd.boolValue {
                return sub.path
            }
        }

        return root.path
    }

    public func inspectStorageDriveStatus() -> ExternalVolumeStatus {
        let fm = FileManager.default
        let isVolumes = modelsDirectoryPath.hasPrefix("/Volumes/")
        let isExt = isVolumes || isUsingExternalDrive

        var volName = rememberedExternalVolumeName
        var mountPoint = ""

        if isVolumes {
            let parts = modelsDirectoryPath.components(separatedBy: "/").filter { !$0.isEmpty }
            if parts.count >= 2 {
                volName = parts[1]
                mountPoint = "/Volumes/\(parts[1])"
            }
        }

        let volExists = isVolumes ? fm.fileExists(atPath: mountPoint) : true
        let pathExists = fm.fileExists(atPath: modelsDirectoryPath)

        var freeGB: Double? = nil
        var totalGB: Double? = nil
        let probe = pathExists ? modelsDirectoryPath : mountPoint

        if volExists && !probe.isEmpty, let attrs = try? fm.attributesOfFileSystem(forPath: probe) {
            if let f = attrs[.systemFreeSize] as? NSNumber {
                freeGB = f.doubleValue / 1_073_741_824.0
            }
            if let t = attrs[.systemSize] as? NSNumber {
                totalGB = t.doubleValue / 1_073_741_824.0
            }
        }

        return ExternalVolumeStatus(
            isExternal: isExt,
            volumeName: volName.isEmpty ? "External Drive" : volName,
            mountPoint: mountPoint,
            isMountedAndWritable: volExists && (pathExists || isVolumes),
            freeSpaceGB: freeGB,
            totalSpaceGB: totalGB
        )
    }

    public func toEnvironmentVariables() -> [String: String] {
        var env: [String: String] = [
            "OLLAMA_HOST": "\(hostAddress):\(port)",
            "OLLAMA_ORIGINS": "*",
            "OLLAMA_MODELS": modelsDirectoryPath,
            "OLLAMA_KEEP_ALIVE": "15m"
        ]
        if flashAttention {
            env["OLLAMA_FLASH_ATTENTION"] = "1"
        }
        return env
    }
}
