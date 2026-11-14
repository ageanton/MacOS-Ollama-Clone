set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/MotifApp.swift
import SwiftUI
import AppKit

// MARK: - AppKit Window Configurator (Eliminates NSToolbar Top Bar Waste in Fullscreen!)
public struct FullSizeWindowConfigurator: NSViewRepresentable {
    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if window.toolbar != nil {
                window.toolbar = nil
            }
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
        }
    }
}

public struct MotifRootView: View {
    @ObservedObject public var store: WorkstationStore
    @Environment(\.controlActiveState) private var controlActiveState

    private var isWindowActive: Bool {
        controlActiveState != .inactive
    }

    private var tokens: MotifTokens {
        MotifTokens(theme: store.activeTheme, isWindowActive: isWindowActive)
    }

    private var typo: TypographyConfiguration { store.typography }

    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if store.isSidebarVisible {
                    SidebarNavigationView(store: store, tokens: tokens)
                        .frame(width: store.sidebarWidth)
                }

                EditorialConversationView(store: store, tokens: tokens)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if store.isRightUtilityPaneOpen {
                    RightUtilityArtifactPane(store: store, tokens: tokens)
                }
            }
            .background(FullSizeWindowConfigurator().frame(width: 0, height: 0))
            .background(tokens.canvasBackground)
            .ignoresSafeArea(.container, edges: .top)
            .onChange(of: geo.size.width) { _, newWidth in
                let hasArtifacts = !(store.activeSession?.artifacts.isEmpty ?? true)
                if newWidth >= 1540 && hasArtifacts && !store.isRightUtilityPaneOpen && !store.userManuallyClosedRightPaneInWideMode {
                    store.isRightUtilityPaneOpen = true
                } else if newWidth < 1220 && store.isRightUtilityPaneOpen {
                    store.isRightUtilityPaneOpen = false
                }
            }
        }
        .sheet(isPresented: $store.isSettingsModalPresented) {
            WorkstationSettingsModal(store: store)
        }
        .sheet(isPresented: $store.isNewWorkspaceSheetPresented) {
            CreateNamedItemSheet(
                heading: "New Workspace",
                placeholder: "Workspace name (e.g. Systems Architecture)",
                tokens: tokens,
                typo: typo
            ) { name in
                store.createWorkspace(name: name)
            }
        }
        .sheet(isPresented: $store.isNewPresetSheetPresented) {
            CreateNamedItemSheet(
                heading: "Save Parameter Preset",
                placeholder: "Preset name (e.g. Deep Reasoning)",
                tokens: tokens,
                typo: typo
            ) { name in
                store.createPreset(name: name)
            }
        }
        .alert(
            "Large Model Memory Warning",
            isPresented: Binding(
                get: { store.pendingSSDSwapWarningModel != nil },
                set: { if !$0 { store.pendingSSDSwapWarningModel = nil } }
            ),
            presenting: store.pendingSSDSwapWarningModel
        ) { targetModel in
            Button("Load with Tight-RAM Optimization (Recommended)") {
                store.pendingSSDSwapWarningModel = nil
                store.applyTightRAMOptimization(andLoadModel: targetModel)
            }
            Button("Load Anyway (May Use SSD Swap)") {
                store.selectAndLoadModel(targetModel, bypassSwapGuard: true)
            }
            Button("Cancel", role: .cancel) {
                store.pendingSSDSwapWarningModel = nil
            }
        } message: { targetModel in
            let reclaimableGB = Double(store.liveOllamaResidentBytes) / 1_073_741_824.0
            let availableGB = store.memorySnapshot.headroomGB + reclaimableGB
            Text("“\(targetModel.shortDisplayName)” requires \(targetModel.formattedSize), and \(String(format: "%.1f GB", availableGB)) is currently available before swap. Tight-RAM Optimization enables Q4_0 KV cache compression, 4k context, and safe GPU layer splitting.")
        }
    }
}

public final class MotifAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        CustomFontRegistrar.registerBundledFonts()
        NSWindow.allowsAutomaticWindowTabbing = false
    }
}

@main
public struct MotifApp: App {
    @NSApplicationDelegateAdaptor(MotifAppDelegate.self) private var appDelegate
    @StateObject private var store = WorkstationStore()

    private func keyEq(_ raw: String, fallback: Character) -> KeyEquivalent {
        let ch = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().first ?? fallback
        return KeyEquivalent(ch)
    }

    public var body: some Scene {
        WindowGroup("Motif") {
            let rootTokens = MotifTokens(theme: store.activeTheme, isWindowActive: true)
            MotifRootView(store: store)
                .frame(minWidth: 880, minHeight: 560)
                .preferredColorScheme(rootTokens.isEffectivelyDark ? .dark : .light)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    store.createNewSession(folderID: nil)
                }
                .keyboardShortcut(keyEq(store.shortcuts.newChatKey, fallback: "n"), modifiers: [.command])

                Button("Toggle Left Sidebar") {
                    store.isSidebarVisible.toggle()
                }
                .keyboardShortcut(keyEq(store.shortcuts.toggleSidebarKey, fallback: "s"), modifiers: [.command])

                Button("Toggle Code Inspector") {
                    store.userManuallyClosedRightPaneInWideMode = store.isRightUtilityPaneOpen
                    store.isRightUtilityPaneOpen.toggle()
                }
                .keyboardShortcut(keyEq(store.shortcuts.toggleInspectorKey, fallback: "\\"), modifiers: [.command])

                Divider()

                Button("Increase Font Size") {
                    store.adjustActiveFontSize(delta: 0.5)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("Decrease Font Size") {
                    store.adjustActiveFontSize(delta: -0.5)
                }
                .keyboardShortcut("-", modifiers: [.command])

                Divider()

                Button("Stop Generation") {
                    store.stopActiveGeneration()
                }
                .keyboardShortcut(keyEq(store.shortcuts.stopGenerationKey, fallback: "."), modifiers: [.command])
            }
        }
    }
}
EOF
