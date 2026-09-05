import SwiftUI

/// 기존 A4 1페이지 계획서 PDF에서 그대로 뽑은 색.
/// 화면은 그 문서의 연장이지 새 브랜드가 아니다 (docs/reference/one-pager-analysis.md).
extension Color {
    static let ink = Color(hex: 0x0B1017)      // 제목 · 큰 숫자
    static let bodyText = Color(hex: 0x33414F) // 본문
    static let muted = Color(hex: 0x68747F)    // 라벨 · 보조
    static let faint = Color(hex: 0x98A3AC)    // 희미함
    static let rule = Color(hex: 0xE3E8EB)     // 괘선
    static let ruleStrong = Color(hex: 0xC3CCD3)
    static let surface = Color(hex: 0xF4F7F8)  // 면 · 강조 배경

    static let dad = Color(hex: 0x1D5E7F)
    static let mom = Color(hex: 0x8E4650)
    static let son = Color(hex: 0x2A7A66)
    static let daughter = Color(hex: 0x7A5A2E)

    static let gain = Color(hex: 0x2A7A66)
    static let loss = Color(hex: 0x8E4650)

    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension Color {
    /// 구성원 색. 1페이지의 아빠·엄마·아들·딸 순서 그대로.
    static let memberPalette: [Color] = [.dad, .mom, .son, .daughter]

    static func member(_ index: Int) -> Color {
        memberPalette[((index % memberPalette.count) + memberPalette.count) % memberPalette.count]
    }
}
