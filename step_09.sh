set -eo pipefail
cat << 'EOF' > Motif/Sources/Motif/Components/GlassAndTelemetryComponents.swift
import SwiftUI
import AppKit

extension TypographyConfiguration {
    public var baseFontSize: Double {
        get { windowedBaseFontSize }
        set { windowedBaseFontSize = newValue }
    }
}

// MARK: - Crisp 1px Physical Hairline
public struct HairlineDivider: View {
    public var axis: Axis = .horizontal
    public let tokens: MotifTokens
    @Environment(\.displayScale) private var displayScale

    private var thickness: CGFloat { 1.0 / max(1.0, displayScale) }

    public init(axis: Axis = .horizontal, tokens: MotifTokens) {
        self.axis = axis
        self.tokens = tokens
    }

    public var body: some View {
        if axis == .horizontal {
            Rectangle().fill(tokens.hairline).frame(height: thickness)
        } else {
            Rectangle().fill(tokens.hairline).frame(width: thickness)
        }
    }
}

// MARK: - Reliable AppKit NSScrollView Bottom Detector (520pt Scroll Threshold so Jump Arrow Never Pops Up on 2-3 Lines!)
public struct ScrollViewBottomObserver: NSViewRepresentable {
    @Binding public var isScrolledAwayFromBottom: Bool

    public init(isScrolledAwayFromBottom: Binding<Bool>) {
        self._isScrolledAwayFromBottom = isScrolledAwayFromBottom
    }

    public func makeNSView(context: Context) -> ObserverNSView {
        let view = ObserverNSView()
        view.onScrolledAwayChange = { away in
            if self.isScrolledAwayFromBottom != away {
                self.isScrolledAwayFromBottom = away
            }
        }
        return view
    }

    public func updateNSView(_ nsView: ObserverNSView, context: Context) {
        nsView.onScrolledAwayChange = { away in
            if self.isScrolledAwayFromBottom != away {
                self.isScrolledAwayFromBottom = away
            }
        }
        nsView.evaluateScrollPosition()
    }

    public final class ObserverNSView: NSView {
        public var onScrolledAwayChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private weak var trackedScrollView: NSScrollView?

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                self?.attachToEnclosingScrollView()
            }
        }

        private func attachToEnclosingScrollView() {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()

            var candidate: NSView? = self
            var foundScroll: NSScrollView? = nil
            while let cur = candidate {
                if let sv = cur as? NSScrollView {
                    foundScroll = sv
                    break
                }
                candidate = cur.superview
            }
            guard let scrollView = foundScroll else { return }
            trackedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            scrollView.contentView.postsFrameChangedNotifications = true
            scrollView.documentView?.postsFrameChangedNotifications = true

            let center = NotificationCenter.default
            let bObs = center.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
                self?.evaluateScrollPosition()
            }
            let fObs = center.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
                self?.evaluateScrollPosition()
            }
            let dObs = center.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView.documentView, queue: .main) { [weak self] _ in
                self?.evaluateScrollPosition()
            }
            let fsObs = center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.evaluateScrollPosition()
                }
            }
            observers = [bObs, fObs, dObs, fsObs]
            evaluateScrollPosition()
        }

        public func evaluateScrollPosition() {
            guard let sv = trackedScrollView, let docView = sv.documentView else { return }
            let clipBounds = sv.contentView.bounds
            let docHeight = docView.frame.height

            // Subtract the bottom anchor spacer (~160pt) first so we measure true prose overflow
            let realContentOverflow = (docHeight - 160.0) - clipBounds.height
            if realContentOverflow <= 420.0 {
                onScrolledAwayChange?(false)
                return
            }

            // Distance above the bottom spacer: only show the Jump button when scrolled > 520pt (~18-20 lines) up!
            let distanceAboveBottomSpacer = max(0.0, (docHeight - 150.0) - clipBounds.maxY)
            let hideThreshold: CGFloat = 140.0
            let showThreshold: CGFloat = 520.0

            if distanceAboveBottomSpacer <= hideThreshold {
                onScrolledAwayChange?(false)
            } else if distanceAboveBottomSpacer >= showThreshold {
                onScrolledAwayChange?(true)
            }
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }
    }
}

// MARK: - Clean Barless Top-Right RAM Readout Pill (Uses Standard UI Font & Refreshes Live!)
public struct HeaderMemoryIndicatorView: View {
    @ObservedObject public var store: WorkstationStore
    public let tokens: MotifTokens
    public let isCompactWindow: Bool

    private var snap: UnifiedMemorySnapshot { store.memorySnapshot }
    private var typo: TypographyConfiguration { store.typography }

    public var body: some View {
        Button {
            store.isMemoryDetailPopoverPresented.toggle()
        } label: {
            Text(String(format: "%.1f GB free", snap.headroomGB))
                .font(typo.sans(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundColor(tokens.primaryText)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(tokens.canvasBackground)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(tokens.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help("Unified Memory: \(String(format: "%.1f GB used · %.1f GB free of %.0f GB", snap.usedGB, snap.headroomGB, snap.totalGB))")
        .popover(isPresented: $store.isMemoryDetailPopoverPresented, arrowEdge: .bottom) {
            MemoryDetailPopoverView(store: store, tokens: tokens)
        }
    }
}

public struct MemoryDetailPopoverView: View {
    @ObservedObject public var store: WorkstationStore
    public let tokens: MotifTokens

    private var snap: UnifiedMemorySnapshot { store.memorySnapshot }
    private var typo: TypographyConfiguration { store.typography }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("System Memory")
                    .font(typo.sans(size: 12.5, weight: .semibold))
                    .foregroundColor(tokens.primaryText)
                Spacer()
                Text(String(format: "%.2f GB free", snap.headroomGB))
                    .font(typo.sans(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(tokens.accentAction)
            }

            HairlineDivider(tokens: tokens)

            VStack(spacing: 6) {
                memoryRow("Free / Remaining RAM", String(format: "%.2f GB", snap.headroomGB))
                memoryRow("Total System RAM Used", String(format: "%.2f / %.0f GB", snap.usedGB, snap.totalGB))
                if let model = store.activeModelDescriptor {
                    memoryRow("Target Model Size (\(model.shortDisplayName))", model.formattedSize)
                }
                memoryRow("Ollama Resident in RAM", String(format: "%.2f GB", snap.weightsGB))
                memoryRow("RAM Delta Since Load", String(format: "%@%.2f GB", snap.activeRAMDeltaGB >= 0 ? "+" : "", snap.activeRAMDeltaGB))
                memoryRow("Estimated KV Cache (\(store.supervisor.kvCacheTypeEnv.rawValue.uppercased()))", String(format: "%.2f GB", snap.kvCacheGB))
                memoryRow("Metal Recommended Ceiling", String(format: "%.1f GB", snap.metalMaxGB))
            }

            if let session = store.activeSession {
                HairlineDivider(tokens: tokens)

                let usedTok = session.estimatedActiveTokens
                let maxTok = max(1, session.parameters.numCtx)
                let pct = Int(min(100.0, (Double(usedTok) / Double(maxTok)) * 100.0))
                let thread = session.activeBranchThread

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Active Chat Context")
                            .font(typo.sans(size: 11.5, weight: .semibold))
                            .foregroundColor(tokens.primaryText)
                        Spacer()
                        Text("\(usedTok) / \(maxTok) tok (\(pct)%)")
                            .font(typo.sans(size: 11, weight: .medium).monospacedDigit())
                            .foregroundColor(pct >= 80 ? Color.orange : tokens.secondaryText)
                    }

                    HStack(spacing: 8) {
                        Button {
                            store.trimOldestTurnInActiveSession()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "scissors")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Trim Oldest Turn")
                                    .font(typo.sans(size: 11, weight: .medium))
                            }
                            .foregroundColor(thread.isEmpty ? tokens.mutedText : tokens.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(tokens.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(tokens.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(thread.isEmpty)
                        .help("Excise the oldest question & reply from this chat to free KV cache memory")

                        Button {
                            store.isMemoryDetailPopoverPresented = false
                            store.summarizeContextIntoNewBranch()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.branch")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("Summarize Chat")
                                    .font(typo.sans(size: 11, weight: .medium))
                            }
                            .foregroundColor(thread.isEmpty ? tokens.mutedText : tokens.primaryText)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity)
                            .background(tokens.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(tokens.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(thread.isEmpty)
                        .help("Compress conversation history into a fresh summary branch to reclaim KV cache RAM")
                    }
                }
            }

            if let loaded = store.availableModels.first(where: { $0.residency == .activeInUnifiedRAM }) {
                HairlineDivider(tokens: tokens)
                HStack {
                    Button("Reset KV Cache Buffer") {
                        store.clearActiveKVCacheInRAM()
                    }
                    .font(typo.sans(size: 11, weight: .medium))
                    .foregroundColor(tokens.secondaryText)
                    .buttonStyle(.plain)
                    .help("Clears any cached conversation tokens from Ollama's KV buffer while keeping the model weights in RAM")

                    Spacer()

                    Button("Unload \(loaded.shortDisplayName)") {
                        Task { await store.unloadModelFromMemory(loaded) }
                    }
                    .font(typo.sans(size: 11, weight: .semibold))
                    .foregroundColor(tokens.accentAction)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 345)
        .background(tokens.canvasBackground)
        .onAppear {
            Task {
                await store.pollOllamaRunningProcesses()
                store.recalculateHardwareTelemetry()
            }
        }
    }

    private func memoryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(typo.sans(size: 11.5))
                .foregroundColor(tokens.secondaryText)
            Spacer()
            Text(value)
                .font(typo.sans(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundColor(tokens.primaryText)
        }
    }
}

// MARK: - Self-Contrasting "Jump to Latest" Circle Button
public struct HighContrastJumpToLatestButton: View {
    public let tokens: MotifTokens
    public let action: () -> Void
    @State private var isHovered: Bool = false

    private var buttonSurfaceColor: Color {
        if tokens.theme == .alabasterStudio && !tokens.hasCustomAccent {
            return Color(red: 0.239, green: 0.259, blue: 0.302).opacity(isHovered ? 0.96 : 0.88)
        }
        return tokens.accentAction.opacity(isHovered ? 0.98 : 0.92)
    }

    private var arrowForegroundColor: Color {
        if tokens.theme == .alabasterStudio && !tokens.hasCustomAccent {
            return Color.white
        }
        return tokens.accentForeground
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(buttonSurfaceColor)
                    .frame(width: 34, height: 34)

                Image(systemName: "arrow.down")
                    .font(.system(size: 12.0, weight: .bold))
                    .foregroundColor(arrowForegroundColor)
            }
            .overlay(
                Circle()
                    .strokeBorder(tokens.strongBorder.opacity(0.45), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(tokens.isEffectivelyDark ? 0.35 : 0.14),
                radius: 6,
                y: 2
            )
            .scaleEffect(isHovered ? 1.06 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .help("Scroll to bottom")
    }
}

// MARK: - LaTeX, Math & Spaced-Markdown Symbol Normalizer + Full H1-H6 Markdown Renderer
public enum LaTeXAndSymbolNormalizer {
    public static func normalize(_ input: String) -> String {
        var s = input

        // Repair spaced ** bold ** markers (e.g. `** text **` -> `**text**`) that CommonMark otherwise leaves as raw asterisks
        if s.contains("**") {
            if let spacedBold = try? NSRegularExpression(pattern: "\\*\\*\\s+([^\\*\\n]+?)\\s+\\*\\*") {
                s = spacedBold.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "**$1**")
            }
        }

        guard s.contains("$") || s.contains("\\") else { return s }

        s = s.replacingOccurrences(of: "$$", with: "")
        s = s.replacingOccurrences(of: "\\[", with: "")
        s = s.replacingOccurrences(of: "\\]", with: "")
        s = s.replacingOccurrences(of: "\\(", with: "")
        s = s.replacingOccurrences(of: "\\)", with: "")

        let wrappers = ["\\\\textbf\\{([^\\}]*)\\}": "**$1**",
                        "\\\\textit\\{([^\\}]*)\\}": "*$1*",
                        "\\\\text\\{([^\\}]*)\\}": "$1",
                        "\\\\mathrm\\{([^\\}]*)\\}": "$1",
                        "\\\\mathbf\\{([^\\}]*)\\}": "**$1**",
                        "\\\\sqrt\\{([^\\}]*)\\}": "√($1)",
                        "\\\\frac\\{([^\\}]*)\\}\\{([^\\}]*)\\}": "($1/$2)"]
        for (pattern, template) in wrappers {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
            }
        }

        if let inlineMathRegex = try? NSRegularExpression(pattern: "\\$(?!\\s)([^$\\n]+?)(?<!\\s)\\$") {
            s = inlineMathRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }

        let replacements: [(String, String)] = [
            ("\\times", "×"), ("\\div", "÷"), ("\\pm", "±"), ("\\mp", "∓"),
            ("\\cdot", "·"), ("\\approx", "≈"), ("\\neq", "≠"), ("\\ne", "≠"),
            ("\\leq", "≤"), ("\\le", "≤"), ("\\geq", "≥"), ("\\ge", "≥"),
            ("\\rightarrow", "→"), ("\\to", "→"), ("\\leftarrow", "←"),
            ("\\Rightarrow", "⇒"), ("\\Leftarrow", "⇐"), ("\\leftrightarrow", "↔"),
            ("\\infty", "∞"), ("\\partial", "∂"), ("\\nabla", "∇"),
            ("\\forall", "∀"), ("\\exists", "∃"), ("\\in", "∈"), ("\\notin", "∉"),
            ("\\subset", "⊂"), ("\\subseteq", "⊆"), ("\\cup", "∪"), ("\\cap", "∩"),
            ("\\sum", "∑"), ("\\prod", "∏"), ("\\int", "∫"),
            ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"),
            ("\\epsilon", "ε"), ("\\zeta", "ζ"), ("\\eta", "η"), ("\\theta", "θ"),
            ("\\lambda", "λ"), ("\\mu", "μ"), ("\\pi", "π"), ("\\rho", "ρ"),
            ("\\sigma", "σ"), ("\\tau", "τ"), ("\\phi", "φ"), ("\\chi", "χ"),
            ("\\psi", "ψ"), ("\\omega", "ω"), ("\\Delta", "Δ"), ("\\Sigma", "Σ"),
            ("\\Omega", "Ω"), ("\\Gamma", "Γ"), ("\\Lambda", "Λ"), ("\\Theta", "Θ"),
            ("^2", "²"), ("^3", "³"), ("^n", "ⁿ"), ("_0", "₀"), ("_1", "₁"), ("_2", "₂"), ("_i", "ᵢ"), ("_n", "ₙ")
        ]
        for (latex, unicode) in replacements {
            s = s.replacingOccurrences(of: latex, with: unicode)
        }
        return s
    }
}

public struct StreamSafeMarkdownView: View {
    public let rawMarkdown: String
    public let isStreaming: Bool
    public let effectiveFontSize: CGFloat
    public let tokens: MotifTokens
    public let typo: TypographyConfiguration
    public var useMonospaceBody: Bool = false
    public var overrideTextColor: Color? = nil
    public let onOpenCodeInInspector: (String, String) -> Void

    public var body: some View {
        let cleaned = LaTeXAndSymbolNormalizer.normalize(sanitizeIncompleteStreamMarkers(rawMarkdown, isStreaming: isStreaming))
        let blocks = parseBlocks(from: cleaned)
        VStack(alignment: .leading, spacing: useMonospaceBody ? 8 : 12) {
            ForEach(blocks.indices, id: \.self) { idx in
                let block = blocks[idx]
                switch block.kind {
                case .codeBlock(let lang, let code):
                    MotifCodeBlockView(
                        language: lang,
                        code: code,
                        tokens: tokens,
                        typo: typo,
                        onOpenInArtifactPane: { onOpenCodeInInspector(lang, code) }
                    )
                    .padding(.vertical, 2)

                case .heading(let level, let text):
                    let size: CGFloat = {
                        switch level {
                        case 1: return effectiveFontSize + 3.6
                        case 2: return effectiveFontSize + 2.0
                        case 3: return effectiveFontSize + 0.8
                        case 4: return effectiveFontSize + 0.2
                        default: return effectiveFontSize
                        }
                    }()
                    renderInlineRichText(text, baseFontSize: size, isHeading: true)
                        .padding(.top, level <= 3 ? 3 : 1)

                case .bulletItem(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("•")
                            .font(typo.mono(size: max(11, effectiveFontSize - 1), weight: .medium))
                            .foregroundColor(overrideTextColor ?? tokens.secondaryText)
                            .frame(width: 12, alignment: .trailing)
                        renderInlineRichText(text, baseFontSize: effectiveFontSize, isHeading: false)
                    }

                case .numberedItem(let numberStr, let text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(numberStr)
                            .font(typo.sans(size: max(11, effectiveFontSize - 0.8), weight: .semibold).monospacedDigit())
                            .foregroundColor(overrideTextColor ?? tokens.secondaryText)
                            .frame(width: 22, alignment: .trailing)
                        renderInlineRichText(text, baseFontSize: effectiveFontSize, isHeading: false)
                    }

                case .blockquote(let text):
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(tokens.strongBorder)
                            .frame(width: 2)
                        renderInlineRichText(text, baseFontSize: effectiveFontSize, isHeading: false)
                            .foregroundColor(overrideTextColor ?? tokens.secondaryText)
                    }
                    .padding(.vertical, 2)

                case .horizontalRule:
                    HairlineDivider(tokens: tokens)
                        .padding(.vertical, 4)

                case .paragraph(let text):
                    renderInlineRichText(text, baseFontSize: effectiveFontSize, isHeading: false)
                }
            }
        }
    }

    private enum MarkdownBlockKind {
        case paragraph(String)
        case heading(Int, String)
        case bulletItem(String)
        case numberedItem(String, String)
        case blockquote(String)
        case horizontalRule
        case codeBlock(String, String)
    }

    private struct MarkdownBlock {
        let kind: MarkdownBlockKind
    }

    private func sanitizeIncompleteStreamMarkers(_ input: String, isStreaming: Bool) -> String {
        guard isStreaming else { return input }
        var result = input
        let boldCount = result.components(separatedBy: "**").count - 1
        if boldCount % 2 != 0, let lastRange = result.range(of: "**", options: .backwards) {
            result.removeSubrange(lastRange)
        }
        let fenceCount = result.components(separatedBy: "```").count - 1
        if fenceCount % 2 == 0 {
            let inlineBackticks = result.components(separatedBy: "`").count - 1
            if inlineBackticks % 2 != 0, let lastTick = result.range(of: "`", options: .backwards) {
                result.removeSubrange(lastTick)
            }
        }
        return result
    }

    /// Parses all Markdown heading levels (# through ######, i.e. 1 to 6 hashtags) and strips trailing hashtags
    private func matchHeading(_ trimmed: String) -> (level: Int, text: String)? {
        guard trimmed.hasPrefix("#") else { return nil }
        var count = 0
        for ch in trimmed {
            if ch == "#" { count += 1 }
            else { break }
        }
        guard count >= 1 && count <= 6 else { return nil }
        let remainder = String(trimmed.dropFirst(count))
        guard remainder.isEmpty || remainder.first == " " || remainder.first == "\t" else { return nil }
        var cleanedText = remainder.trimmingCharacters(in: .whitespaces)
        while cleanedText.hasSuffix("#") {
            cleanedText.removeLast()
        }
        cleanedText = cleanedText.trimmingCharacters(in: .whitespaces)
        guard !cleanedText.isEmpty else { return nil }
        return (count, cleanedText)
    }

    private func parseBlocks(from raw: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let segments = raw.components(separatedBy: "```")

        for (segIdx, segment) in segments.enumerated() {
            if segIdx % 2 == 1 {
                var lines = segment.components(separatedBy: .newlines)
                let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !lines.isEmpty { lines.removeFirst() }
                let codeBody = lines.joined(separator: "\n")
                blocks.append(MarkdownBlock(kind: .codeBlock(firstLine, codeBody)))
            } else {
                let lines = segment.components(separatedBy: .newlines)
                var currentParagraph: [String] = []

                func flushParagraph() {
                    let joined = currentParagraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !joined.isEmpty {
                        blocks.append(MarkdownBlock(kind: .paragraph(joined)))
                    }
                    currentParagraph.removeAll()
                }

                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        flushParagraph()
                    } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                        flushParagraph()
                        blocks.append(MarkdownBlock(kind: .horizontalRule))
                    } else if let headingMatch = matchHeading(trimmed) {
                        flushParagraph()
                        blocks.append(MarkdownBlock(kind: .heading(headingMatch.level, headingMatch.text)))
                    } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") || trimmed.hasPrefix("+ ") {
                        flushParagraph()
                        blocks.append(MarkdownBlock(kind: .bulletItem(String(trimmed.dropFirst(2)))))
                    } else if trimmed.hasPrefix("> ") || trimmed == ">" {
                        flushParagraph()
                        let quoteBody = trimmed.count > 2 ? String(trimmed.dropFirst(2)) : ""
                        if !quoteBody.isEmpty {
                            blocks.append(MarkdownBlock(kind: .blockquote(quoteBody)))
                        }
                    } else if let numberedMatch = matchNumberedList(trimmed) {
                        flushParagraph()
                        blocks.append(MarkdownBlock(kind: .numberedItem(numberedMatch.number, numberedMatch.rest)))
                    } else {
                        currentParagraph.append(line)
                    }
                }
                flushParagraph()
            }
        }
        return blocks
    }

    private func matchNumberedList(_ line: String) -> (number: String, rest: String)? {
        let dotIdx = line.firstIndex(of: ".") ?? line.firstIndex(of: ")")
        guard let sepIdx = dotIdx else { return nil }
        let prefix = String(line[..<sepIdx])
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isNumber }) else { return nil }
        let afterSep = line.index(after: sepIdx)
        guard afterSep < line.endIndex, line[afterSep] == " " else { return nil }
        let body = String(line[line.index(after: afterSep)...])
        return ("\(prefix).", body)
    }

    @ViewBuilder
    private func renderInlineRichText(_ text: String, baseFontSize: CGFloat, isHeading: Bool) -> some View {
        Text(buildAttributedInline(text, baseFontSize: baseFontSize, isHeading: isHeading))
            .lineSpacing(CGFloat(baseFontSize * (useMonospaceBody ? 0.34 : (typo.lineSpacingMultiplier - 1.0))))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buildAttributedInline(_ raw: String, baseFontSize: CGFloat, isHeading: Bool) -> AttributedString {
        var output = AttributedString()
        let parts = raw.components(separatedBy: "`")
        let targetColor = overrideTextColor ?? tokens.primaryText

        for (idx, part) in parts.enumerated() {
            if idx % 2 == 1 {
                var codeAttr = AttributedString(" \(part) ")
                codeAttr.font = .system(size: max(11.0, baseFontSize - 1.2), weight: .medium, design: .monospaced)
                codeAttr.foregroundColor = targetColor
                codeAttr.backgroundColor = tokens.elevatedSurface
                output.append(codeAttr)
            } else {
                var mdAttr = (try? AttributedString(markdown: part, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(part)
                mdAttr.foregroundColor = targetColor

                for run in mdAttr.runs {
                    let range = run.range
                    let isBold = run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true || isHeading
                    let isItalic = run.inlinePresentationIntent?.contains(.emphasized) == true
                    if useMonospaceBody {
                        var f = Font.system(size: baseFontSize, weight: isBold ? .bold : .regular, design: .monospaced)
                        if isItalic { f = f.italic() }
                        mdAttr[range].font = f
                    } else {
                        var f = typo.sans(size: baseFontSize, weight: isBold ? .semibold : .regular)
                        if isItalic { f = f.italic() }
                        mdAttr[range].font = f
                    }
                }
                output.append(mdAttr)
            }
        }
        return output
    }
}

public struct MotifCodeBlockView: View {
    public let language: String
    public let code: String
    public let tokens: MotifTokens
    public let typo: TypographyConfiguration
    public let onOpenInArtifactPane: () -> Void

    @State private var isCopied: Bool = false
    @State private var softWrapEnabled: Bool = false

    private var lines: [String] {
        code.trimmingCharacters(in: .newlines).components(separatedBy: .newlines)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(language.isEmpty ? "CODE" : language.uppercased())
                    .font(typo.mono(size: 10.5, weight: .semibold))
                    .foregroundColor(tokens.secondaryText)

                Text("\(lines.count) \(lines.count == 1 ? "line" : "lines")")
                    .font(typo.sans(size: 10.5, weight: .regular).monospacedDigit())
                    .foregroundColor(tokens.mutedText)

                Spacer()

                Button {
                    softWrapEnabled.toggle()
                } label: {
                    Text(softWrapEnabled ? "Unwrap" : "Wrap")
                        .font(typo.sans(size: 11, weight: .medium))
                        .foregroundColor(tokens.secondaryText)
                }
                .buttonStyle(.plain)

                Button(action: onOpenInArtifactPane) {
                    Text("Inspector")
                        .font(typo.sans(size: 11, weight: .medium))
                        .foregroundColor(tokens.secondaryText)
                }
                .buttonStyle(.plain)

                Button(action: copyCodeToClipboard) {
                    ZStack {
                        Text("Copied").font(typo.sans(size: 11, weight: .medium)).opacity(0)
                        Text(isCopied ? "Copied" : "Copy")
                            .font(typo.sans(size: 11, weight: .medium))
                            .foregroundColor(isCopied ? tokens.accentForeground : tokens.primaryText)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isCopied ? tokens.accentAction : tokens.canvasBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(tokens.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tokens.elevatedSurface)

            HairlineDivider(tokens: tokens)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(lines.indices, id: \.self) { idx in
                        Text("\(idx + 1)")
                            .font(typo.mono(size: 12))
                            .foregroundColor(tokens.mutedText)
                    }
                }
                .frame(minWidth: 36, alignment: .trailing)
                .padding(.vertical, 12)
                .padding(.trailing, 10)
                .padding(.leading, 8)
                .background(tokens.sidebarBackground)

                HairlineDivider(axis: .vertical, tokens: tokens)

                if softWrapEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(lines.indices, id: \.self) { idx in
                            Text(lines[idx].isEmpty ? " " : lines[idx])
                                .font(typo.mono(size: 12.5))
                                .foregroundColor(tokens.primaryText)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(lines.indices, id: \.self) { idx in
                                Text(lines[idx].isEmpty ? " " : lines[idx])
                                    .font(typo.mono(size: 12.5))
                                    .foregroundColor(tokens.primaryText)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 12)
                        .padding(.leading, 16)
                        .padding(.trailing, 24)
                    }
                }
            }
            .background(tokens.canvasBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(tokens.hairline, lineWidth: 1)
        )
    }

    private func copyCodeToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation(.easeInOut(duration: 0.14)) { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.14)) { isCopied = false }
        }
    }
}

// MARK: - Theme-Matched Multi-Line Text Editor (`MotifStyledTextEditor`)
public struct MotifStyledTextEditor: NSViewRepresentable {
    @Binding public var text: String
    public let font: NSFont
    public let tokens: MotifTokens

    public init(text: Binding<String>, font: NSFont, tokens: MotifTokens) {
        self._text = text
        self.font = font
        self.tokens = tokens
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.appearance = NSAppearance(named: tokens.isEffectivelyDark ? .darkAqua : .aqua)

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = font
        textView.textColor = NSColor(tokens.primaryText)
        textView.insertionPointColor = NSColor(tokens.primaryText)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        scrollView.scrollerStyle = .overlay
        scrollView.appearance = NSAppearance(named: tokens.isEffectivelyDark ? .darkAqua : .aqua)
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text && !textView.hasMarkedText() {
            textView.string = text
        }
        if textView.font != font {
            textView.font = font
        }
        let targetColor = NSColor(tokens.primaryText)
        if textView.textColor != targetColor {
            textView.textColor = targetColor
            textView.insertionPointColor = targetColor
        }
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MotifStyledTextEditor
        init(_ parent: MotifStyledTextEditor) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if !tv.hasMarkedText() {
                parent.text = tv.string
            }
        }
    }
}

// MARK: - Zero-Flicker 3-Line Quantized NSTextView Bridge with Native Blinking Caret
public struct IMESafeComposerTextView: NSViewRepresentable {
    @Binding public var text: String
    @Binding public var isFocused: Bool
    @Binding public var compactHeight: CGFloat
    @Binding public var lineCount: Int
    public let placeholder: String
    public let tokens: MotifTokens
    public let typo: TypographyConfiguration
    public let fontSize: CGFloat
    public let isSlashMenuVisible: Bool
    public let onSend: () -> Void
    public let onSlashMoveUp: () -> Void
    public let onSlashMoveDown: () -> Void
    public let onSlashConfirm: () -> Bool
    public let onSlashDismiss: () -> Void
    public let onLargePaste: (String) -> Void

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = ComposerNSTextView()
        textView.delegate = context.coordinator
        textView.coordinator = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.font = typo.nsFont(size: fontSize)
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 4

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
        let textChangedExternally = (textView.string != text && !textView.hasMarkedText())
        if textChangedExternally {
            textView.string = text
            textView.needsDisplay = true
        }
        let targetFont = typo.nsFont(size: fontSize)
        if textView.font != targetFont {
            textView.font = targetFont
        }
        let targetTextColor = NSColor(tokens.primaryText)
        if textView.textColor != targetTextColor {
            textView.textColor = targetTextColor
            textView.insertionPointColor = targetTextColor
        }
        let targetPlaceholderColor = NSColor(tokens.mutedText)
        if textView.placeholderString != placeholder || textView.placeholderColor != targetPlaceholderColor {
            textView.placeholderString = placeholder
            textView.placeholderColor = targetPlaceholderColor
            if textView.string.isEmpty {
                textView.needsDisplay = true
            }
        }

        if textChangedExternally {
            context.coordinator.recalculateQuantizedMetrics(for: textView)
        }
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IMESafeComposerTextView
        private var lastMeasuredWidth: CGFloat = 0

        init(_ parent: IMESafeComposerTextView) { self.parent = parent }

        public func textDidBeginEditing(_ notification: Notification) { parent.isFocused = true }
        public func textDidEndEditing(_ notification: Notification) { parent.isFocused = false }

        public func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            if !tv.hasMarkedText() {
                parent.text = tv.string
            }
            recalculateQuantizedMetrics(for: tv)
        }

        public func handleWidthChangeIfNeeded(for textView: NSTextView) {
            let currentW = textView.bounds.width
            guard abs(currentW - lastMeasuredWidth) > 6.0 else { return }
            lastMeasuredWidth = currentW
            recalculateQuantizedMetrics(for: textView)
        }

        public func recalculateQuantizedMetrics(for textView: NSTextView) {
            if textView.string.isEmpty {
                if parent.lineCount != 1 || parent.compactHeight != 28.0 {
                    DispatchQueue.main.async {
                        self.parent.lineCount = 1
                        self.parent.compactHeight = 28.0
                    }
                }
                return
            }

            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let singleLineH = max(18.0, (textView.font?.ascender ?? 13.0) - (textView.font?.descender ?? -4.0) + (textView.font?.leading ?? 2.0))
            let estimatedLines = max(1, Int(round(usedHeight / singleLineH)))

            let targetCompactHeight: CGFloat
            if estimatedLines <= 1 {
                targetCompactHeight = 28.0
            } else if estimatedLines == 2 {
                targetCompactHeight = 46.0
            } else {
                targetCompactHeight = 64.0
            }

            if parent.lineCount != estimatedLines || abs(parent.compactHeight - targetCompactHeight) > 0.5 {
                DispatchQueue.main.async {
                    self.parent.lineCount = estimatedLines
                    self.parent.compactHeight = targetCompactHeight
                }
            }
        }

        public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if textView.hasMarkedText() { return false }

            if parent.isSlashMenuVisible {
                if commandSelector == #selector(NSResponder.moveUp(_:)) {
                    parent.onSlashMoveUp()
                    return true
                }
                if commandSelector == #selector(NSResponder.moveDown(_:)) {
                    parent.onSlashMoveDown()
                    return true
                }
                if commandSelector == #selector(NSResponder.insertTab(_:)) {
                    let ok = parent.onSlashConfirm()
                    recalculateQuantizedMetrics(for: textView)
                    return ok
                }
                if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                    parent.onSlashDismiss()
                    return true
                }
            }

            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    recalculateQuantizedMetrics(for: textView)
                    return true
                } else {
                    if parent.isSlashMenuVisible && parent.onSlashConfirm() {
                        recalculateQuantizedMetrics(for: textView)
                        return true
                    }
                    parent.onSend()
                    return true
                }
            }
            return false
        }
    }
}

public final class ComposerNSTextView: NSTextView {
    weak var coordinator: IMESafeComposerTextView.Coordinator?
    var placeholderString: String = ""
    var placeholderColor: NSColor = .secondaryLabelColor

    public override var acceptsFirstResponder: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
        updateInsertionPointStateAndRestartTimer(true)
    }

    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            updateInsertionPointStateAndRestartTimer(true)
        }
        return ok
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        coordinator?.handleWidthChangeIfNeeded(for: self)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty && !hasMarkedText() {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? NSFont.systemFont(ofSize: 14),
                .foregroundColor: placeholderColor
            ]
            let rect = NSRect(x: 6, y: 4, width: bounds.width - 12, height: bounds.height - 6)
            (placeholderString as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    public override func paste(_ sender: Any?) {
        if let pasted = NSPasteboard.general.string(forType: .string),
           (pasted.count > 2400 || pasted.components(separatedBy: .newlines).count > 55) {
            coordinator?.parent.onLargePaste(pasted)
            return
        }
        super.pasteAsPlainText(sender)
        coordinator?.recalculateQuantizedMetrics(for: self)
    }
}
EOF
