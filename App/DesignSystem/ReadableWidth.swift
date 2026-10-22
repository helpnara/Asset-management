import SwiftUI

/// **넓은 화면에서 한 줄이 끝에서 끝까지 늘어나지 않게** (docs/08-feedback.md 161번).
///
/// 아이패드에서 `매월 적립` 은 화면 왼쪽 끝, `4,100,000` 은 오른쪽 끝에 붙는다.
/// 세로에서도 이미 그렇고 가로면 더 벌어진다 — 라벨과 값이 한눈에 안 들어온다.
/// **사이드바를 넣어도 이건 그대로다.** 메뉴를 빼도 남는 폭이 870pt 가 넘는다.
///
/// 그래서 내용의 폭 자체를 묶는다. 애플이 설정 앱에서 하는 것과 같다.
/// 좁은 화면(아이폰)에서는 아무 일도 하지 않는다 — 거기서는 이미 알맞다.
///
/// **왜 `maxWidth` 만 두고 `minWidth` 는 안 두나.** 화면이 그보다 좁으면
/// 그냥 화면을 다 쓰면 된다. 억지로 넓히면 아이폰에서 잘린다.
struct ReadableWidth: ViewModifier {
    /// 한 줄이 이보다 넓어지지 않는다. 700pt 는 아이패드 가로에서 양옆에
    /// 여백이 남으면서도 표가 답답하지 않은 폭이다.
    var maxWidth: CGFloat = 700
    /// **묶고 남은 양옆의 바탕** (205번). 예전에는 칠하지 않아 그 자리에 시스템 기본 바탕(흰색)이
    /// 비쳤다 — 자산 · 계획 · 더보기는 가운데만 회색 목록이고 양옆이 흰 띠였고, 현황판 · 시뮬레이션은
    /// 화면이 스스로 `ground` 를 깔아서 통일돼 보였다. 이제 여기서 한 번에 칠한다. 기본은 앱의 한 가지
    /// 바탕(`ground` = 목록 · 폼의 회색과 같은 색). 흰 바탕을 쓰는 점검 창 · 점검 완료는 `canvas` 를 건넨다.
    var background: Color = .ground

    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if sizeClass == .regular {
            // 안쪽 프레임이 폭을 묶고, 바깥 프레임이 남은 자리에서 가운데로 민다.
            content
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity)
                .background(background)
        } else {
            content
        }
    }
}

extension View {
    /// 넓은 화면에서 내용의 폭을 읽기 좋은 만큼으로 묶고, 양옆은 `background` 로 칠한다 (161 · 205번).
    func readableWidth(_ maxWidth: CGFloat = 700, background: Color = .ground) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth, background: background))
    }
}
