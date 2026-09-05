import SwiftUI

extension View {
    /// 자간을 넓힌 소문자 라벨. `가 족 총 자 산` 처럼 쓴다.
    func eyebrowStyle() -> some View {
        self.font(.system(size: 9, weight: .medium))
            .tracking(2)
            .foregroundStyle(Color.muted)
    }
}

extension Font {
    /// 금액용 서체. **숫자만** 고정폭으로 만든다.
    ///
    /// `design: .monospaced` 를 쓰면 한글(억·만·원)과 공백까지 고정폭이 되어
    /// "3억   273만원" 처럼 사이가 벌어진다. `monospacedDigit()` 은 자릿수만
    /// 고정하고 나머지는 본문 서체 그대로 둔다 — 표에서 자릿수가 흔들리지 않으면서
    /// 한글은 자연스럽게 붙는다.
    static func figure(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}
