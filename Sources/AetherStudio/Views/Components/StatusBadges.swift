import SwiftUI

public struct PillBadge: View {
    public let text: String
    public let palette: AetherPalette
    public var isAccent: Bool = false
    public var dotColor: Color? = nil

    public init(_ text: String, palette: AetherPalette, isAccent: Bool = false, dotColor: Color? = nil) {
        self.text = text
        self.palette = palette
        self.isAccent = isAccent
        self.dotColor = dotColor
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let dot = dotColor {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(isAccent ? palette.accent : palette.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AetherMetrics.pillCornerRadius, style: .continuous)
                .fill(isAccent ? palette.accentSoft : palette.subtleSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AetherMetrics.pillCornerRadius, style: .continuous)
                .stroke(isAccent ? palette.accent.opacity(0.35) : palette.hairlineBorder, lineWidth: 1)
        )
    }
}
