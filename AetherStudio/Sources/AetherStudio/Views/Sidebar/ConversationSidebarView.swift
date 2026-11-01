import SwiftUI

public struct ConversationSidebarView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var theme: ThemeCoordinator
    public let palette: AetherPalette

    public var body: some View {
        VStack(spacing: 0) {
            // Header: New Chat & Filter
            VStack(spacing: 8) {
                HStack {
                    Text("Aether")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    Spacer()
                    Button {
                        coordinator.newConversation()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(palette.primaryText)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))
                    }
                    .buttonStyle(.plain)
                    .help("New Conversation (⌘N)")
                }

                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.mutedText)
                    TextField("Search chats...", text: $coordinator.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !coordinator.searchQuery.isEmpty {
                        Button {
                            coordinator.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.mutedText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))
            }
            .padding(12)

            Divider().overlay(palette.hairlineBorder)

            // Conversation List
            List(selection: $coordinator.activeConversationID) {
                ForEach(coordinator.filteredConversations) { conv in
                    ConversationRow(conversation: conv, palette: palette)
                        .tag(conv.id)
                        .contextMenu {
                            Button(conv.isPinned ? "Unpin" : "Pin") {
                                if let idx = coordinator.conversations.firstIndex(where: { $0.id == conv.id }) {
                                    coordinator.conversations[idx].isPinned.toggle()
                                    coordinator.persistVault()
                                }
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                coordinator.deleteConversation(id: conv.id)
                            }
                        }
                }
            }
            .listStyle(.sidebar)

            Divider().overlay(palette.hairlineBorder)

            // Footer: Unified RAM & Storage Drive Indicator
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(coordinator.isEngineOnline ? palette.statusHealthy : palette.statusDanger)
                            .frame(width: 6, height: 6)
                        Text(coordinator.isEngineOnline ? coordinator.engineVersion : "Engine Offline")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }
                    Spacer()
                    Text(String(format: "%.1f GB / %.0f GB", coordinator.hardware.currentSnapshot.usedRAMGB, coordinator.hardware.currentSnapshot.totalRAMGB))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.mutedText)
                }

                // Storage Drive pill
                Button {
                    coordinator.selectedSettingsTab = .externalDrive
                    coordinator.isSettingsOpen = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: coordinator.externalStatus.isExternal ? "externaldrive.fill" : "internaldrive")
                            .font(.system(size: 11))
                            .foregroundStyle(coordinator.externalStatus.isMountedAndWritable ? palette.accent : palette.statusWarning)
                        Text(coordinator.externalStatus.statusText)
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.primaryText)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 5).fill(palette.subtleSurface))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
        }
        .background(palette.windowCanvas)
    }
}

public struct ConversationRow: View {
    public let conversation: Conversation
    public let palette: AetherPalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if conversation.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.accent)
                }
                Text(conversation.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
            }

            if let last = conversation.messages.last {
                Text(last.content.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
