import SwiftUI
import UIKit

/// 기존 A4 1페이지 계획서 PDF에서 그대로 뽑은 색.
/// 화면은 그 문서의 연장이지 새 브랜드가 아니다 (docs/reference/one-pager-analysis.md).
///
/// **토큰은 전부 적응형이다.** 라이트 값은 1페이지에서 뽑은 원래 색이고,
/// 다크 값은 그 역할을 어두운 바탕에서 그대로 하도록 짝지은 것이다.
/// 이름을 바꾸지 않았으므로 색을 쓰는 231곳은 손댈 필요가 없다.
///
/// 색을 새로 쓸 때 **`Color.white` · `Color.black` 을 직접 쓰지 않는다.**
/// 다크 모드에서 그 화면만 흰 판으로 남는다 (docs/08-feedback.md 1번).
/// 바탕이 필요하면 `canvas`, 살짝 눌린 면이 필요하면 `surface` 를 쓴다.
extension Color {
    /// 화면 바탕. 예전에 `Color.white` 로 칠하던 자리.
    static let canvas = Color(light: 0xFFFFFF, dark: 0x0E1216)
    /// 바탕보다 한 겹 눌린 면. 카드가 얹히는 배경.
    static let surface = Color(light: 0xF4F7F8, dark: 0x171C21)
    /// 카드·시트처럼 `surface` 위에 떠 있는 면.
    static let raised = Color(light: 0xFFFFFF, dark: 0x1E242A)

    static let ink = Color(light: 0x0B1017, dark: 0xF2F5F7)      // 제목 · 큰 숫자
    static let bodyText = Color(light: 0x33414F, dark: 0xC5CED6) // 본문
    static let muted = Color(light: 0x68747F, dark: 0x939EA9)    // 라벨 · 보조
    static let faint = Color(light: 0x98A3AC, dark: 0x6F7A85)    // 희미함
    static let rule = Color(light: 0xE3E8EB, dark: 0x272E35)     // 괘선
    static let ruleStrong = Color(light: 0xC3CCD3, dark: 0x3C464F)

    /// `ink` 로 칠한 면 위에 얹는 글자색. 라이트에서는 흰 글자, 다크에서는 검은 글자다.
    /// `ink` 가 뒤집히므로 이것도 같이 뒤집혀야 읽힌다.
    static let onInk = Color(light: 0xFFFFFF, dark: 0x0E1216)

    static let dad = Color(light: 0x1D5E7F, dark: 0x6FB4D2)
    static let mom = Color(light: 0x8E4650, dark: 0xD98C97)
    static let son = Color(light: 0x2A7A66, dark: 0x63C6AC)
    static let daughter = Color(light: 0x7A5A2E, dark: 0xC9A469)

    static let gain = Color(light: 0x2A7A66, dark: 0x63C6AC)
    static let loss = Color(light: 0x8E4650, dark: 0xD98C97)

    // 배지·줄 강조에 쓰는 옅은 바탕. **라이트 값은 예전 그대로** 두고 다크 짝만 더했다.
    static let neutralSoft = Color(light: 0xEDF1F3, dark: 0x252C33)
    static let gainSoft = Color(light: 0xE8F1EE, dark: 0x172A25)
    static let lossSoft = Color(light: 0xF5E6E8, dark: 0x2F2125)
    static let alertSoft = Color(light: 0xFDF7F8, dark: 0x241A1D)
    /// 지금 입력 중인 줄. 주간 점검에서 어디를 적고 있는지 표시한다.
    static let rowActive = Color(light: 0xF7FAFB, dark: 0x1C2228)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// 시스템 설정을 따라 갈아 끼워지는 색.
    ///
    /// `UIColor(dynamicProvider:)` 를 쓰는 이유는 **에셋 카탈로그를 열지 않고도
    /// 두 값을 한자리에서 읽을 수 있기 때문**이다. 이 저장소는 맥 없이
    /// 원격에서 고치므로 색이 코드에 보이는 편이 낫다.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// 인쇄물용 고정 팔레트. **화면 설정과 무관하게 항상 흰 종이다.**
///
/// 1페이지는 PDF 로 나가 인쇄되거나 남에게 전달된다. 받는 사람의 기기가
/// 다크인지 라이트인지는 이 문서와 상관이 없다. 그래서 적응형 토큰을 쓰지 않고
/// 1페이지 원본의 색을 그대로 박아 둔다 (docs/08-feedback.md 1번 · 10번).
enum Paper {
    static let sheet = Color(hex: 0xFFFFFF)
    static let ink = Color(hex: 0x0B1017)
    static let bodyText = Color(hex: 0x33414F)
    static let muted = Color(hex: 0x68747F)
    static let faint = Color(hex: 0x98A3AC)
    static let rule = Color(hex: 0xE3E8EB)
}

extension Color {
    /// 구성원 색. 1페이지의 아빠·엄마·아들·딸 순서 그대로.
    static let memberPalette: [Color] = [.dad, .mom, .son, .daughter]

    static func member(_ index: Int) -> Color {
        memberPalette[((index % memberPalette.count) + memberPalette.count) % memberPalette.count]
    }
}
