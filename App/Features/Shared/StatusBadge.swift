import Core
import SwiftUI

/// 1페이지의 `동결` · `적립중` · `신규` 배지. 알약이 아니라 사각(반경 2)이다.
struct StatusBadge: View {
    let text: String
    var foreground: Color = .muted
    var background: Color = Color(hex: 0xEDF1F3)

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(background, in: RoundedRectangle(cornerRadius: 2))
    }
}

extension HoldingStatus {
    var badgeForeground: Color {
        switch self {
        case .accumulating: return .gain
        case .frozen, .closed: return .muted
        case .new: return .muted
        }
    }

    var badgeBackground: Color {
        switch self {
        case .accumulating: return Color(hex: 0xE8F1EE)
        case .frozen, .closed: return Color(hex: 0xEDF1F3)
        case .new: return Color(hex: 0xF4F7F8)
        }
    }
}
