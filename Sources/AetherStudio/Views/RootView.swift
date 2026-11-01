import SwiftUI

public struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var theme: ThemeCoordinator
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        let palette = theme.palette(for: colorScheme)

        NavigationSplitView {
            ConversationSidebarView(palette: palette)
                .frame(minWidth: 220, idealWidth: AetherMetrics.sidebarWidth, maxWidth: 300)
        } detail: {
            ChatContainerView(palette: palette)
        }
        .sheet(isPresented: $coordinator.isSettingsOpen) {
            SettingsContainerView(palette: palette)
                .environmentObject(coordinator)
                .environmentObject(theme)
        }
        .sheet(isPresented: $coordinator.isDialsOpen) {
            SamplingDialsInspector(palette: palette)
                .environmentObject(coordinator)
                .environmentObject(theme)
        }
        .background(palette.windowCanvas)
    }
}

public struct SettingsContainerView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var theme: ThemeCoordinator
    public let palette: AetherPalette
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: 0) {
            // Header with tabs
            HStack {
                Picker("Settings Section", selection: $coordinator.selectedSettingsTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .controlSize(.small)
            }
            .padding(16)
            .background(palette.windowCanvas)

            Divider().overlay(palette.hairlineBorder)

            Group {
                switch coordinator.selectedSettingsTab {
                case .externalDrive:
                    ExternalDriveSettingsView(palette: palette)
                case .engine:
                    EngineSettingsView(palette: palette)
                case .appearance:
                    AppearanceSettingsView(palette: palette)
                }
            }
        }
        .frame(width: 640, height: 580)
        .background(palette.windowCanvas)
    }
}

public struct AppearanceSettingsView: View {
    @EnvironmentObject private var theme: ThemeCoordinator
    public let palette: AetherPalette

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Theme & Aesthetic")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Text("Restrained, disciplined palettes inspired by Apple Pro apps and Things 3.")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }

                VStack(spacing: 10) {
                    ForEach(AetherThemeID.allCases) { th in
                        let isSelected = theme.selectedTheme == th
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(th.displayName)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                    .foregroundStyle(palette.primaryText)
                                Text(th.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(palette.secondaryText)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? palette.accentSoft : palette.subtleSurface))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? palette.accent.opacity(0.4) : palette.hairlineBorder, lineWidth: 1))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            theme.selectedTheme = th
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}
