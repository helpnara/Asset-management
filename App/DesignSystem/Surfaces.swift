import SwiftUI

/// **카드와 단추의 모양 하나** (217번 · docs/23 원칙 2 · 6).
///
/// 현황판 · 점검 완료는 각진 종이(굵은 검은 줄 · 각진 흰 상자 · 각진 검은 단추)였고 자산 · 더보기 · 진단은
/// 둥근 iOS 목록이었다 — 한 앱에 모양이 둘이었다. 탭 화면은 이제 **바탕 `ground` 위 둥근 카드**
/// 하나로 간다. 각진 모양은 종이(1페이지 · 인쇄)에만 남는다.
enum Card {
    /// 카드 모서리 — 연속 곡률. 자산 탭의 둥근 목록과 눈으로 같게.
    static let radius: CGFloat = 18
    /// 화면 가장자리에서 카드까지.
    static let margin: CGFloat = 16
    /// 카드 안쪽 가로 여백.
    static let inset: CGFloat = 16
}

extension View {
    /// 둥근 카드 한 장. 안쪽 여백은 부르는 쪽이 정한다(카드마다 줄 높이가 다르다).
    func cardSurface(_ fill: Color = .raised) -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Card.radius, style: .continuous))
            .padding(.horizontal, Card.margin)
    }
}

/// **주 단추** — 채운 캡슐, 브랜드 색. 한 화면에 하나(원칙 6).
struct PrimaryCapsule: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaled(14, weight: .semibold))
            .foregroundStyle(Color.onBrand)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 18)
            .padding(.vertical, fullWidth ? 15 : 9)
            .background(Color.brand, in: Capsule())
            .opacity(configuration.isPressed ? 0.82 : 1)
            .contentShape(Capsule())
    }
}

/// **보조 단추** — 옅은 캡슐. 주 단추 옆이나, 이미 한 일을 다시 여는 자리.
struct SecondaryCapsule: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.scaled(13, weight: .semibold))
            .foregroundStyle(Color.brand)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.brandSoft, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
