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
    /// 모든 금액은 고정폭 tabular로. 자릿수가 흔들리면 표가 아니라 목록이 된다.
    static func figure(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
