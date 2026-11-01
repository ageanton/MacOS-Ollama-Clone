import SwiftUI

public struct ChatContainerView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var theme: ThemeCoordinator
    public let palette: AetherPalette

    public var body: some View {
        VStack(spacing: 0) {
            // Quiet Top Header
            HStack(spacing: 8) {
                ModelPickerMenu(palette: palette)

                if coordinator.externalStatus.isExternal {
                    HStack(spacing: 4) {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(palette.accent)
                        Text(coordinator.externalStatus.volumeName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(palette.secondaryText)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(palette.subtleSurface))
                }

                Spacer()

                Button {
                    coordinator.isSettingsOpen = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(palette.windowCanvas)

            Divider().overlay(palette.hairlineBorder)

            // Message Scroll Area
            if let activeConv = coordinator.activeConversation {
                if activeConv.messages.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "cpu")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(palette.accent)

                        VStack(spacing: 6) {
                            Text("Aether Studio")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                            Text("Fast, local Apple Silicon inference with external drive storage.")
                                .font(.system(size: 13))
                                .foregroundStyle(palette.secondaryText)
                        }

                        HStack(spacing: 12) {
                            Button {
                                coordinator.selectedSettingsTab = .externalDrive
                                coordinator.isSettingsOpen = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "externaldrive")
                                    Text("Manage External Models...")
                                }
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 6).fill(palette.subtleSurface))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.hairlineBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(palette.windowCanvas)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(bindingForMessages()) { $msg in
                                    MessageRowView(message: $msg, palette: palette)
                                        .id(msg.id)
                                }
                            }
                            .padding(16)
                        }
                        .background(palette.windowCanvas)
                        .onChange(of: activeConv.messages.last?.content) { _ in
                            if let lastID = activeConv.messages.last?.id {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider().overlay(palette.hairlineBorder)

            // Chat input bar
            ChatInputBar(palette: palette)
        }
    }

    private func bindingForMessages() -> Binding<[ChatMessage]> {
        guard let id = coordinator.activeConversation?.id,
              let idx = coordinator.conversations.firstIndex(where: { $0.id == id }) else {
            return .constant([])
        }
        return $coordinator.conversations[idx].messages
    }
}
