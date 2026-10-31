import SwiftUI

public struct MainView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    @Environment(\.colorScheme) private var systemColorScheme

    public init() {}

    public var body: some View {
        let palette = theme.palette(for: systemColorScheme)

        ZStack(alignment: .bottom) {
            // Outer Sage / Studio Window Frame
            palette.windowCanvas
                .ignoresSafeArea()

            HStack(spacing: 0) {
                // 1. Calm Left Sidebar Sitting Directly on the Window Canvas
                SidebarView(palette: palette)
                    .frame(width: StudioMetrics.sidebarWidth)

                // 2. Inset Rounded White Card for Main Content
                ZStack {
                    RoundedRectangle(cornerRadius: StudioMetrics.cardCornerRadius, style: .continuous)
                        .fill(palette.cardSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.cardCornerRadius, style: .continuous)
                                .strokeBorder(palette.cardRing, lineWidth: 1)
                        )

                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            if let errorBanner = appState.activeErrorBanner {
                                CalmErrorRecoveryBar(error: errorBanner, palette: palette)
                            }

                            Group {
                                switch appState.selectedTab {
                                case .chat:
                                    ChatView(palette: palette)
                                case .modelsAndRAM:
                                    ModelsManagerView(palette: palette)
                                case .modelBuilder:
                                    ModelBuilderView(palette: palette)
                                case .serverControl:
                                    ServerControlView(palette: palette)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }

                        if appState.isInspectorDrawerOpen {
                            Divider()
                                .overlay(palette.hairlineBorder)
                            InspectorDrawerView(palette: palette)
                                .frame(width: StudioMetrics.inspectorWidth)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: StudioMetrics.cardCornerRadius, style: .continuous))
                }
                .padding(.top, StudioMetrics.cardOuterInset)
                .padding(.bottom, StudioMetrics.cardOuterInset)
                .padding(.trailing, StudioMetrics.cardOuterInset)
            }

            // Non-Destructive Undo Toast
            if let toast = appState.activeUndoToast {
                HStack(spacing: 12) {
                    Text(toast.message)
                        .font(theme.bodyFont(weight: .medium))
                        .foregroundStyle(palette.primaryText)
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appState.restoreFromTrash(toast.trashedItemID)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            StudioIcon(.restore, size: 12, color: palette.accent)
                            Text("Undo")
                                .font(theme.bodyFont(weight: .semibold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius, style: .continuous)
                        .fill(palette.elevatedSurface)
                        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius, style: .continuous)
                        .strokeBorder(palette.hairlineBorder, lineWidth: 1)
                )
                .padding(.bottom, 22)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(resolvedColorScheme)
        .sheet(isPresented: $appState.isSettingsSheetOpen) {
            SettingsView(palette: palette)
                .environmentObject(appState)
                .environmentObject(theme)
        }
        .sheet(isPresented: $appState.isQuickActionSheetOpen) {
            QuickSessionActionsSheet(palette: palette)
                .environmentObject(appState)
                .environmentObject(theme)
        }
        .sheet(isPresented: $appState.isTrashSheetOpen) {
            TrashRecoverySheet(palette: palette)
                .environmentObject(appState)
                .environmentObject(theme)
        }
    }

    private var resolvedColorScheme: ColorScheme? {
        if theme.selectedTheme == .carbonAndMoss { return .dark }
        switch theme.appearancePreference {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Calm Plain-English Error Banner with 1-Click Fix

public struct CalmErrorRecoveryBar: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    public let error: HumanFriendlyError
    public let palette: StudioPalette

    public var body: some View {
        HStack(spacing: 12) {
            StudioIcon(.warning, size: 15, color: palette.statusWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text(error.title)
                    .font(theme.bodyFont(weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Text(error.plainExplanation)
                    .font(theme.captionFont())
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer()
            if let actionTitle = error.recoveryActionTitle {
                Button {
                    performRecovery(error.recoveryKind)
                } label: {
                    Text(actionTitle)
                        .font(theme.captionFont(weight: .semibold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                                .fill(palette.accent)
                        )
                }
                .buttonStyle(.plain)
            }
            Button {
                appState.activeErrorBanner = nil
            } label: {
                StudioIcon(.close, size: 12, color: palette.mutedText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.subtleSurface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairlineBorder).frame(height: 1)
        }
    }

    private func performRecovery(_ kind: HumanFriendlyError.RecoveryKind?) {
        guard let kind = kind else { return }
        switch kind {
        case .startEngine:
            appState.processManager.startManagedServer(config: appState.serverConfig)
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await appState.refreshEngineStatus()
            }
        case .reduceContextWindow:
            if let idx = appState.activeConversationIndex {
                appState.conversations[idx].dials.numCtx = 4096
                appState.activeErrorBanner = nil
            }
        case .pullMissingModel(let model):
            appState.selectedTab = .modelsAndRAM
            appState.startOrResumeModelPull(rawIdentifier: model)
            appState.activeErrorBanner = nil
        case .retryConnection:
            Task { await appState.refreshEngineStatus() }
            appState.activeErrorBanner = nil
        }
    }
}

// MARK: - Sidebar View & Hardware HUD Capsule

public struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var theme: ThemeManager
    public let palette: StudioPalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // macOS Traffic Light Clearance + New Chat Button
            HStack {
                Spacer()
                Button {
                    appState.createNewConversation()
                } label: {
                    HStack(spacing: 5) {
                        StudioIcon(.plus, size: 12, color: palette.accent)
                        Text("New Chat")
                            .font(theme.captionFont(weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                            .fill(palette.accentSoft)
                    )
                }
                .buttonStyle(.plain)
                .help("Start a new conversation (⌘N)")
            }
            .frame(height: StudioMetrics.trafficLightClearanceHeight)
            .padding(.horizontal, 12)

            // Primary Navigation (⌘1 - ⌘4)
            VStack(spacing: 3) {
                ForEach(PrimaryWorkspaceTab.allCases) { tab in
                    let isSelected = appState.selectedTab == tab
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            appState.selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 9) {
                            StudioIcon(
                                tab.iconName,
                                size: 14,
                                color: isSelected ? palette.accent : palette.secondaryText
                            )
                            Text(tab.title)
                                .font(theme.bodyFont(weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                            Spacer()
                            Text(tab.shortcutLabel)
                                .font(theme.captionFont())
                                .foregroundStyle(palette.mutedText)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6.5)
                        .background(
                            RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                                .fill(isSelected ? palette.cardSurface.opacity(0.85) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)

            // Search Across All Chats
            HStack(spacing: 6) {
                StudioIcon(.search, size: 12, color: palette.mutedText)
                TextField("Filter chats...", text: $appState.searchQuery)
                    .textFieldStyle(.plain)
                    .font(theme.captionFont())
                    .foregroundStyle(palette.primaryText)
                if !appState.searchQuery.isEmpty {
                    Button {
                        appState.searchQuery = ""
                    } label: {
                        StudioIcon(.close, size: 10, color: palette.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                    .fill(palette.cardSurface.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                    .strokeBorder(palette.hairlineBorder, lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            // Section Header
            HStack {
                Text("History")
                    .font(theme.captionFont(weight: .semibold))
                    .foregroundStyle(palette.mutedText)
                Spacer()
                if !appState.trashedItems.isEmpty {
                    Button {
                        appState.isTrashSheetOpen = true
                    } label: {
                        Text("Trash (\(appState.trashedItems.count))")
                            .font(theme.captionFont())
                            .foregroundStyle(palette.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 4)

            // Conversation List
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(appState.filteredConversations) { conv in
                        let isSelected = (appState.activeConversation?.id == conv.id && appState.selectedTab == .chat)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(conv.title)
                                    .font(theme.bodyFont(weight: isSelected ? .medium : .regular))
                                    .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                                    .lineLimit(1)
                                Text(conv.selectedModel.isEmpty ? "No model chosen" : conv.selectedModel.replacingOccurrences(of: ":latest", with: ""))
                                    .font(theme.captionFont())
                                    .foregroundStyle(palette.mutedText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                appState.deleteConversationToTrash(conv.id)
                            } label: {
                                StudioIcon(.trash, size: 11, color: palette.mutedText)
                            }
                            .buttonStyle(.plain)
                            .opacity(isSelected ? 0.85 : 0.0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6.5)
                        .background(
                            RoundedRectangle(cornerRadius: StudioMetrics.controlCornerRadius, style: .continuous)
                                .fill(isSelected ? palette.cardSurface.opacity(0.9) : Color.clear)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appState.activeConversationID = conv.id
                            appState.selectedTab = .chat
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer()

            // Live Apple Silicon Unified Memory & Privacy HUD Capsule
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.isEngineOnline ? palette.statusHealthy : palette.statusWarning)
                        .frame(width: 7, height: 7)
                    Text(appState.isEngineOnline ? "Local Engine · v\(appState.engineVersion)" : "Engine Offline")
                        .font(theme.captionFont(weight: .medium))
                        .foregroundStyle(palette.primaryText)
                    Spacer()
                    StudioIcon(.lock, size: 11, color: palette.accent)
                        .help("100% Local & Encrypted at Rest")
                }

                // Unified RAM Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(palette.hairlineBorder)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(appState.hardware.memoryUsageFraction > 0.85 ? palette.statusWarning : palette.accent)
                            .frame(width: geo.size.width * appState.hardware.memoryUsageFraction)
                    }
                }
                .frame(height: 5)

                HStack {
                    Text(String(format: "RAM %.1f / %.0f GB", appState.hardware.usedMemoryGB, appState.hardware.totalMemoryGB))
                        .font(theme.monoFont(size: 11))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    if let loaded = appState.runningModels.first {
                        Text("\(loaded.name.components(separatedBy: ":").first ?? loaded.name) · Metal")
                            .font(theme.monoFont(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.accent)
                            .lineLimit(1)
                    } else {
                        Text("0 models in RAM")
                            .font(theme.monoFont(size: 10.5))
                            .foregroundStyle(palette.mutedText)
                    }
                }

                Divider().overlay(palette.hairlineBorder)

                // Bottom Bar: Quick Actions & Settings (⌘,)
                HStack {
                    Button {
                        appState.isSettingsSheetOpen = true
                    } label: {
                        HStack(spacing: 5) {
                            StudioIcon(.settings, size: 13, color: palette.secondaryText)
                            Text("Settings")
                                .font(theme.captionFont(weight: .medium))
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Themes, Typography & Privacy (⌘,)")

                    Spacer()

                    Button {
                        appState.isInspectorDrawerOpen.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            StudioIcon(.dials, size: 13, color: appState.isInspectorDrawerOpen ? palette.accent : palette.secondaryText)
                            Text("Dials")
                                .font(theme.captionFont(weight: .medium))
                                .foregroundStyle(appState.isInspectorDrawerOpen ? palette.accent : palette.secondaryText)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Toggle 28-Parameter Inspector Drawer (⌘I)")
                }
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius, style: .continuous)
                    .fill(palette.cardSurface.opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.containerCornerRadius, style: .continuous)
                    .strokeBorder(palette.hairlineBorder, lineWidth: 1)
            )
            .padding(10)
        }
    }
}
