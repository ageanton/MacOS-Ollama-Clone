set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/Views/SidebarNavigationView.swift
import SwiftUI
import AppKit

public struct SidebarNavigationView: View {
    @ObservedObject public var store: WorkstationStore
    public let tokens: MotifTokens

    @State private var renamingSessionID: UUID? = nil
    @State private var renameDraft: String = ""
    @FocusState private var isRenameFocused: Bool

    @State private var renamingFolderID: UUID? = nil
    @State private var folderRenameDraft: String = ""
    @FocusState private var isFolderRenameFocused: Bool

    private var typo: TypographyConfiguration { store.typography }

    private var searchQuery: String {
        store.sidebarSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var unfiledSessions: [ConversationSession] {
        store.sessions.filter { session in
            guard !session.isTrashed, session.folderID == nil else { return false }
            guard !searchQuery.isEmpty else { return true }
            return session.title.lowercased().contains(searchQuery)
        }
    }

    private var trashedSessions: [ConversationSession] {
        store.sessions.filter { $0.isTrashed }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Header: Crash-Free Sidebar Toggle, Motif Wordmark & Prominent '+' Button
            HStack(alignment: .center, spacing: 10) {
                Text("Motif")
                    .font(typo.wordmark(size: 18))
                    .foregroundColor(tokens.primaryText)

                Spacer()

                Button {
                    commitActiveRenameIfNeeded()
                    store.isSidebarVisible = false
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundColor(tokens.secondaryText)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(tokens.elevatedSurface)
                        )
                }
                .buttonStyle(.plain)
                .help("Hide Sidebar (⌘\(store.shortcuts.toggleSidebarKey.uppercased()))")

                Button {
                    commitActiveRenameIfNeeded()
                    store.createNewSession(folderID: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(tokens.accentForeground)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(tokens.accentAction)
                        )
                }
                .buttonStyle(.plain)
                .help("Start New Chat (⌘\(store.shortcuts.newChatKey.uppercased()))")
            }
            .padding(.horizontal, 16)
            .padding(.top, store.isWindowFullscreen ? 12 : 34)
            .padding(.bottom, 12)

            // FTS5 Full-Text Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundColor(tokens.mutedText)

                TextField("Search chats & messages…", text: $store.sidebarSearchQuery)
                    .textFieldStyle(.plain)
                    .font(typo.sans(size: 12.5))
                    .foregroundColor(tokens.primaryText)

                if !store.sidebarSearchQuery.isEmpty {
                    Button {
                        store.sidebarSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(tokens.mutedText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(tokens.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            HairlineDivider(tokens: tokens)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if !store.ftsSearchResults.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("MESSAGE MATCHES")
                                .font(typo.mono(size: 10, weight: .semibold))
                                .tracking(0.7)
                                .foregroundColor(tokens.mutedText)
                                .padding(.horizontal, 16)

                            ForEach(store.ftsSearchResults) { hit in
                                HStack(alignment: .top, spacing: 6) {
                                    Button {
                                        commitActiveRenameIfNeeded()
                                        store.selectedSessionID = hit.sessionID
                                        store.pendingScrollToMessageID = hit.messageID
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(hit.sessionTitle)
                                                .font(typo.sans(size: 12, weight: .semibold))
                                                .foregroundColor(tokens.primaryText)
                                                .lineLimit(1)
                                            Text(hit.snippetText)
                                                .font(typo.sans(size: 11))
                                                .foregroundColor(tokens.secondaryText)
                                                .lineLimit(2)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(hit.snippetText, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                            .foregroundColor(tokens.mutedText)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Copy matching snippet")
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(tokens.elevatedSurface.opacity(0.6))
                                )
                                .padding(.horizontal, 8)
                            }
                        }
                    }

                    // Workspaces Section (With Context Menu to Rename or Delete Workspaces)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("WORKSPACES")
                                .font(typo.mono(size: 10, weight: .semibold))
                                .tracking(0.7)
                                .foregroundColor(tokens.mutedText)
                            Spacer()
                            Button {
                                store.isNewWorkspaceSheetPresented = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 11))
                                    .foregroundColor(tokens.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help("Create Workspace")
                        }
                        .padding(.horizontal, 16)

                        if store.folders.isEmpty {
                            Button {
                                store.isNewWorkspaceSheetPresented = true
                            } label: {
                                Text("Create a workspace…")
                                    .font(typo.sans(size: 12))
                                    .foregroundColor(tokens.mutedText)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ForEach(store.folders.indices, id: \.self) { fIdx in
                                let folder = store.folders[fIdx]
                                let folderChats = store.sessions.filter {
                                    !$0.isTrashed && $0.folderID == folder.id && (searchQuery.isEmpty || $0.title.lowercased().contains(searchQuery))
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    if renamingFolderID == folder.id {
                                        HStack(spacing: 6) {
                                            TextField("Workspace name", text: $folderRenameDraft)
                                                .textFieldStyle(.plain)
                                                .font(typo.sans(size: 12.5, weight: .medium))
                                                .foregroundColor(tokens.primaryText)
                                                .focused($isFolderRenameFocused)
                                                .onSubmit {
                                                    store.renameWorkspace(folderID: folder.id, newName: folderRenameDraft)
                                                    renamingFolderID = nil
                                                }
                                                .onExitCommand {
                                                    renamingFolderID = nil
                                                }

                                            Button {
                                                store.renameWorkspace(folderID: folder.id, newName: folderRenameDraft)
                                                renamingFolderID = nil
                                            } label: {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 11.5))
                                                    .foregroundColor(tokens.accentAction)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 14)
                                        .frame(height: 28)
                                    } else {
                                        HStack(spacing: 6) {
                                            Button {
                                                withAnimation(.easeOut(duration: 0.12)) {
                                                    store.folders[fIdx].isExpanded.toggle()
                                                }
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: "chevron.right")
                                                        .font(.system(size: 9, weight: .semibold))
                                                        .foregroundColor(tokens.mutedText)
                                                        .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                                                    Text(folder.name)
                                                        .font(typo.sans(size: 12.5, weight: .medium))
                                                        .foregroundColor(tokens.primaryText)
                                                        .lineLimit(1)
                                                    Spacer()
                                                }
                                                .contentShape(Rectangle())
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                store.folders[fIdx].isExpanded = true
                                                store.createNewSession(folderID: folder.id)
                                            } label: {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 10.5, weight: .semibold))
                                                    .foregroundColor(tokens.secondaryText)
                                                    .frame(width: 20, height: 20)
                                            }
                                            .buttonStyle(.plain)
                                            .help("New chat in \(folder.name)")
                                        }
                                        .padding(.horizontal, 14)
                                        .frame(height: 28)
                                        .contextMenu {
                                            Button("New Chat in Workspace") {
                                                store.folders[fIdx].isExpanded = true
                                                store.createNewSession(folderID: folder.id)
                                            }
                                            Button("Rename Workspace") {
                                                folderRenameDraft = folder.name
                                                renamingFolderID = folder.id
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                    isFolderRenameFocused = true
                                                }
                                            }
                                            Divider()
                                            Button("Delete Workspace (Keep Chats)", role: .destructive) {
                                                store.deleteWorkspace(folderID: folder.id)
                                            }
                                        }
                                    }

                                    if folder.isExpanded {
                                        ForEach(folderChats) { chat in
                                            chatRowItem(chat, indented: true)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Conversations Section
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CONVERSATIONS")
                            .font(typo.mono(size: 10, weight: .semibold))
                            .tracking(0.7)
                            .foregroundColor(tokens.mutedText)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 2)

                        if unfiledSessions.isEmpty {
                            Text(searchQuery.isEmpty ? "No chats yet" : "No title matches")
                                .font(typo.sans(size: 12))
                                .foregroundColor(tokens.mutedText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        } else {
                            ForEach(unfiledSessions) { session in
                                chatRowItem(session, indented: false)
                            }
                        }
                    }

                    // Recoverable Trash Section
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    store.isTrashExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(tokens.mutedText)
                                        .rotationEffect(.degrees(store.isTrashExpanded ? 90 : 0))
                                    Text("TRASH (\(trashedSessions.count))")
                                        .font(typo.mono(size: 10, weight: .semibold))
                                        .tracking(0.7)
                                        .foregroundColor(tokens.mutedText)
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if !trashedSessions.isEmpty {
                                Button("Empty") {
                                    store.emptyTrashPermanently()
                                }
                                .font(typo.sans(size: 11, weight: .medium))
                                .foregroundColor(tokens.secondaryText)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)

                        if store.isTrashExpanded {
                            if trashedSessions.isEmpty {
                                Text("Trash is empty")
                                    .font(typo.sans(size: 11.5))
                                    .foregroundColor(tokens.mutedText)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 4)
                            } else {
                                ForEach(trashedSessions) { trashed in
                                    HStack(spacing: 6) {
                                        Text(trashed.title)
                                            .font(typo.sans(size: 12))
                                            .foregroundColor(tokens.secondaryText)
                                            .lineLimit(1)
                                        Spacer()
                                        Button("Restore") {
                                            store.restoreSessionFromTrash(trashed.id)
                                        }
                                        .font(typo.sans(size: 11, weight: .medium))
                                        .foregroundColor(tokens.accentAction)
                                        .buttonStyle(.plain)

                                        Button {
                                            store.permanentlyDeleteSession(trashed.id)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9.5, weight: .semibold))
                                                .foregroundColor(tokens.mutedText)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Delete permanently")
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 26)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .onChange(of: isRenameFocused) { _, focused in
                if !focused, renamingSessionID != nil {
                    commitActiveRenameIfNeeded()
                }
            }

            Spacer(minLength: 0)

            HairlineDivider(tokens: tokens)

            Button {
                commitActiveRenameIfNeeded()
                store.isSettingsModalPresented = true
            } label: {
                HStack {
                    Text("Settings")
                        .font(typo.sans(size: 12.5, weight: .medium))
                        .foregroundColor(tokens.secondaryText)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .frame(height: 38)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(tokens.sidebarBackground)
        .overlay(alignment: .trailing) {
            HairlineDivider(axis: .vertical, tokens: tokens)
                .ignoresSafeArea()
        }
    }

    private func commitActiveRenameIfNeeded() {
        if let activeFolderID = renamingFolderID {
            store.renameWorkspace(folderID: activeFolderID, newName: folderRenameDraft)
            renamingFolderID = nil
        }
        guard let activeID = renamingSessionID else { return }
        store.commitInlineRename(sessionID: activeID, proposedName: renameDraft)
        renamingSessionID = nil
    }

    @ViewBuilder
    private func chatRowItem(_ session: ConversationSession, indented: Bool) -> some View {
        let isSelected = store.selectedSessionID == session.id
        let isGeneratingHere = store.isStreamingGeneration && store.streamingSessionID == session.id
        let isBranchedChat = session.title.lowercased().hasPrefix("branch")

        if renamingSessionID == session.id {
            HStack(spacing: 6) {
                TextField("Chat title", text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(typo.sans(size: 13, weight: .medium))
                    .foregroundColor(tokens.primaryText)
                    .focused($isRenameFocused)
                    .onSubmit {
                        commitActiveRenameIfNeeded()
                    }
                    .onExitCommand {
                        renamingSessionID = nil
                    }

                Button {
                    commitActiveRenameIfNeeded()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(tokens.accentAction)
                }
                .buttonStyle(.plain)
                .help("Save title (Return)")

                Button {
                    renamingSessionID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(tokens.mutedText)
                }
                .buttonStyle(.plain)
                .help("Cancel rename (Esc)")
            }
            .padding(.leading, indented ? 22 : 10)
            .padding(.trailing, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tokens.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(tokens.accentAction, lineWidth: 1)
            )
            .padding(.horizontal, 8)
        } else {
            Button {
                commitActiveRenameIfNeeded()
                store.selectedSessionID = session.id
            } label: {
                HStack(spacing: 6) {
                    if isBranchedChat {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isSelected ? tokens.accentAction : tokens.mutedText)
                    }

                    Text(session.title)
                        .font(typo.sans(size: 13, weight: isSelected ? .medium : .regular))
                        .foregroundColor(isSelected ? tokens.primaryText : tokens.secondaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isGeneratingHere {
                        Circle()
                            .fill(tokens.statusOnline)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.leading, indented ? 22 : 10)
                .padding(.trailing, 10)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? tokens.selectionPill : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .contextMenu {
                Button("Rename") {
                    commitActiveRenameIfNeeded()
                    renameDraft = session.title
                    renamingSessionID = session.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isRenameFocused = true
                    }
                }
                Button("Duplicate") {
                    store.duplicateSession(session.id)
                }
                Button("Export as Markdown…") {
                    store.exportSessionAsMarkdown(session.id)
                }
                if !store.folders.isEmpty {
                    Menu("Move to Workspace") {
                        Button("None (Conversations)") {
                            if let idx = store.sessions.firstIndex(where: { $0.id == session.id }) {
                                store.sessions[idx].folderID = nil
                                store.saveAllState()
                            }
                        }
                        ForEach(store.folders) { folder in
                            Button(folder.name) {
                                if let idx = store.sessions.firstIndex(where: { $0.id == session.id }) {
                                    store.sessions[idx].folderID = folder.id
                                    store.saveAllState()
                                }
                            }
                        }
                    }
                }
                Divider()
                Button("Move to Trash", role: .destructive) {
                    store.moveSessionToTrash(session.id)
                }
            }
        }
    }
}
EOF
