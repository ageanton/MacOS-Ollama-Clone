import SwiftUI
import AppKit

// MARK: - Studio Theme Palettes

public enum StudioThemeID: String, CaseIterable, Codable, Identifiable {
    case sageAndPaper = "sage_and_paper"
    case warmStone = "warm_stone"
    case nordicSlate = "nordic_slate"
    case macOSSequoia = "macos_sequoia"
    case editorialAmber = "editorial_amber"
    case britishRacingGreen = "british_racing_green"
    case carbonAndMoss = "carbon_and_moss"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sageAndPaper: return "Sage & Paper (Default)"
        case .warmStone: return "Warm Stone"
        case .nordicSlate: return "Nordic Slate"
        case .macOSSequoia: return "macOS Sequoia"
        case .editorialAmber: return "Editorial Paper & Amber"
        case .britishRacingGreen: return "British Racing Green"
        case .carbonAndMoss: return "Carbon & Moss"
        }
    }

    public var subtitle: String {
        switch self {
        case .sageAndPaper:
            return "Soft botanical sage canvas with a crisp white inset card and deep forest accent."
        case .warmStone:
            return "Travertine linen frame with warm alabaster paper and espresso-terracotta cues."
        case .nordicSlate:
            return "Cool mist-blue architectural frame with pure paper and deep fjord blue highlights."
        case .macOSSequoia:
            return "Native Apple Pro neutral alabaster canvas paired with classic system blue."
        case .editorialAmber:
            return "Warm print parchment surface with high-contrast ink and burnt amber accents."
        case .britishRacingGreen:
            return "Deep hunter green studio tint with warm ivory cards and heritage brass status cues."
        case .carbonAndMoss:
            return "Restrained low-glare obsidian dark workspace with muted sage-emerald accents."
        }
    }
}

public enum AppearancePreference: String, CaseIterable, Codable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "Match System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum StudioFontFamily: String, CaseIterable, Codable, Identifiable {
    case sfPro = "sf_pro"
    case inter = "inter"
    case plusJakartaSans = "plus_jakarta"
    case openSans = "open_sans"
    case dmSans = "dm_sans"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sfPro: return "San Francisco (macOS Native)"
        case .inter: return "Inter"
        case .plusJakartaSans: return "Plus Jakarta Sans"
        case .openSans: return "Open Sans"
        case .dmSans: return "DM Sans"
        }
    }

    public var descriptorNote: String {
        switch self {
        case .sfPro: return "Apple's optical system typeface calibrated for Retina displays."
        case .inter: return "High-legibility neo-grotesque designed for dense technical interfaces."
        case .plusJakartaSans: return "Contemporary geometric sans with warm, approachable proportions."
        case .openSans: return "Humanist sans-serif with wide apertures for effortless long-form reading."
        case .dmSans: return "Low-contrast geometric typeface with crisp tabular rhythm."
        }
    }

    public var postScriptCandidates: [String] {
        switch self {
        case .sfPro: return []
        case .inter: return ["Inter-Regular", "Inter"]
        case .plusJakartaSans: return ["PlusJakartaSans-Regular", "Plus Jakarta Sans"]
        case .openSans: return ["OpenSans-Regular", "Open Sans"]
        case .dmSans: return ["DMSans-Regular", "DM Sans"]
        }
    }
}

// MARK: - Color Tokens

public struct StudioPalette {
    public let windowCanvas: Color        // Outer window & sidebar background
    public let cardSurface: Color         // Inset main content card background
    public let elevatedSurface: Color     // Popovers, sheets, and floating capsules
    public let subtleSurface: Color       // Hover states, quiet pill backgrounds, code blocks
    public let primaryText: Color         // High-contrast ink
    public let secondaryText: Color       // Accessible readable secondary text (WCAG AA+)
    public let mutedText: Color           // Quiet metadata and shortcut hints
    public let accent: Color              // Single restrained accent color
    public let accentSoft: Color          // 12% tint of accent for selected rows/pills
    public let hairlineBorder: Color      // 1px crisp structural divider
    public let cardRing: Color            // Subtle outer ring around the inset card
    public let statusHealthy: Color       // Calm botanical green for healthy RAM / running server
    public let statusWarning: Color       // Warm ochre for elevated memory pressure
    public let statusDanger: Color        // Restrained crimson for destructive actions / overflow
}

extension Color {
    public init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: - Concentric Layout & Radius Tokens

public enum StudioMetrics {
    /// Outer window padding around the main content card
    public static let cardOuterInset: CGFloat = 8.0
    /// Primary inset white card corner radius
    public static let cardCornerRadius: CGFloat = 12.0
    /// Secondary container radius (sheets, grouped panels, code blocks)
    public static let containerCornerRadius: CGFloat = 8.0
    /// Interactive control radius (buttons, inputs, segmented controls, pills)
    public static let controlCornerRadius: CGFloat = 6.0
    /// Small badge radius
    public static let badgeCornerRadius: CGFloat = 4.0
    /// Sidebar fixed width
    public static let sidebarWidth: CGFloat = 248.0
    /// Inspector drawer width
    public static let inspectorWidth: CGFloat = 340.0
    /// Comfortable reading column max width (~65ch)
    public static let readingColumnMaxWidth: CGFloat = 720.0
    /// macOS Traffic Light top clearance
    public static let trafficLightClearanceHeight: CGFloat = 38.0
}

// MARK: - Theme Manager

@MainActor
public final class ThemeManager: ObservableObject {
    @Published public var selectedTheme: StudioThemeID {
        didSet { UserDefaults.standard.set(selectedTheme.rawValue, forKey: "studio.theme") }
    }
    @Published public var appearancePreference: AppearancePreference {
        didSet { UserDefaults.standard.set(appearancePreference.rawValue, forKey: "studio.appearance") }
    }
    @Published public var selectedFont: StudioFontFamily {
        didSet { UserDefaults.standard.set(selectedFont.rawValue, forKey: "studio.font") }
    }
    @Published public var useComfortableTextSize: Bool {
        didSet { UserDefaults.standard.set(useComfortableTextSize, forKey: "studio.comfortableText") }
    }

    public init() {
        let savedTheme = UserDefaults.standard.string(forKey: "studio.theme") ?? StudioThemeID.sageAndPaper.rawValue
        self.selectedTheme = StudioThemeID(rawValue: savedTheme) ?? .sageAndPaper

        let savedAppearance = UserDefaults.standard.string(forKey: "studio.appearance") ?? AppearancePreference.light.rawValue
        self.appearancePreference = AppearancePreference(rawValue: savedAppearance) ?? .light

        let savedFont = UserDefaults.standard.string(forKey: "studio.font") ?? StudioFontFamily.sfPro.rawValue
        self.selectedFont = StudioFontFamily(rawValue: savedFont) ?? .sfPro

        if UserDefaults.standard.object(forKey: "studio.comfortableText") == nil {
            self.useComfortableTextSize = true
        } else {
            self.useComfortableTextSize = UserDefaults.standard.bool(forKey: "studio.comfortableText")
        }
    }

    public func palette(for colorScheme: ColorScheme) -> StudioPalette {
        let isDark: Bool = {
            if selectedTheme == .carbonAndMoss { return true }
            switch appearancePreference {
            case .light: return false
            case .dark: return true
            case .system: return colorScheme == .dark
            }
        }()

        switch (selectedTheme, isDark) {
        // 1. Sage & Paper (The signature default)
        case (.sageAndPaper, false):
            return StudioPalette(
                windowCanvas: Color(hex: 0xEBF0EC),
                cardSurface: Color(hex: 0xFFFFFF),
                elevatedSurface: Color(hex: 0xFAFBF9),
                subtleSurface: Color(hex: 0xF2F5F3),
                primaryText: Color(hex: 0x18221D),
                secondaryText: Color(hex: 0x46544D),
                mutedText: Color(hex: 0x687870),
                accent: Color(hex: 0x2C5E43),
                accentSoft: Color(hex: 0x2C5E43, alpha: 0.11),
                hairlineBorder: Color(hex: 0xDCE3DE),
                cardRing: Color(hex: 0x18221D, alpha: 0.07),
                statusHealthy: Color(hex: 0x2C5E43),
                statusWarning: Color(hex: 0xB4691E),
                statusDanger: Color(hex: 0xB8332A)
            )
        case (.sageAndPaper, true), (.carbonAndMoss, _):
            return StudioPalette(
                windowCanvas: Color(hex: 0x131614),
                cardSurface: Color(hex: 0x1B1F1C),
                elevatedSurface: Color(hex: 0x222724),
                subtleSurface: Color(hex: 0x252B27),
                primaryText: Color(hex: 0xEAEFEA),
                secondaryText: Color(hex: 0xA3B1A8),
                mutedText: Color(hex: 0x76857B),
                accent: Color(hex: 0x529471),
                accentSoft: Color(hex: 0x529471, alpha: 0.18),
                hairlineBorder: Color(hex: 0x2B312D),
                cardRing: Color(hex: 0xFFFFFF, alpha: 0.06),
                statusHealthy: Color(hex: 0x529471),
                statusWarning: Color(hex: 0xD99441),
                statusDanger: Color(hex: 0xE05A50)
            )

        // 2. Warm Stone (Things 3 / Kinfolk travertine)
        case (.warmStone, false):
            return StudioPalette(
                windowCanvas: Color(hex: 0xEFECE6),
                cardSurface: Color(hex: 0xFAF8F5),
                elevatedSurface: Color(hex: 0xFFFFFF),
                subtleSurface: Color(hex: 0xF3EFE8),
                primaryText: Color(hex: 0x211E1A),
                secondaryText: Color(hex: 0x575047),
                mutedText: Color(hex: 0x7A7167),
                accent: Color(hex: 0x7C4D3A),
                accentSoft: Color(hex: 0x7C4D3A, alpha: 0.11),
                hairlineBorder: Color(hex: 0xE2DDD5),
                cardRing: Color(hex: 0x211E1A, alpha: 0.07),
                statusHealthy: Color(hex: 0x3B6E4C),
                statusWarning: Color(hex: 0xB86B23),
                statusDanger: Color(hex: 0xB5382E)
            )
        case (.warmStone, true):
            return StudioPalette(
                windowCanvas: Color(hex: 0x161412),
                cardSurface: Color(hex: 0x1E1B18),
                elevatedSurface: Color(hex: 0x26221F),
                subtleSurface: Color(hex: 0x2A2622),
                primaryText: Color(hex: 0xF0ECE6),
                secondaryText: Color(hex: 0xB0A69B),
                mutedText: Color(hex: 0x82786E),
                accent: Color(hex: 0xC48468),
                accentSoft: Color(hex: 0xC48468, alpha: 0.18),
                hairlineBorder: Color(hex: 0x302B27),
                cardRing: Color(hex: 0xFFFFFF, alpha: 0.06),
                statusHealthy: Color(hex: 0x5A996E),
                statusWarning: Color(hex: 0xD99148),
                statusDanger: Color(hex: 0xE06256)
            )

        // 3. Nordic Slate
        case (.nordicSlate, false):
            return StudioPalette(
                windowCanvas: Color(hex: 0xEAEFF5),
                cardSurface: Color(hex: 0xFFFFFF),
                elevatedSurface: Color(hex: 0xF8FAFC),
                subtleSurface: Color(hex: 0xF1F5F9),
                primaryText: Color(hex: 0x151D28),
                secondaryText: Color(hex: 0x455366),
                mutedText: Color(hex: 0x67768A),
                accent: Color(hex: 0x2B4C7E),
                accentSoft: Color(hex: 0x2B4C7E, alpha: 0.11),
                hairlineBorder: Color(hex: 0xDAE2EC),
                cardRing: Color(hex: 0x151D28, alpha: 0.07),
                statusHealthy: Color(hex: 0x2D6A4F),
                statusWarning: Color(hex: 0xB56A1E),
                statusDanger: Color(hex: 0xB9382E)
            )
        case (.nordicSlate, true):
            return StudioPalette(
                windowCanvas: Color(hex: 0x11151C),
                cardSurface: Color(hex: 0x181D26),
                elevatedSurface: Color(hex: 0x1F2631),
                subtleSurface: Color(hex: 0x232B38),
                primaryText: Color(hex: 0xE9EEF5),
                secondaryText: Color(hex: 0x9FB0C4),
                mutedText: Color(hex: 0x708299),
                accent: Color(hex: 0x6692D6),
                accentSoft: Color(hex: 0x6692D6, alpha: 0.18),
                hairlineBorder: Color(hex: 0x28313E),
                cardRing: Color(hex: 0xFFFFFF, alpha: 0.06),
                statusHealthy: Color(hex: 0x52997A),
                statusWarning: Color(hex: 0xDB9446),
                statusDanger: Color(hex: 0xE05E53)
            )

        // 4. macOS Sequoia
        case (.macOSSequoia, false):
            return StudioPalette(
                windowCanvas: Color(hex: 0xF0F1F4),
                cardSurface: Color(hex: 0xFFFFFF),
                elevatedSurface: Color(hex: 0xFAFAFC),
                subtleSurface: Color(hex: 0xF4F5F7),
                primaryText: Color(hex: 0x1A1B1E),
                secondaryText: Color(hex: 0x4F5259),
                mutedText: Color(hex: 0x727680),
                accent: Color(hex: 0x0066CC),
                accentSoft: Color(hex: 0x0066CC, alpha: 0.10),
                hairlineBorder: Color(hex: 0xE1E3E8),
                cardRing: Color(hex: 0x000000, alpha: 0.07),
                statusHealthy: Color(hex: 0x287D4E),
                statusWarning: Color(hex: 0xB86A1B),
                statusDanger: Color(hex: 0xC4332B)
            )
        case (.macOSSequoia, true):
            return StudioPalette(
                windowCanvas: Color(hex: 0x141518),
                cardSurface: Color(hex: 0x1C1D21),
                elevatedSurface: Color(hex: 0x24262B),
                subtleSurface: Color(hex: 0x27292F),
                primaryText: Color(hex: 0xECEDF0),
                secondaryText: Color(hex: 0xA4A8B3),
                mutedText: Color(hex: 0x767A85),
                accent: Color(hex: 0x4796E6),
                accentSoft: Color(hex: 0x4796E6, alpha: 0.18),
                hairlineBorder: Color(hex: 0x2C2E35),
                cardRing: Color(hex: 0xFFFFFF, alpha: 0.06),
                statusHealthy: Color(hex: 0x4D9E6F),
                statusWarning: Color(hex: 0xD99243),
                statusDanger: Color(hex: 0xE05A52)
            )

        // 5. Editorial Paper & Amber
        case (.editorialAmber, false):
            return StudioPalette(
                windowCanvas: Color(hex: 0xF3EDE2),
                cardSurface: Color(hex: 0xFCF9F4),
                elevatedSurface: Color(hex: 0xFFFFFF),
                subtleSurface: Color(hex: 0xF5F0E6),
                primaryText: Color(hex: 0x1F1A16),
                secondaryText: Color(hex: 0x594E43),
                mutedText: Color(hex: 0x7D7063),
                accent: Color(hex: 0xB85318),
                accentSoft: Color(hex: 0xB85318, alpha: 0.11),
                hairlineBorder: Color(hex: 0xE3DBD0),
                cardRing: Color(hex: 0x1F1A16, alpha: 0.07),
                statusHealthy: Color(hex: 0x356947),
                statusWarning: Color(hex: 0xB85318),
                statusDanger: Color(hex: 0xB5332A)
            )
        case (.editorialAmber, true):
            return StudioPalette(
                windowCanvas: Color(hex: 0x171310),
                cardSurface: Color(hex: 0x201B17),
                elevatedSurface: Color(hex: 0x28221D),
                subtleSurface: Color(hex: 0x2C2520),
                primaryText: Color(hex: 0xF2EAE1),
                secondaryText: Color(hex: 0xB5A698),
                mutedText: Color(hex: 0x85776A),
                accent: Color(hex: 0xDE7D43),
                accentSoft: Color(hex: 0xDE7D43, alpha: 0.18),
                hairlineBorder: Color(hex: 0x332B25),
                cardRing: Color(hex: 0xFFFFFF, alpha: 0.06),
                statusHealthy: Color(hex: 0x57996D),
                statusWarning: Color(hex: 0xDE7D43),
                statusDanger: Color(hex: 0xE05E53)
            )

        // 6. British Racing Green
        case (.britishRacingGreen, false):
            return StudioPalette(
                windowCanvas: Color(hex: 0xE4ECE7),
                cardSurface: Color(hex: 0xFDFCFA),
                elevatedSurface: Color(hex: 0xFFFFFF),
                subtleSurface: Color(hex: 0xEFF4F1),
                primaryText: Color(hex: 0x121F18),
                secondaryText: Color(hex: 0x3F5247),
                mutedText: Color(hex: 0x63786B),
                accent: Color(hex: 0x154D34),
                accentSoft: Color(hex: 0x154D34, alpha: 0.11),
                hairlineBorder: Color(hex: 0xD6E0DA),
                cardRing: Color(hex: 0x121F18, alpha: 0.07),
                statusHealthy: Color(hex: 0x154D34),
                statusWarning: Color(hex: 0xA8681D),
                statusDanger: Color(hex: 0xB33329)
            )
        case (.britishRacingGreen, true):
            return StudioPalette(
                windowCanvas: Color(hex: 0x0E1612),
                cardSurface: Color(hex: 0x15201A),
                elevatedSurface: Color(hex: 0x1C2922),
                subtleSurface: Color(hex: 0x202F27),
                primaryText: Color(hex: 0xE8F0EC),
                secondaryText: Color(hex: 0x9EB3A7),
                mutedText: Color(hex: 0x6F8579),
                accent: Color(hex: 0x4C9A74),
                accentSoft: Color(hex: 0x4C9A74, alpha: 0.18),
                hairlineBorder: Color(hex: 0x24332B),
                cardRing: Color(hex: 0xFFFFFF, alpha: 0.06),
                statusHealthy: Color(hex: 0x4C9A74),
                statusWarning: Color(hex: 0xD69445),
                statusDanger: Color(hex: 0xE05B50)
            )
        }
    }

    // MARK: - Native Mac Typography Scale (4 Strict Sizes + Weight Hierarchy)

    /// 1. Small Quiet Secondary Text (11.5pt)
    public func captionFont(weight: Font.Weight = .regular) -> Font {
        resolvedFont(size: 11.5, weight: weight)
    }

    /// 2. Standard UI Body Text (13pt - macOS native control size)
    public func bodyFont(weight: Font.Weight = .regular) -> Font {
        resolvedFont(size: 13.0, weight: weight)
    }

    /// 3. Editorial Conversation Text (14.5pt or 15.5pt comfortable)
    public func conversationFont(weight: Font.Weight = .regular) -> Font {
        let base: CGFloat = useComfortableTextSize ? 15.0 : 14.0
        return resolvedFont(size: base, weight: weight)
    }

    /// 4. Section / Card Title Text (16.5pt)
    public func titleFont(weight: Font.Weight = .semibold) -> Font {
        resolvedFont(size: 16.5, weight: weight)
    }

    /// Monospaced Tabular Font for live counters, RAM readouts, and code blocks
    public func monoFont(size: CGFloat = 12.0, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }

    private func resolvedFont(size: CGFloat, weight: Font.Weight) -> Font {
        if selectedFont == .sfPro {
            return .system(size: size, weight: weight, design: .default).monospacedDigit()
        }
        for candidate in selectedFont.postScriptCandidates {
            if NSFont(name: candidate, size: size) != nil {
                return .custom(candidate, size: size).weight(weight).monospacedDigit()
            }
        }
        return .system(size: size, weight: weight, design: .default).monospacedDigit()
    }
}

// MARK: - Unified 1.5px Stroke Icon System (Zero Emojis)

public enum StudioIconName: String, CaseIterable {
    case chat = "bubble.left"
    case models = "cpu"
    case builder = "slider.horizontal.below.rectangle"
    case server = "server.rack"
    case dials = "slider.horizontal.3"
    case settings = "gearshape"
    case plus = "plus"
    case search = "magnifyingglass"
    case trash = "trash"
    case restore = "arrow.uturn.backward"
    case send = "arrow.up"
    case stop = "stop.fill"
    case paperclip = "paperclip"
    case photo = "photo"
    case doc = "doc.text"
    case copy = "doc.on.doc"
    case check = "checkmark"
    case chevronRight = "chevron.right"
    case chevronDown = "chevron.down"
    case info = "info.circle"
    case warning = "exclamationmark.triangle"
    case spark = "sparkles"
    case eject = "eject"
    case bolt = "bolt"
    case download = "arrow.down.circle"
    case pause = "pause.circle"
    case play = "play.circle"
    case refresh = "arrow.clockwise"
    case folder = "folder"
    case lock = "lock.shield"
    case terminal = "terminal"
    case edit = "pencil"
    case sliders = "dial.medium"
    case eye = "eye"
    case code = "chevron.left.forwardslash.chevron.right"
    case close = "xmark"
    case command = "command"
    case link = "link"
    case archive = "archivebox"
}

public struct StudioIcon: View {
    public let name: StudioIconName
    public var size: CGFloat = 14.0
    public var color: Color? = nil

    public init(_ name: StudioIconName, size: CGFloat = 14.0, color: Color? = nil) {
        self.name = name
        self.size = size
        self.color = color
    }

    public var body: some View {
        Image(systemName: name.rawValue)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color ?? .primary)
            .frame(width: size + 4, height: size + 4, alignment: .center)
    }
}

// MARK: - Reusable Calm UI Controls

public struct StudioPillBadge: View {
    public let text: String
    public let palette: StudioPalette
    public var isAccent: Bool = false
    public var statusColor: Color? = nil

    public init(_ text: String, palette: StudioPalette, isAccent: Bool = false, statusColor: Color? = nil) {
        self.text = text
        self.palette = palette
        self.isAccent = isAccent
        self.statusColor = statusColor
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let dot = statusColor {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(isAccent ? palette.accent : palette.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: StudioMetrics.badgeCornerRadius, style: .continuous)
                .fill(isAccent ? palette.accentSoft : palette.subtleSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.badgeCornerRadius, style: .continuous)
                .strokeBorder(isAccent ? palette.accent.opacity(0.25) : palette.hairlineBorder, lineWidth: 1)
        )
    }
}

public struct PlainEnglishTooltipButton: View {
    public let title: String
    public let technicalKey: String
    public let explanation: String
    public let recommendation: String?
    public let palette: StudioPalette
    @State private var isPresented: Bool = false

    public init(
        title: String,
        technicalKey: String,
        explanation: String,
        recommendation: String? = nil,
        palette: StudioPalette
    ) {
        self.title = title
        self.technicalKey = technicalKey
        self.explanation = explanation
        self.recommendation = recommendation
        self.palette = palette
    }

    public var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            StudioIcon(.info, size: 12, color: palette.mutedText)
        }
        .buttonStyle(.plain)
        .help(explanation)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Spacer()
                    Text(technicalKey)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.mutedText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(palette.subtleSurface)
                        )
                }

                Text(explanation)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)

                if let rec = recommendation, !rec.isEmpty {
                    Divider()
                    HStack(alignment: .top, spacing: 6) {
                        StudioIcon(.check, size: 11, color: palette.accent)
                        Text(rec)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(palette.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .frame(width: 310)
            .background(palette.elevatedSurface)
        }
    }
}
