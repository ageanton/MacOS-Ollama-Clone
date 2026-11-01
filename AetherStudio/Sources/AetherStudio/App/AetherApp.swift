import SwiftUI

@main
struct AetherApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var theme = ThemeCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(theme)
                .frame(minWidth: 840, minHeight: 560)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    coordinator.newConversation()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandMenu("Model") {
                Button("Sampling Dials & Precision...") {
                    coordinator.isDialsOpen = true
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Refresh Engine Status") {
                    Task { await coordinator.refreshEngine() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Divider()

                Button("Manage External Drive Storage...") {
                    coordinator.selectedSettingsTab = .externalDrive
                    coordinator.isSettingsOpen = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsContainerView(palette: theme.palette(for: .light))
                .environmentObject(coordinator)
                .environmentObject(theme)
        }
        #endif
    }
}
