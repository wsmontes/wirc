import SwiftUI

// MARK: - Channel Tab

struct ChannelTab: View {
    let label: String
    let isActive: Bool
    var badge: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(isActive ? DesignSystem.Fonts.data(12, weight: .bold) : DesignSystem.Fonts.data(12))
                if let b = badge, b > 0 {
                    Text("\(b)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
            }
            .foregroundStyle(isActive ? .white : DesignSystem.Colors.ink)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, 6)
            .background(isActive ? DesignSystem.Colors.signal : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.Radius.chip))
        }
        .buttonStyle(.plain)
    }
}
