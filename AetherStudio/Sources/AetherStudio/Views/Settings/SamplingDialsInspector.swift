import SwiftUI

public struct SamplingDialsInspector: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var theme: ThemeCoordinator
    public let palette: AetherPalette
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    Text("Sampling Dials & Precision Parameters")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .controlSize(.small)
            }
            .padding(16)
            .background(palette.windowCanvas)

            Divider().overlay(palette.hairlineBorder)

            if let conv = coordinator.activeConversation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // System Prompt
                        VStack(alignment: .leading, spacing: 6) {
                            Text("System Persona Prompt")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                            TextEditor(text: bindingForDials().systemPrompt)
                                .font(.system(size: 12.5))
                                .frame(height: 80)
                                .padding(4)
                                .background(palette.cardSurface)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.hairlineBorder, lineWidth: 1))
                        }

                        // Sliders
                        Group {
                            // Temperature
                            DialSlider(
                                label: "Temperature",
                                value: bindingForDials().temperature,
                                range: 0.0...1.5,
                                step: 0.05,
                                format: "%.2f",
                                hint: "Higher = creative & varied, Lower = deterministic & focused",
                                palette: palette
                            )

                            // Top-P
                            DialSlider(
                                label: "Top-P (Nucleus Sampling)",
                                value: bindingForDials().topP,
                                range: 0.0...1.0,
                                step: 0.05,
                                format: "%.2f",
                                hint: "Limits token selection to cumulative probability threshold",
                                palette: palette
                            )

                            // Min-P
                            DialSlider(
                                label: "Min-P",
                                value: bindingForDials().minP,
                                range: 0.0...0.5,
                                step: 0.01,
                                format: "%.2f",
                                hint: "Alternative to Top-P: cuts off tokens relative to top token probability",
                                palette: palette
                            )

                            // Repeat Penalty
                            DialSlider(
                                label: "Repeat Penalty",
                                value: bindingForDials().repeatPenalty,
                                range: 1.0...2.0,
                                step: 0.05,
                                format: "%.2f",
                                hint: "Penalizes recently generated tokens to prevent repetition loops",
                                palette: palette
                            )
                        }

                        // Context Length Picker
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Context Length (num_ctx)")
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                                Text("\(conv.dials.numCtx) tokens")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(palette.accent)
                            }
                            Picker("Context Length", selection: bindingForDials().numCtx) {
                                Text("2,048").tag(2048)
                                Text("4,096").tag(4096)
                                Text("8,192").tag(8192)
                                Text("16,384").tag(16384)
                                Text("32,768").tag(32768)
                            }
                            .pickerStyle(.segmented)
                        }

                        Divider().overlay(palette.hairlineBorder)

                        // Save Defaults
                        HStack {
                            Button("Reset Defaults") {
                                if let id = coordinator.activeConversation?.id,
                                   let idx = coordinator.conversations.firstIndex(where: { $0.id == id }) {
                                    coordinator.conversations[idx].dials = SamplingDials()
                                    coordinator.persistVault()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.secondaryText)

                            Spacer()

                            Button("Save as Model Default") {
                                if !conv.selectedModel.isEmpty {
                                    coordinator.modelDefaults[conv.selectedModel] = conv.dials
                                    coordinator.persistVault()
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.system(size: 12))
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(width: 480, height: 520)
        .background(palette.windowCanvas)
    }

    private func bindingForDials() -> Binding<SamplingDials> {
        guard let id = coordinator.activeConversation?.id,
              let idx = coordinator.conversations.firstIndex(where: { $0.id == id }) else {
            return .constant(SamplingDials())
        }
        return $coordinator.conversations[idx].dials
    }
}

public struct DialSlider: View {
    public let label: String
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public let step: Double
    public let format: String
    public let hint: String
    public let palette: AetherPalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(palette.accent)
            }
            Slider(value: $value, in: range, step: step)
                .tint(palette.accent)
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(palette.mutedText)
        }
    }
}
