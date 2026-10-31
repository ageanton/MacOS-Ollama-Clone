import SwiftUI
import AppKit

@main
public struct OllamaStudioApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var theme = ThemeManager()

    public init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    public var body: some Scene {
        WindowGroup("Ollama Studio") {
            MainView()
                .environmentObject(appState)
                .environmentObject(theme)
                .frame(minWidth: 980, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    appState.createNewConversation()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandMenu("Workspace") {
                Button("Conversations") { appState.selectedTab = .chat }
                    .keyboardShortcut("1", modifiers: [.command])

                Button("Models & Unified RAM") { appState.selectedTab = .modelsAndRAM }
                    .keyboardShortcut("2", modifiers: [.command])

                Button("Visual Model Builder") { appState.selectedTab = .modelBuilder }
                    .keyboardShortcut("3", modifiers: [.command])

                Button("Server Control Center") { appState.selectedTab = .serverControl }
                    .keyboardShortcut("4", modifiers: [.command])

                Divider()

                Button("Toggle Model Dials Inspector") {
                    appState.isInspectorDrawerOpen.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button("Session Controls & Quick Toggles") {
                    appState.isQuickActionSheetOpen.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command])

                Divider()

                Button("Studio Settings & Themes...") {
                    appState.isSettingsSheetOpen = true
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
