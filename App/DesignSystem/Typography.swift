import SwiftUI

extension View {
    /// 자간을 넓힌 소문자 라벨. `가 족 총 자 산` 처럼 쓴다.
    func eyebrowStyle() -> some View {
        self.font(.scaled(9, weight: .medium))
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
        scaled(size, weight: weight).monospacedDigit()
    }

    /// **글자 크기 설정을 따르는 본문 서체** (접근성, docs/10 §3-6 · 132번).
    ///
    /// 앱의 글자는 전부 `size:` 로 못 박혀 있어서 iOS 의 "텍스트 크기" 를 키워도
    /// 하나도 안 커졌다 — CI 가 접근성 크기로 찍은 장이 보통 장과 **바이트까지
    /// 같았다.** 여기 한 곳에서 `UIFontMetrics` 로 키운다. 설계 크기가 기준이고
    /// 사용자의 설정 배율을 곱한다.
    ///
    /// **xxxLarge 까지만 따른다.** 그 위 접근성 다섯 단계(최대 3.1배)는 표와
    /// 고정폭 칸이 못 받는다 — 애플도 xxxLarge 까지를 기본 요구로 본다. 따라가되
    /// 깨지지 않는 선에서 멈춘다.
    ///
    /// 1페이지(`OnePagerView`)는 종이라 **안 쓴다** — A4 한 장에 맞춘 크기다.
    static func scaled(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        // 사용자 배율로 키운 값과 xxxLarge 배율로 키운 값 중 작은 쪽 — 그래서
        // 접근성 단계에서도 xxxLarge 에 멈춘다. `UIApplication` 을 안 읽어
        // 액터 격리 문제가 없다.
        let user = UIFontMetrics.default.scaledValue(for: size)
        let cap = UIFontMetrics.default.scaledValue(for: size, compatibleWith: Self.capTraits)
        return .system(size: min(user, cap), weight: weight)
    }

    /// 글자에 맞춰 커져야 하는 **길이** (자리 높이 · 칸 폭). `scaled` 와 같은 배율, 같은 상한.
    static func scaledLength(_ length: CGFloat) -> CGFloat {
        let user = UIFontMetrics.default.scaledValue(for: length)
        let cap = UIFontMetrics.default.scaledValue(for: length, compatibleWith: capTraits)
        return min(user, cap)
    }

    private static let capTraits = UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge)
}
