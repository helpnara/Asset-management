import SwiftUI

/// **`대표` 띠지** — 가족 대표(구성원 순서의 맨 위 사람) 이름 옆에 붙는다 (168번).
///
/// 글자로 "가장" 이라고 적는 것보다 작은 띠지 하나가 한눈에 읽힌다 (사용자
/// 결정). 자산 탭의 구성원 머리글과 구성원 순서 화면이 같은 것을 쓴다 —
/// 두 곳의 모양이 다르면 같은 뜻인지 헷갈린다.
struct HeadBadge: View {
    var body: some View {
        // **한 줄로** (217번 D1). 자산 탭 머리글에서 자리가 모자라면 "대 / 표" 로 접혔다.
        Text("대표")
            .font(.scaled(11, weight: .semibold))
            .foregroundStyle(Color.brand)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Color.brandSoft, in: Capsule())
            .accessibilityLabel("가족 대표")
    }
}
