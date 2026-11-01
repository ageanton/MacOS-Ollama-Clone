import SwiftUI

public struct ChatInputBar: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var theme: ThemeCoordinator
    public let palette: AetherPalette
    @State private var inputText: String = ""

    public var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                // Text input
                TextField("Send a message... (Return to send, Shift-Return for newline)", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .lineLimit(1...8)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.cardSurface))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.hairlineBorder, lineWidth: 1))
                    .onSubmit {
                        if !NSEvent.modifierFlags.contains(.shift) {
                            send()
                        }
                    }

                // Send or Stop button
                if coordinator.isGenerating {
                    Button {
                        coordinator.stopGeneration()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 7).fill(palette.statusDanger))
                    }
                    .buttonStyle(.plain)
                    .help("Stop Generating")
                } else {
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(width: 32, height: 32)
                            .background(RoundedRectangle(cornerRadius: 7).fill(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? palette.mutedText.opacity(0.4) : palette.accent))
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send Message (Return)")
                }
            }

            // Sub-bar: Context token indicator
            HStack {
                let tokens = coordinator.activeConversation?.totalTokens ?? 0
                let maxCtx = coordinator.activeConversation?.dials.numCtx ?? 8192
                Text("\(tokens) / \(maxCtx) tokens")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.mutedText)

                Spacer()

                Button {
                    coordinator.isDialsOpen = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10))
                        Text("Sampling Dials (⌘I)")
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)
        }
        .padding(12)
        .background(palette.windowCanvas)
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        coordinator.sendUserMessage(text)
    }
}
