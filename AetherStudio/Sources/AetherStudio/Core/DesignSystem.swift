import SwiftUI
import AppKit

// MARK: - Themes

public enum AetherThemeID: String, CaseIterable, Codable, Identifiable {
    case botanicalSage = "botanical_sage"
    case kyotoHinoki = "kyoto_hinoki"
    case braunSilver = "braun_silver"
    case nordicFjord = "nordic_fjord"
    case obsidianEmerald = "obsidian_emerald"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .botanicalSage: return "Botanical Sage"
        case .kyotoHinoki: return "Kyoto Hinoki"
        case .braunSilver: return "Braun Industrial"
        case .nordicFjord: return "Nordic Fjord (Dark)"
        case .obsidianEmerald: return "Obsidian Emerald (Dark)"
        }
    }

    public var subtitle: String {
        switch self {
        case .botanicalSage: return "Things 3 inspired sage canvas, paper white card, forest green cues."
        case .kyotoHinoki: return "Warm hinoki cypress frame, crisp wasabi accents, soothing reading surface."
        case .braunSilver: return "Dieter Rams silver-grey anodized chassis with safety orange accents."
        case .nordicFjord: return "Deep midnight fjord canvas with elevated slate cards and glacier blue."
        case .obsidianEmerald: return "Pitch carbon matte surface with crisp phosphor emerald status indicators."
        }
    }
}

public struct AetherPalette: Equatable {
    public let windowCanvas: Color
    public let cardSurface: Color
    public let elevatedSurface: Color
    public let subtleSurface: Color
    public let codeSurface: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let mutedText: Color
    public let accent: Color
    public let accentSoft: Color
    public let hairlineBorder: Color
    public let cardRing: Color
    public let statusHealthy: Color
    public let statusWarning: Color
    public let statusDanger: Color
    public let isDark: Bool
}

extension Color {
    public init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

public enum AetherMetrics {
    public static let windowCornerRadius: CGFloat = 12.0
    public static let cardCornerRadius: CGFloat = 10.0
    public static let controlCornerRadius: CGFloat = 6.0
    public static let pillCornerRadius: CGFloat = 4.5
    public static let sidebarWidth: CGFloat = 248.0
    public static let inspectorWidth: CGFloat = 340.0
    public static let trafficLightHeight: CGFloat = 36.0
}

@MainActor
public final class ThemeCoordinator: ObservableObject {
    @Published public var selectedTheme: AetherThemeID {
        didSet { UserDefaults.standard.set(selectedTheme.rawValue, forKey: "aether.theme") }
    }
    @Published public var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "aether.fontSize") }
    }

    public init() {
        let saved = UserDefaults.standard.string(forKey: "aether.theme") ?? AetherThemeID.botanicalSage.rawValue
        self.selectedTheme = AetherThemeID(rawValue: saved) ?? .botanicalSage
        let fs = UserDefaults.standard.double(forKey: "aether.fontSize")
        self.fontSize = (fs >= 12 && fs <= 20) ? fs : 14.5
    }

    public func palette(for colorScheme: ColorScheme) -> AetherPalette {
        switch selectedTheme {
        case .botanicalSage:
            return AetherPalette(
                windowCanvas: Color(hex: 0xDDE6DF),
                cardSurface: Color(hex: 0xFFFFFF),
                elevatedSurface: Color(hex: 0xF6FAF7),
                subtleSurface: Color(hex: 0xECF3ED),
                codeSurface: Color(hex: 0xF1F5F2),
                primaryText: Color(hex: 0x121A15),
                secondaryText: Color(hex: 0x3E5247),
                mutedText: Color(hex: 0x64796E),
                accent: Color(hex: 0x1B5E38),
                accentSoft: Color(hex: 0x1B5E38, alpha: 0.12),
                hairlineBorder: Color(hex: 0xC8D7CD),
                cardRing: Color(hex: 0x121A15, alpha: 0.08),
                statusHealthy: Color(hex: 0x1E7A46),
                statusWarning: Color(hex: 0xC6691A),
                statusDanger: Color(hex: 0xC83226),
                isDark: false
            )
        case .kyotoHinoki:
            return AetherPalette(
                windowCanvas: Color(hex: 0xECE5D8),
                cardSurface: Color(hex: 0xFDFBF7),
                elevatedSurface: Color(hex: 0xFFFFFF),
                subtleSurface: Color(hex: 0xF4EFE5),
                codeSurface: Color(hex: 0xF3ECE0),
                primaryText: Color(hex: 0x191815),
                secondaryText: Color(hex: 0x48443D),
                mutedText: Color(hex: 0x736E64),
                accent: Color(hex: 0x2A7A44),
                accentSoft: Color(hex: 0x2A7A44, alpha: 0.13),
                hairlineBorder: Color(hex: 0xDCD1C0),
                cardRing: Color(hex: 0x191815, alpha: 0.08),
                statusHealthy: Color(hex: 0x2A7A44),
                statusWarning: Color(hex: 0xCA6418),
                statusDanger: Color(hex: 0xC33025),
                isDark: false
            )
        case .braunSilver:
            return AetherPalette(
                windowCanvas: Color(hex: 0xDFDFDC),
                cardSurface: Color(hex: 0xF8F8F6),
                elevatedSurface: Color(hex: 0xFFFFFF),
                subtleSurface: Color(hex: 0xECECE8),
                codeSurface: Color(hex: 0xEAEAE6),
                primaryText: Color(hex: 0x111110),
                secondaryText: Color(hex: 0x444440),
                mutedText: Color(hex: 0x6E6E68),
                accent: Color(hex: 0xEA580C),
                accentSoft: Color(hex: 0xEA580C, alpha: 0.14),
                hairlineBorder: Color(hex: 0xCCCCCC),
                cardRing: Color(hex: 0x000000, alpha: 0.09),
                statusHealthy: Color(hex: 0x237841),
                statusWarning: Color(hex: 0xD97706),
                statusDanger: Color(hex: 0xDC2626),
                isDark: false
            )
        case .nordicFjord:
            return AetherPalette(
                windowCanvas: Color(hex: 0x0E1626),
                cardSurface: Color(hex: 0x1B263B),
                elevatedSurface: Color(hex: 0x23324C),
                subtleSurface: Color(hex: 0x24344E),
                codeSurface: Color(hex: 0x131C2E),
                primaryText: Color(hex: 0xF0F4F8),
                secondaryText: Color(hex: 0xCBD5E1),
                mutedText: Color(hex: 0x8FA3BA),
                accent: Color(hex: 0x38BDF8),
                accentSoft: Color(hex: 0x38BDF8, alpha: 0.18),
                hairlineBorder: Color(hex: 0x2D3F5C),
                cardRing: Color(hex: 0xFFFFFF, alpha: 0.08),
                statusHealthy: Color(hex: 0x34D399),
                statusWarning: Color(hex: 0xFBBF24),
                statusDanger: Color(hex: 0xF87171),
                isDark: true
            )
        case .obsidianEmerald:
            return AetherPalette(
                windowCanvas: Color(hex: 0x0B0E0D),
                cardSurface: Color(hex: 0x131816),
                elevatedSurface: Color(hex: 0x1A221E),
                subtleSurface: Color(hex: 0x1D2622),
                codeSurface: Color(hex: 0x0D1210),
                primaryText: Color(hex: 0xECFDF5),
                secondaryText: Color(hex: 0xA7F3D0),
                mutedText: Color(hex: 0x6EE7B7, alpha: 0.7),
                accent: Color(hex: 0x10B981),
                accentSoft: Color(hex: 0x10B981, alpha: 0.20),
                hairlineBorder: Color(hex: 0x24332D),
                cardRing: Color(hex: 0x10B981, alpha: 0.14),
                statusHealthy: Color(hex: 0x10B981),
                statusWarning: Color(hex: 0xF59E0B),
                statusDanger: Color(hex: 0xEF4444),
                isDark: true
            )
        }
    }
}
