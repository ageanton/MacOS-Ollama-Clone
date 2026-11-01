import SwiftUI
import AppKit

public struct MessageRowView: View {
    @Binding public var message: ChatMessage
    public let palette: AetherPalette
    @State private var isCopied: Bool = false

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Role & Timestamp
            HStack(spacing: 8) {
                Text(message.role == .user ? "You" : (message.modelUsed?.replacingOccurrences(of: ":latest", with: "") ?? "Assistant"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(message.role == .user ? palette.secondaryText : palette.accent)

                if let tps = message.tokensPerSecond {
                    Text(String(format: "%.1f tok/s", tps))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.mutedText)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isCopied ? palette.statusHealthy : palette.mutedText)
                }
                .buttonStyle(.plain)
                .help("Copy Message")
            }

            // Thinking Accordion (for DeepSeek-R1, QwQ, etc.)
            if !message.thinkingContent.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        message.isThinkingExpanded.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: message.isThinkingExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                            Text(message.isThinkingExpanded ? "Hide Thinking Process" : "Thought Process (\(message.thinkingContent.count / 4) tokens)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(palette.mutedText)
                    }
                    .buttonStyle(.plain)

                    if message.isThinkingExpanded {
                        Text(message.thinkingContent)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 6).fill(palette.codeSurface))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.hairlineBorder, lineWidth: 1))
                    }
                }
                .padding(.vertical, 2)
            }

            // Main Message Content
            if message.content.isEmpty && message.role == .assistant {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Thinking...")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.mutedText)
                }
            } else {
                Text(message.content)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.primaryText)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AetherMetrics.cardCornerRadius)
                .fill(message.role == .user ? palette.subtleSurface : palette.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AetherMetrics.cardCornerRadius)
                .stroke(palette.hairlineBorder, lineWidth: 1)
        )
    }
}
