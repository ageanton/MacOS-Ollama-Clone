# Aether Studio 🌌

A native macOS desktop application for Apple Silicon (M-series) Macs designed for local LLM inference with Ollama and external drive model storage.

---

## 💎 Design Philosophy & Core Tenets

1. **The User Never Needs Terminal**:
   Full visual controls for model selection, external drive symlinking, sampling dials, and engine status.
2. **First-Class External Drive Model Support**:
   - Stores gigabytes of LLM weights on external SSDs (`/Volumes/...`).
   - Automatically links `~/.ollama/models` to your external drive with 1 click so native CLI, Ollama.app, and Aether Studio all share the external volume.
   - Discovers loose `.gguf` files on your external drive and registers them in 1 click without copying or duplicating storage.
3. **Restrained Apple Pro Aesthetic**:
   Inspired by Things 3 and Apple Pro apps. Zero generic purple neon AI glows. Quiet dialogue canvases and calm typography.

---

## 📁 Project Architecture

```
AetherStudio/
├── Package.swift                    # Swift 5.10 / macOS 14+ manifest (zero external dependencies)
├── .github/
│   └── workflows/
│       └── build.yml                # GitHub Actions workflow: generates DMG installer & release
├── Sources/
│   └── AetherStudio/
│       ├── App/
│       │   ├── AetherApp.swift      # @main application entry point with menu commands (⌘N, ⌘I, ⌘,)
│       │   └── AppCoordinator.swift # State coordinator (conversations, models, processes, vault)
│       ├── Core/
│       │   ├── Constants.swift      # Application constants, default port & paths
│       │   └── DesignSystem.swift   # 5 bespoke themes (Botanical Sage, Kyoto Hinoki, Braun, etc.)
│       ├── Models/
│       │   ├── ModelEntities.swift  # OllamaModel, DiscoveredGGUF, RunningModelProcess
│       │   ├── SamplingDials.swift  # Temperature, Top-P, Min-P, Repeat Penalty, num_ctx
│       │   ├── Conversation.swift   # ChatMessage & Conversation entities
│       │   └── StorageConfig.swift  # Fast path normalization & external drive inspection
│       ├── Services/
│       │   ├── ExternalDriveManager.swift # External volume discovery, symlinking, GGUF auto-import
│       │   ├── ProcessSupervisor.swift    # Ollama background daemon manager & log stream
│       │   ├── OllamaClient.swift         # Async/await REST client & NDJSON chat stream
│       │   ├── HardwareMonitor.swift      # Darwin Apple Silicon unified memory monitor
│       │   └── VaultStorage.swift         # Safe atomic JSON persistence
│       ├── Views/
│       │   ├── RootView.swift             # SplitView container & sheet modals
│       │   ├── Sidebar/
│       │   │   └── ConversationSidebarView.swift # Filterable chat history & RAM gauge
│       │   ├── Chat/
│       │   │   ├── ChatContainerView.swift       # Message stream & quiet header
│       │   │   ├── ModelPickerMenu.swift         # Header dropdown with external drive section
│       │   │   ├── MessageRowView.swift          # Dialogue cards with collapsible thinking
│       │   │   └── ChatInputBar.swift            # Auto-sizing input & token stats
│       │   └── Settings/
│       │       ├── ExternalDriveSettingsView.swift # Dedicated external storage manager
│       │       ├── EngineSettingsView.swift       # Network bindings, Flash Attention & logs
│       │       └── SamplingDialsInspector.swift   # Parameter sliders & persona editor
│       └── Resources/
│           ├── Info.plist           # TCC permissions (NSRemovableVolumesUsageDescription)
│           └── AetherStudio.entitlements
```

---

## 🛠 Compiling Locally

To build and run directly on your Mac:

```bash
cd AetherStudio
swift build -c release --arch arm64
```

---

## 🚀 GitHub Actions Compilation & Release

The repository includes a ready-to-run GitHub Actions workflow at `.github/workflows/build.yml`.
When you push to `main` or push a version tag (`git tag v1.0.0 && git push --tags`):

1. GitHub compiles the Swift package natively on an Apple Silicon macOS runner (`macos-14`).
2. Bundles the app with complete privacy permissions for external drives.
3. Packages the app into a compressed `.dmg` (`AetherStudio-AppleSilicon.dmg`).
4. Attaches the DMG to GitHub Releases and Actions Artifacts for 1-click download.
