import Foundation
import Testing
@testable import Core

/// 증권사 캡처 읽기 규칙 (docs/25 J3). 화면 조각은 손으로 만든 가상의 것 — 금액은 지어낸 숫자.
@Suite("CaptureParser — 캡처에서 종목 · 평가금액 고르기")
struct CaptureParserTests {

    private func line(_ text: String, _ x: Double, _ top: Double, h: Double = 0.016) -> CaptureParser.Line {
        .init(text: text, x: x, top: top, width: 0.4, height: h)
    }

    @Test("부호 · % · 주 · 매입 · 원금 · 현재가 는 평가금액 후보가 아니다")
    func amountFilters() {
        #expect(CaptureParser.amounts(in: "2,080,008원") == [2_080_008])
        #expect(CaptureParser.amounts(in: "-143,894 (-6.47%)").isEmpty)
        #expect(CaptureParser.amounts(in: "+1,205,000").isEmpty)
        #expect(CaptureParser.amounts(in: "1,913주 · 매입 2,223,902").isEmpty)
        #expect(CaptureParser.amounts(in: "투자원금 3,590,157원").isEmpty)
        #expect(CaptureParser.amounts(in: "현재가 52,300").isEmpty)
        #expect(CaptureParser.amounts(in: "12,345,678").contains(12_345_678))
    }

    // 목록형: 이름 | 평가금액(큰 글씨), 아래 수량 · 매입 | 손익(%)
    // 총액 3,000,000 + 1,500,000 = 4,500,000 (손으로 셈)
    @Test("목록형 — 큰 글씨 금액을 고르고 합이 총액과 맞는다")
    func listLayout() {
        let lines = [
            line("종합매매 · 아빠 · 123-45-****", 0.05, 0.07),
            line("4,500,000원", 0.05, 0.10, h: 0.032),
            line("총 평가금액 · 평가손익 +12,000", 0.05, 0.14),
            line("ALPHA 미국지수", 0.05, 0.22, h: 0.018),
            line("3,000,000원", 0.70, 0.22, h: 0.018),
            line("120주 · 매입 2,900,000", 0.05, 0.25, h: 0.014),
            line("+100,000 (+3.45%)", 0.65, 0.25, h: 0.014),
            line("가나전자", 0.05, 0.30, h: 0.018),
            line("1,500,000원", 0.72, 0.30, h: 0.018),
            line("30주 · 매입 1,588,000", 0.05, 0.33, h: 0.014),
            line("-88,000 (-5.54%)", 0.66, 0.33, h: 0.014),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.totalMinor == 4_500_000)
        #expect(result.accountLine == "종합매매 · 아빠 · 123-45-****")
        #expect(result.items.map(\.name) == ["ALPHA 미국지수", "가나전자"])
        #expect(result.items.map(\.valueMinor) == [3_000_000, 1_500_000])
        #expect(result.isBalanced == true)
    }

    // 카드형: 매입금액이 평가금액보다 클 때(손실) — 이름표 `평가금액` 줄을 골라야 한다
    @Test("카드형 — 이름표 평가금액 줄을 고른다 (매입금액이 더 커도)")
    func cardLayout() {
        let lines = [
            line("연금저축 · 엄마 · 456-78-****", 0.05, 0.07),
            line("900,000원", 0.05, 0.10, h: 0.032),
            line("BETA 채권", 0.08, 0.22, h: 0.017),
            line("평가금액", 0.08, 0.25, h: 0.015),
            line("900,000원", 0.75, 0.25, h: 0.015),
            line("매입금액", 0.08, 0.27, h: 0.015),
            line("1,000,000원", 0.73, 0.27, h: 0.015),
            line("수익률", 0.08, 0.29, h: 0.015),
            line("-10.00%", 0.80, 0.29, h: 0.015),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.items.map(\.valueMinor) == [900_000])
        #expect(result.isBalanced == true)
    }

    @Test("한 종목을 잘못 읽으면 검산이 걸린다")
    func checksumCatches() {
        let lines = [
            line("6,000,000원", 0.05, 0.10, h: 0.032),
            line("감마 펀드", 0.05, 0.22, h: 0.018),
            line("5,000,000원", 0.70, 0.22, h: 0.018),
            line("델타 주식", 0.05, 0.30, h: 0.018),
            line("1,800,000원", 0.70, 0.30, h: 0.018),   // 정답은 1,000,000 이라고 치자 — 합 6,800,000 ≠ 6,000,000
        ]
        #expect(CaptureParser.parse(lines).isBalanced == false)
    }

    @Test("두 줄로 꺾인 펀드 이름은 하나로 붙인다")
    func wrappedName() {
        let lines = [
            line("2,000,000원", 0.05, 0.10, h: 0.032),
            line("하늘자산 TDF 2050 증권투자신탁(주식혼합)", 0.07, 0.22, h: 0.016),
            line("C-Pe", 0.07, 0.24, h: 0.016),
            line("평가금액", 0.07, 0.27, h: 0.015),
            line("2,000,000원", 0.70, 0.27, h: 0.020),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.items.map(\.name) == ["하늘자산 TDF 2050 증권투자신탁(주식혼합) C-Pe"])
        #expect(result.isBalanced == true)
    }

    @Test("이름 맞추기 — 잘린 이름은 앞부분, 나머지는 비슷한 것, 너무 다르면 짝 없음")
    func matching() {
        let names = ["ORBIT 미국30년국채액티브(H)", "ORBIT 200", "가나전자"]
        #expect(CaptureParser.match("ORBIT 미국30년국채액티브(…", among: names)?.index == 0)
        #expect(CaptureParser.match("ORBIT 200", among: names)?.index == 1)
        #expect(CaptureParser.match("가나 전자", among: names)?.index == 2)
        #expect(CaptureParser.match("전혀 다른 종목", among: names) == nil)
    }
}
