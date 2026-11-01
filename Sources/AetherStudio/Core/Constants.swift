import Foundation

public enum AetherConstants {
    public static let appName = "Aether Studio"
    public static let version = "1.0.0"
    public static let buildNumber = "100"
    public static let bundleID = "com.aether.studio"
    public static let defaultPort: Int = 11434
    public static let defaultHost: String = "127.0.0.1"
    
    public static var defaultInternalModelsPath: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.ollama/models"
    }
    
    public static var defaultOllamaHome: String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/.ollama"
    }
}
