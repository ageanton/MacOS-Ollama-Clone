set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/Models/DomainModels.swift
import Foundation
import SwiftUI
import AppKit
import CoreText

// MARK: - 6 Calibrated Architectural Themes (With True-Black #000000 Midnight Nord)
public enum AppThemeID: String, CaseIterable, Codable, Identifiable {
    case alabasterStudio = "Alabaster Studio"
    case warmEditorial = "Warm Editorial"
    case nordicFrost = "Nordic Frost"
    case botanicalSage = "Botanical Sage"
    case carbonSlate = "Carbon Slate"
    case midnightNord = "Midnight Nord"

    public var id: String { rawValue }

    public var subtitle: String {
        switch self {
        case .alabasterStudio: return "Soft architectural alabaster (#F7F8FA) with customizable studio canvas, accent & thinking box"
        case .warmEditorial: return "Unbleached gallery linen (#F4F0E6) with espresso ink and customizable studio palette"
        case .nordicFrost: return "Cool ice-slate (#EEF3F8) with deep navy typography and cobalt accents"
        case .botanicalSage: return "Calm organic daylight (#EEF4F0) with deep forest ink and eucalyptus accents"
        case .carbonSlate: return "Matte dark studio slate (#121316) with high-contrast silver ink and indigo accents"
        case .midnightNord: return "True-black OLED obsidian (#000000) with platinum typography, specular hairlines, and ice-cyan accents"
        }
    }

    public var supportsCustomPalette: Bool {
        self == .alabasterStudio || self == .warmEditorial
    }

    public var isDark: Bool {
        switch self {
        case .alabasterStudio, .warmEditorial, .nordicFrost, .botanicalSage: return false
        case .carbonSlate, .midnightNord: return true
        }
    }
}

// MARK: - Custom Palette Overrides for Alabaster Studio & Warm Editorial (Canvas, Accent & Thinking Box)
public struct ThemeColorOverride: Codable, Equatable {
    public var isCustomCanvasEnabled: Bool = false
    public var canvasRed: Double
    public var canvasGreen: Double
    public var canvasBlue: Double

    public var isCustomAccentEnabled: Bool = false
    public var accentRed: Double
    public var accentGreen: Double
    public var accentBlue: Double

    public var isCustomThinkingEnabled: Bool = false
    public var thinkingRed: Double
    public var thinkingGreen: Double
    public var thinkingBlue: Double

    public var isModified: Bool {
        isCustomCanvasEnabled || isCustomAccentEnabled || isCustomThinkingEnabled
    }

    public static let alabasterDefault = ThemeColorOverride(
        canvasRed: 0.969, canvasGreen: 0.973, canvasBlue: 0.980,
        accentRed: 0.110, accentGreen: 0.118, accentBlue: 0.145,
        thinkingRed: 0.918, thinkingGreen: 0.922, thinkingBlue: 0.937
    )

    public static let warmEditorialDefault = ThemeColorOverride(
        canvasRed: 0.957, canvasGreen: 0.941, canvasBlue: 0.902,
        accentRed: 0.604, accentGreen: 0.204, accentBlue: 0.071,
        thinkingRed: 0.894, thinkingGreen: 0.867, thinkingBlue: 0.812
    )
}

public struct CustomStudioPalettes: Codable, Equatable {
    public var alabaster: ThemeColorOverride = .alabasterDefault
    public var warmEditorial: ThemeColorOverride = .warmEditorialDefault
    public init() {}
}

// MARK: - Centralized Design Token System
public struct MotifTokens {
    public nonisolated(unsafe) static var customPalettes = CustomStudioPalettes()

    public let theme: AppThemeID
    public let isWindowActive: Bool

    public init(theme: AppThemeID, isWindowActive: Bool = true) {
        self.theme = theme
        self.isWindowActive = isWindowActive
    }

    public var activeOverride: ThemeColorOverride? {
        switch theme {
        case .alabasterStudio: return Self.customPalettes.alabaster
        case .warmEditorial: return Self.customPalettes.warmEditorial
        default: return nil
        }
    }

    private var hasCustomCanvas: Bool {
        activeOverride?.isCustomCanvasEnabled == true
    }

    public var hasCustomAccent: Bool {
        activeOverride?.isCustomAccentEnabled == true
    }

    private var hasCustomThinking: Bool {
        activeOverride?.isCustomThinkingEnabled == true
    }

    private var customCanvasLuminance: Double {
        guard let c = activeOverride else { return 0.95 }
        return 0.2126 * c.canvasRed + 0.7152 * c.canvasGreen + 0.0722 * c.canvasBlue
    }

    public var isEffectivelyDark: Bool {
        if hasCustomCanvas {
            return customCanvasLuminance < 0.42
        }
        return theme.isDark
    }

    public var canvasBackground: Color {
        if hasCustomCanvas, let c = activeOverride {
            return Color(red: c.canvasRed, green: c.canvasGreen, blue: c.canvasBlue)
        }
        switch theme {
        case .alabasterStudio: return Color(red: 0.969, green: 0.973, blue: 0.980)
        case .warmEditorial: return Color(red: 0.957, green: 0.941, blue: 0.902)
        case .nordicFrost: return Color(red: 0.933, green: 0.953, blue: 0.973)
        case .botanicalSage: return Color(red: 0.933, green: 0.957, blue: 0.941)
        case .carbonSlate: return Color(red: 0.071, green: 0.075, blue: 0.086)
        case .midnightNord: return Color(red: 0.000, green: 0.000, blue: 0.000) // True Pitch Black #000000
        }
    }

    public var surroundSubstrate: Color {
        if hasCustomCanvas { return sidebarBackground }
        switch theme {
        case .alabasterStudio: return Color(red: 0.945, green: 0.949, blue: 0.961)
        default: return sidebarBackground
        }
    }

    public var sidebarBackground: Color {
        if hasCustomCanvas, let c = activeOverride {
            let factor = isEffectivelyDark ? 0.78 : 0.962
            return Color(
                red: min(1.0, max(0.0, c.canvasRed * factor)),
                green: min(1.0, max(0.0, c.canvasGreen * factor)),
                blue: min(1.0, max(0.0, c.canvasBlue * factor))
            )
        }
        switch theme {
        case .alabasterStudio: return Color(red: 0.941, green: 0.945, blue: 0.957)
        case .warmEditorial: return Color(red: 0.918, green: 0.894, blue: 0.847)
        case .nordicFrost: return Color(red: 0.890, green: 0.918, blue: 0.945)
        case .botanicalSage: return Color(red: 0.886, green: 0.925, blue: 0.898)
        case .carbonSlate: return Color(red: 0.051, green: 0.055, blue: 0.063)
        case .midnightNord: return Color(red: 0.020, green: 0.024, blue: 0.031) // Deep Obsidian #050608
        }
    }

    public var elevatedSurface: Color {
        if hasCustomCanvas, let c = activeOverride {
            if isEffectivelyDark {
                return Color(
                    red: min(1.0, c.canvasRed + 0.055),
                    green: min(1.0, c.canvasGreen + 0.055),
                    blue: min(1.0, c.canvasBlue + 0.060)
                )
            } else {
                return Color(
                    red: max(0.0, c.canvasRed * 0.942),
                    green: max(0.0, c.canvasGreen * 0.942),
                    blue: max(0.0, c.canvasBlue * 0.948)
                )
            }
        }
        switch theme {
        case .alabasterStudio: return Color(red: 0.918, green: 0.922, blue: 0.937)
        case .warmEditorial: return Color(red: 0.894, green: 0.867, blue: 0.812)
        case .nordicFrost: return Color(red: 0.859, green: 0.894, blue: 0.929)
        case .botanicalSage: return Color(red: 0.855, green: 0.902, blue: 0.871)
        case .carbonSlate: return Color(red: 0.114, green: 0.118, blue: 0.137)
        case .midnightNord: return Color(red: 0.047, green: 0.055, blue: 0.071) // Carbon Onyx #0C0E12
        }
    }

    public var thinkingSurface: Color {
        if hasCustomThinking, let c = activeOverride {
            return Color(red: c.thinkingRed, green: c.thinkingGreen, blue: c.thinkingBlue)
        }
        return elevatedSurface
    }

    public var thinkingText: Color {
        if hasCustomThinking, let c = activeOverride {
            let lum = 0.2126 * c.thinkingRed + 0.7152 * c.thinkingGreen + 0.0722 * c.thinkingBlue
            return lum < 0.42
                ? Color(red: 0.85, green: 0.87, blue: 0.91)
                : Color(red: 0.24, green: 0.25, blue: 0.29)
        }
        return secondaryText
    }

    public var selectionPill: Color {
        if hasCustomCanvas, let c = activeOverride {
            if isEffectivelyDark {
                return Color(
                    red: min(1.0, c.canvasRed + 0.11),
                    green: min(1.0, c.canvasGreen + 0.11),
                    blue: min(1.0, c.canvasBlue + 0.12)
                )
            } else {
                return Color(
                    red: max(0.0, c.canvasRed * 0.895),
                    green: max(0.0, c.canvasGreen * 0.895),
                    blue: max(0.0, c.canvasBlue * 0.905)
                )
            }
        }
        switch theme {
        case .alabasterStudio: return Color(red: 0.875, green: 0.882, blue: 0.906)
        case .warmEditorial: return Color(red: 0.851, green: 0.816, blue: 0.749)
        case .nordicFrost: return Color(red: 0.800, green: 0.851, blue: 0.906)
        case .botanicalSage: return Color(red: 0.796, green: 0.863, blue: 0.820)
        case .carbonSlate: return Color(red: 0.169, green: 0.176, blue: 0.204)
        case .midnightNord: return Color(red: 0.082, green: 0.098, blue: 0.133)
        }
    }

    public var primaryText: Color {
        if hasCustomCanvas {
            return isEffectivelyDark
                ? Color(red: 0.949, green: 0.953, blue: 0.965)
                : Color(red: 0.075, green: 0.078, blue: 0.090)
        }
        switch theme {
        case .alabasterStudio: return Color(red: 0.075, green: 0.078, blue: 0.090)
        case .warmEditorial: return Color(red: 0.118, green: 0.102, blue: 0.090)
        case .nordicFrost: return Color(red: 0.059, green: 0.090, blue: 0.165)
        case .botanicalSage: return Color(red: 0.059, green: 0.149, blue: 0.106)
        case .carbonSlate: return Color(red: 0.949, green: 0.953, blue: 0.965)
        case .midnightNord: return Color(red: 0.949, green: 0.957, blue: 0.973)
        }
    }

    public var secondaryText: Color {
        if hasCustomCanvas {
            return isEffectivelyDark
                ? Color(red: 0.680, green: 0.695, blue: 0.735)
                : Color(red: 0.340, green: 0.350, blue: 0.385)
        }
        switch theme {
        case .alabasterStudio: return Color(red: 0.360, green: 0.369, blue: 0.404)
        case .warmEditorial: return Color(red: 0.420, green: 0.380, blue: 0.337)
        case .nordicFrost: return Color(red: 0.278, green: 0.333, blue: 0.412)
        case .botanicalSage: return Color(red: 0.255, green: 0.369, blue: 0.310)
        case .carbonSlate: return Color(red: 0.620, green: 0.631, blue: 0.675)
        case .midnightNord: return Color(red: 0.557, green: 0.588, blue: 0.659)
        }
    }

    public var mutedText: Color {
        if hasCustomCanvas {
            return isEffectivelyDark
                ? Color(red: 0.500, green: 0.515, blue: 0.555)
                : Color(red: 0.500, green: 0.510, blue: 0.545)
        }
        switch theme {
        case .alabasterStudio: return Color(red: 0.510, green: 0.518, blue: 0.555)
        case .warmEditorial: return Color(red: 0.560, green: 0.520, blue: 0.470)
        case .nordicFrost: return Color(red: 0.440, green: 0.495, blue: 0.575)
        case .botanicalSage: return Color(red: 0.420, green: 0.520, blue: 0.465)
        case .carbonSlate: return Color(red: 0.450, green: 0.460, blue: 0.505)
        case .midnightNord: return Color(red: 0.380, green: 0.420, blue: 0.500)
        }
    }

    public var hairline: Color {
        if hasCustomCanvas {
            return isEffectivelyDark ? Color.white.opacity(0.10) : Color.black.opacity(0.085)
        }
        switch theme {
        case .alabasterStudio: return Color.black.opacity(0.08)
        case .warmEditorial: return Color(red: 0.839, green: 0.808, blue: 0.749)
        case .nordicFrost: return Color(red: 0.792, green: 0.831, blue: 0.878)
        case .botanicalSage: return Color(red: 0.788, green: 0.847, blue: 0.808)
        case .carbonSlate: return Color.white.opacity(0.09)
        case .midnightNord: return Color.white.opacity(0.085)
        }
    }

    public var strongBorder: Color {
        if hasCustomCanvas {
            return isEffectivelyDark ? Color.white.opacity(0.24) : Color.black.opacity(0.22)
        }
        switch theme {
        case .alabasterStudio: return Color(red: 0.710, green: 0.718, blue: 0.755)
        case .warmEditorial: return Color(red: 0.690, green: 0.640, blue: 0.570)
        case .nordicFrost: return Color(red: 0.620, green: 0.690, blue: 0.780)
        case .botanicalSage: return Color(red: 0.610, green: 0.710, blue: 0.650)
        case .carbonSlate: return Color(red: 0.280, green: 0.295, blue: 0.340)
        case .midnightNord: return Color(red: 0.165, green: 0.200, blue: 0.275)
        }
    }

    public var accentAction: Color {
        if !isWindowActive { return mutedText }
        if hasCustomAccent, let c = activeOverride {
            return Color(red: c.accentRed, green: c.accentGreen, blue: c.accentBlue)
        }
        switch theme {
        case .alabasterStudio: return Color(red: 0.110, green: 0.118, blue: 0.145)
        case .warmEditorial: return Color(red: 0.604, green: 0.204, blue: 0.071)
        case .nordicFrost: return Color(red: 0.145, green: 0.388, blue: 0.922)
        case .botanicalSage: return Color(red: 0.082, green: 0.502, blue: 0.239)
        case .carbonSlate: return Color(red: 0.435, green: 0.463, blue: 0.965)
        case .midnightNord: return Color(red: 0.220, green: 0.741, blue: 0.973)
        }
    }

    public var accentForeground: Color {
        if hasCustomAccent, let c = activeOverride {
            let lum = 0.2126 * c.accentRed + 0.7152 * c.accentGreen + 0.0722 * c.accentBlue
            return lum > 0.55 ? Color(red: 0.05, green: 0.06, blue: 0.08) : Color.white
        }
        switch theme {
        case .midnightNord: return Color(red: 0.020, green: 0.024, blue: 0.031)
        default: return Color.white
        }
    }

    public var statusOnline: Color {
        isEffectivelyDark
            ? Color(red: 0.28, green: 0.82, blue: 0.50)
            : Color(red: 0.12, green: 0.55, blue: 0.29)
    }

    public static let sidebarDefaultWidth: CGFloat = 252.0
    public static let sidebarMinWidth: CGFloat = 216.0
    public static let sidebarMaxWidth: CGFloat = 340.0
}

// MARK: - Font Engine (Plus Jakarta Sans, Inter, Open Sans, Geist — Zero Ugly Telemetry Font)
public enum AppFontFamily: String, CaseIterable, Codable, Identifiable {
    case plusJakartaSans = "Plus Jakarta Sans"
    case inter = "Inter"
    case openSans = "Open Sans"
    case geist = "Geist"

    public var id: String { rawValue }
}

public enum CustomFontRegistrar {
    public nonisolated(unsafe) static var resolvedJakartaName: String = "Plus Jakarta Sans"
    public nonisolated(unsafe) static var resolvedInterName: String = "Inter"
    public nonisolated(unsafe) static var resolvedOpenSansName: String = "Open Sans"
    public nonisolated(unsafe) static var resolvedGeistName: String = "Geist"

    public static func registerBundledFonts() {
        guard let resourceURL = Bundle.main.resourceURL else { return }
        let fontDirs = [
            resourceURL.appendingPathComponent("Fonts"),
            resourceURL.appendingPathComponent("Motif_Motif.bundle/Contents/Resources/Fonts"),
            resourceURL
        ]
        for dir in fontDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files where file.pathExtension.lowercased() == "ttf" || file.pathExtension.lowercased() == "otf" {
                CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
                if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor],
                   let first = descriptors.first,
                   let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String {
                    let lower = file.lastPathComponent.lowercased()
                    if lower.contains("jakarta") {
                        resolvedJakartaName = familyName
                    } else if lower.contains("inter") {
                        resolvedInterName = familyName
                    } else if lower.contains("opensans") {
                        resolvedOpenSansName = familyName
                    } else if lower.contains("geist") {
                        resolvedGeistName = familyName
                    }
                }
            }
        }
    }
}

// MARK: - Dual-Profile Windowed vs. Fullscreen Optical Typography & Spatial Utilization Engine
public struct TypographyConfiguration: Codable, Equatable {
    public var fontFamily: AppFontFamily = .plusJakartaSans
    public var windowedBaseFontSize: Double = 13.5
    public var fullscreenBaseFontSize: Double = 16.0
    public var lineSpacingMultiplier: Double = 1.52
    public var comfortableReadingWidth: Double = 780.0

    public var resolvedFamilyName: String {
        switch fontFamily {
        case .plusJakartaSans: return CustomFontRegistrar.resolvedJakartaName
        case .inter: return CustomFontRegistrar.resolvedInterName
        case .openSans: return CustomFontRegistrar.resolvedOpenSansName
        case .geist: return CustomFontRegistrar.resolvedGeistName
        }
    }

    public func effectiveFontSize(forCanvasWidth width: CGFloat, isFullscreen: Bool) -> CGFloat {
        if isFullscreen {
            return CGFloat(fullscreenBaseFontSize)
        }
        let progress = min(1.0, max(0.0, (Double(width) - 880.0) / (1520.0 - 880.0)))
        let interpolated = windowedBaseFontSize + progress * (fullscreenBaseFontSize - windowedBaseFontSize)
        return CGFloat(interpolated)
    }

    public func effectiveReadingWidth(forCanvasWidth width: CGFloat, isFullscreen: Bool) -> CGFloat {
        let activeSize = effectiveFontSize(forCanvasWidth: width, isFullscreen: isFullscreen)
        let scaleRatio = activeSize / max(10.0, CGFloat(windowedBaseFontSize))
        let scaledMeasure = max(CGFloat(comfortableReadingWidth) * scaleRatio, width * 0.78)
        if width < 1120 {
            return max(520.0, width - 38.0)
        }
        return min(width - 56.0, max(720.0, min(1160.0, scaledMeasure)))
    }

    public func sans(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let candidate = resolvedFamilyName
        if NSFont(name: candidate, size: size) != nil {
            return .custom(candidate, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    public func nsFont(size: CGFloat) -> NSFont {
        let candidate = resolvedFamilyName
        return NSFont(name: candidate, size: size) ?? NSFont.systemFont(ofSize: size, weight: .regular)
    }

    public func mono(size: CGFloat = 11.0, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }

    /// Uses the clean main UI sans font with tabular figures (never uses JetBrains Mono / Menlo for UI numbers)
    public func telemetry(size: CGFloat = 11.0, weight: Font.Weight = .medium) -> Font {
        sans(size: size, weight: weight).monospacedDigit()
    }

    public func wordmark(size: CGFloat = 18.0) -> Font {
        sans(size: size, weight: .bold)
    }
}

// MARK: - Inline Slash Command System Personas
public struct SlashPersona: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var trigger: String
    public var title: String
    public var systemPrompt: String

    public static let defaults: [SlashPersona] = [
        SlashPersona(
            trigger: "/architect",
            title: "Systems Architect",
            systemPrompt: "You are a principal systems architect. Reason from first principles, focus on memory layout, concurrency safety, and clean modular boundaries."
        ),
        SlashPersona(
            trigger: "/coder",
            title: "Production Engineer",
            systemPrompt: "You are a senior software engineer. Output complete, production-ready, warning-free code with zero placeholders or omissions."
        ),
        SlashPersona(
            trigger: "/editor",
            title: "Editorial Writer",
            systemPrompt: "You are an executive editor. Write with crisp clarity, strong rhythm, and zero filler."
        ),
        SlashPersona(
            trigger: "/concise",
            title: "Direct & Concise",
            systemPrompt: "Answer as directly and concisely as possible. Lead immediately with the solution."
        )
    ]
}

// MARK: - Introspected Model Thinking Capability Profile (`POST /api/show`)
public enum ModelThinkingSupportKind: String, Codable, Equatable {
    case unsupported = "Standard (No Think)"
    case toggleable = "Binary Think (Off / On)"
    case alwaysOnReasoning = "Native <think> Tag"
    case effortTiered = "Multi-Level (Off / Low / Med / High)"
}

public struct ModelThinkingProfile: Codable, Equatable {
    public var kind: ModelThinkingSupportKind = .unsupported
    public var supportsSlashDirectives: Bool = false
    public var supportsNativeThinkFlag: Bool = false
    public var supportsEffortLevels: Bool = false
    public var detectedMechanismSummary: String = "Standard completion template (no thinking tags detected)"
    public var detectedTemplateTokens: String = "None"

    public var validOptions: [ThinkingModeOption] {
        switch kind {
        case .unsupported:
            return [.forceNoThink]
        case .toggleable, .alwaysOnReasoning:
            return [.forceNoThink, .forceThink]
        case .effortTiered:
            return [.forceNoThink, .effortLow, .effortMedium, .effortHigh]
        }
    }
}

public enum ThinkingModeOption: String, CaseIterable, Codable, Identifiable {
    case forceNoThink = "Off"
    case forceThink = "On"
    case effortLow = "Low"
    case effortMedium = "Med"
    case effortHigh = "High"

    public var id: String { rawValue }

    public var isThinkingEnabled: Bool {
        self != .forceNoThink
    }

    public var effortDirective: String? {
        switch self {
        case .forceNoThink, .forceThink: return nil
        case .effortLow: return "low"
        case .effortMedium: return "medium"
        case .effortHigh: return "high"
        }
    }
}

public enum MirostatMode: Int, CaseIterable, Codable, Identifiable {
    case disabled = 0
    case mirostat1 = 1
    case mirostat2 = 2

    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .disabled: return "Off (0)"
        case .mirostat1: return "Mirostat v1"
        case .mirostat2: return "Mirostat v2"
        }
    }
}

public enum KVCacheQuantization: String, CaseIterable, Codable, Identifiable {
    case f16 = "f16"
    case q8_0 = "q8_0"
    case q4_0 = "q4_0"

    public var id: String { rawValue }
    public var displayTitle: String {
        switch self {
        case .f16: return "FP16 (Uncompressed)"
        case .q8_0: return "Q8_0 (8-bit · Saves ~45% KV RAM)"
        case .q4_0: return "Q4_0 (4-bit · Saves ~70% KV RAM)"
        }
    }
    public var bytesPerElement: Double {
        switch self {
        case .f16: return 2.0
        case .q8_0: return 1.05
        case .q4_0: return 0.55
        }
    }
}

public struct ModelRuntimeParameters: Codable, Equatable {
    public var thinkingMode: ThinkingModeOption = .forceThink
    public var forceThinkingOverrideWhenUnsupported: Bool = false
    public var tightRAMModeEnabled: Bool = false
    public var numCtx: Int = 8192
    public var kvCacheQuant: KVCacheQuantization = .f16
    public var temperature: Double = 0.70
    public var topP: Double = 0.90
    public var topK: Int = 40
    public var minP: Double = 0.05
    public var repeatPenalty: Double = 1.10

    // Advanced CLI Options (numThread = 0 means Auto Apple Silicon Performance Cores; numGpu = -1 means Auto Metal VRAM Fit)
    public var typicalP: Double = 1.00
    public var repeatLastN: Int = 64
    public var presencePenalty: Double = 0.00
    public var frequencyPenalty: Double = 0.00
    public var mirostat: MirostatMode = .disabled
    public var mirostatTau: Double = 5.00
    public var mirostatEta: Double = 0.10
    public var numPredict: Int = 16384
    public var numKeep: Int = 256
    public var numBatch: Int = 512
    public var numThread: Int = 0
    public var numGpu: Int = -1
    public var seed: Int = -1
    public var keepAliveMinutes: Int = 15
    public var stopSequencesCSV: String = ""
    public var penalizeNewline: Bool = true
    public var useMmap: Bool = true
    public var useMlock: Bool = false
    public var enforceJSONMode: Bool = false

    public static let precise = ModelRuntimeParameters(
        thinkingMode: .forceThink, numCtx: 16384, kvCacheQuant: .f16,
        temperature: 0.15, topP: 0.85, topK: 20, minP: 0.08, repeatPenalty: 1.05
    )
    public static let balanced = ModelRuntimeParameters(
        thinkingMode: .forceThink, numCtx: 8192, kvCacheQuant: .f16,
        temperature: 0.70, topP: 0.90, topK: 40, minP: 0.05, repeatPenalty: 1.10
    )
    public static let tightRAM = ModelRuntimeParameters(
        thinkingMode: .forceNoThink, tightRAMModeEnabled: true, numCtx: 4096, kvCacheQuant: .q4_0,
        temperature: 0.70, topP: 0.90, topK: 40, minP: 0.05, repeatPenalty: 1.10,
        numPredict: 8192, numKeep: 128, numBatch: 128, numThread: 0, numGpu: -1, keepAliveMinutes: 5, useMmap: true, useMlock: false
    )
}

public struct ParameterPreset: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var summary: String
    public var parameters: ModelRuntimeParameters
    public var systemPrompt: String

    public static let defaults: [ParameterPreset] = [
        ParameterPreset(
            name: "Tight RAM",
            summary: "Low-memory survival mode (Q4_0 KV · 4k ctx · 128 batch · mmap)",
            parameters: .tightRAM,
            systemPrompt: "You are a concise, accurate assistant."
        ),
        ParameterPreset(
            name: "Balanced",
            summary: "Standard analytical & editorial balance (Temp 0.70 · 8k ctx)",
            parameters: .balanced,
            systemPrompt: "You are a clear, accurate, and thoughtful assistant."
        ),
        ParameterPreset(
            name: "Precise",
            summary: "Deterministic coding & architecture (Temp 0.15 · 16k ctx)",
            parameters: .precise,
            systemPrompt: "You are a principal software engineer. Provide concise, production-grade code and direct technical explanations."
        )
    ]
}

// MARK: - Model Descriptor with Live `/api/show` Introspected Metadata & Automatic `:latest` Stripping
public enum ModelResidencyState: String, Codable {
    case dormantOnDisk = "On disk"
    case loadingIntoMemory = "Loading"
    case activeInUnifiedRAM = "In RAM"
}

public struct LocalModelDescriptor: Identifiable, Codable, Equatable {
    public var id: String { name }
    public var name: String
    public var displayName: String
    public var family: String
    public var parameterSize: String
    public var quantizationLevel: String
    public var sizeBytes: Int64
    public var digest: String
    public var modifiedAt: Date
    public var residency: ModelResidencyState = .dormantOnDisk
    public var vramAllocatedBytes: Int64 = 0
    public var numLayers: Int = 32
    public var numKVHeads: Int = 8
    public var headDim: Int = 128
    public var maxContextLength: Int = 32768
    public var thinkingProfile: ModelThinkingProfile = ModelThinkingProfile()
    public var hasIntrospectedShowMetadata: Bool = false

    public var sizeGB: Double {
        max(0.1, Double(sizeBytes) / 1_073_741_824.0)
    }

    public var formattedSize: String {
        String(format: "%.1f GB", sizeGB)
    }

    public var shortDisplayName: String {
        Self.shortenModelName(displayName)
    }

    /// Strips registry paths AND redundant `:latest` tags so models display cleanly
    public static func shortenModelName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let lastSlash = s.lastIndex(of: "/") {
            s = String(s[s.index(after: lastSlash)...])
        }
        if s.lowercased().hasSuffix(":latest") {
            s = String(s.dropLast(":latest".count))
        }
        return s
    }
}

// MARK: - Attachments & Message Tree Ledger
public enum AttachmentKind: String, Codable {
    case pastedDocumentChip = "Pasted text"
    case sourceCodeFile = "File"
    case downscaledVisionImage = "Image"
}

public struct MessageAttachment: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var title: String
    public var kind: AttachmentKind
    public var byteCount: Int
    public var lineCount: Int
    public var previewText: String
    public var localAssetFilename: String?
    public var base64ImagePayload: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, byteCount, lineCount, previewText, localAssetFilename
    }

    public var tokenEstimate: Int {
        if kind == .downscaledVisionImage { return 768 }
        return max(1, byteCount / 4)
    }
    public var formattedByteSize: String {
        if byteCount >= 1_048_576 {
            return String(format: "%.1f MB", Double(byteCount) / 1_048_576.0)
        } else if byteCount >= 1024 {
            return String(format: "%.1f KB", Double(byteCount) / 1024.0)
        }
        return "\(byteCount) B"
    }
}

public enum MessageRole: String, Codable {
    case system
    case user
    case assistant
}

public struct GenerationMetrics: Codable, Equatable {
    public var tokensPerSecond: Double = 0.0
    public var totalGenerationDurationSec: Double = 0.0
    public var thinkingDurationSec: Double = 0.0
    public var totalTokens: Int = 0
    public var promptEvalTokens: Int = 0
}

public struct ConversationMessageNode: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var parentID: UUID?
    public var childrenIDs: [UUID] = []
    public var activeChildIndex: Int = 0
    public var role: MessageRole
    public var content: String
    public var apiPromptOverride: String? = nil
    public var isSummaryHandoffRequest: Bool = false
    public var thinkingTrace: String = ""
    public var isThinkingComplete: Bool = true
    public var isThinkingExpanded: Bool = false
    public var createdAt: Date = Date()
    public var modelUsed: String = ""
    public var attachments: [MessageAttachment] = []
    public var metrics: GenerationMetrics? = nil
    public var wasStoppedMidStream: Bool = false
    public var wasStoppedMidThinking: Bool = false
    public var errorNote: String? = nil

    public var estimatedTokenFootprint: Int {
        let textTok = max(1, (content.count + thinkingTrace.count) / 4)
        let attTok = attachments.reduce(0) { $0 + $1.tokenEstimate }
        return textTok + attTok
    }
}

public struct WorkspaceArtifact: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var title: String
    public var language: String
    public var content: String
    public var createdAt: Date = Date()
    public var sourceMessageID: UUID?
}

public struct ConversationSession: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var title: String
    public var folderID: UUID? = nil
    public var isPinned: Bool = false
    public var isTrashed: Bool = false
    public var trashedAt: Date? = nil
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var selectedModelName: String = ""
    public var activePersonaTrigger: String? = nil
    public var systemPrompt: String = "You are a clear, accurate assistant."
    public var parameters: ModelRuntimeParameters = .balanced

    public var draftText: String = ""
    public var draftAttachments: [MessageAttachment] = []

    public var nodes: [UUID: ConversationMessageNode] = [:]
    public var rootMessageIDs: [UUID] = []
    public var activeRootIndex: Int = 0
    public var artifacts: [WorkspaceArtifact] = []

    public var activeBranchThread: [ConversationMessageNode] {
        guard !rootMessageIDs.isEmpty else { return [] }
        let clampedRoot = min(max(0, activeRootIndex), rootMessageIDs.count - 1)
        var currentID: UUID? = rootMessageIDs[clampedRoot]
        var thread: [ConversationMessageNode] = []
        var visited = Set<UUID>()

        while let id = currentID, !visited.contains(id), let node = nodes[id] {
            visited.insert(id)
            thread.append(node)
            if node.childrenIDs.isEmpty {
                currentID = nil
            } else {
                let idx = min(max(0, node.activeChildIndex), node.childrenIDs.count - 1)
                currentID = node.childrenIDs[idx]
            }
        }
        return thread
    }

    public var estimatedActiveTokens: Int {
        let thread = activeBranchThread
        let sysTokens = max(1, systemPrompt.count / 4)
        let msgTokens = thread.reduce(0) { $0 + $1.estimatedTokenFootprint }
        let draftTok = (draftText.count / 4) + draftAttachments.reduce(0) { $0 + $1.tokenEstimate }
        let heuristicTotal = sysTokens + msgTokens + draftTok
        if let lastAssistant = thread.last(where: { $0.role == .assistant }),
           let reportedPrompt = lastAssistant.metrics?.promptEvalTokens,
           reportedPrompt > 0 {
            return max(heuristicTotal, reportedPrompt + lastAssistant.estimatedTokenFootprint + draftTok)
        }
        return heuristicTotal
    }

    public func siblingInfo(for nodeID: UUID) -> (currentIndex: Int, totalCount: Int) {
        guard let node = nodes[nodeID] else { return (0, 1) }
        if let parentID = node.parentID, let parent = nodes[parentID] {
            let idx = parent.childrenIDs.firstIndex(of: nodeID) ?? 0
            return (idx, max(1, parent.childrenIDs.count))
        } else {
            let idx = rootMessageIDs.firstIndex(of: nodeID) ?? 0
            return (idx, max(1, rootMessageIDs.count))
        }
    }

    public static func sanitizeTitle(_ raw: String) -> String {
        let firstLine = raw.components(separatedBy: .newlines).first ?? raw
        let stripped = firstLine
            .replacingOccurrences(of: "/think", with: "")
            .replacingOccurrences(of: "/no_think", with: "")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
        let collapsed = stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let punctuation = CharacterSet(charactersIn: ".,;:!?-–—'\"/\\| ")
        let trimmed = collapsed.trimmingCharacters(in: punctuation)
        guard !trimmed.isEmpty else { return "New Chat" }
        if trimmed.count > 46 {
            return String(trimmed.prefix(45)).trimmingCharacters(in: punctuation) + "…"
        }
        return trimmed
    }
}

public struct ProjectFolder: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var isExpanded: Bool = true
}

public struct RegistryDownloadTask: Identifiable, Codable, Equatable {
    public var id: UUID = UUID()
    public var modelReference: String
    public var statusText: String
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var isCompleted: Bool

    public var progressFraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, Double(completedBytes) / Double(totalBytes))
    }

    public var formattedProgressGB: String {
        guard totalBytes > 1024 else { return statusText }
        let doneGB = Double(completedBytes) / 1_073_741_824.0
        let totGB = Double(totalBytes) / 1_073_741_824.0
        let pct = Int(progressFraction * 100.0)
        return String(format: "%.2f / %.2f GB (%d%%)", doneGB, totGB, pct)
    }
}

public struct FTSSearchHit: Identifiable, Equatable {
    public let id = UUID()
    public let sessionID: UUID
    public let messageID: UUID
    public let sessionTitle: String
    public let snippetText: String
}

public struct ShortcutConfiguration: Codable, Equatable {
    public var newChatKey: String = "n"
    public var toggleSidebarKey: String = "s"
    public var toggleInspectorKey: String = "\\"
    public var stopGenerationKey: String = "."
}
EOF
