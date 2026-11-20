import Foundation
import Testing
@testable import Core

/// 증권사 캡처 읽기 규칙 (docs/25 J3). 화면 조각은 손으로 만든 가상의 것 — 금액은 지어낸 숫자.
@Suite("CaptureParser — 캡처에서 종목 · 평가금액 고르기")
struct CaptureParserTests {

    private func line(_ text: String, _ x: Double, _ top: Double, h: Double = 0.016, w: Double = 0.4) -> CaptureParser.Line {
        .init(text: text, x: x, top: top, width: w, height: h)
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
        #expect(CaptureParser.amounts(in: "달러 환율 1,352.70 +0.4%").isEmpty)   // 소수
        #expect(CaptureParser.amounts(in: "담보 1,000,000").isEmpty)
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

    // 11-20 실제 화면(첫째)의 배치 — 2단 표. 숫자 · 이름 · 계좌는 지어낸 것.
    // 위에 메뉴 · 탭 · 계좌 줄 · 단추 줄, 이름표 | 값 요약표, 머리줄 두 단, 한 칸에 평가금액(위) · 매입금액(아래).
    // 평가금액 2,000,000 + 4,000,000 = 6,000,000 = 요약표 평가금액 (손으로 셈). 매입금액(3,000,000)이 평가금액보다
    // 큰 손실 종목 · 부호 없는 이익(1,500,000) · 쉼표 든 수량(1,250) 을 일부러 넣었다 — 큰 값 고르기로는 틀린다.
    @Test("2단 표 — 머리줄의 평가금액 열 · 위 단을 고르고, 메뉴 · 탭 · 단추는 종목이 아니다")
    func twoTierTable() {
        let lines = [
            line("‹ 내자산", 0.05, 0.07, h: 0.022, w: 0.2),
            line("자산", 0.10, 0.13, h: 0.02, w: 0.08), line("국내주식", 0.38, 0.13, h: 0.02, w: 0.15),
            line("해외주식", 0.72, 0.13, h: 0.02, w: 0.15),
            line("123-4567-8901-0 [종합_주식] 딸 일반주식", 0.05, 0.19, w: 0.6),
            line("전체", 0.03, 0.25, w: 0.06), line("담보", 0.37, 0.25, w: 0.06), line("체결", 0.48, 0.25, w: 0.06),
            line("매입금액", 0.03, 0.30, w: 0.12), line("5,500,000", 0.26, 0.30, w: 0.2),
            line("평가손익", 0.52, 0.30, w: 0.12), line("500,000", 0.80, 0.30, w: 0.15),
            line("평가금액", 0.03, 0.35, w: 0.12), line("6,000,000", 0.26, 0.35, w: 0.2),
            line("수익률(%)", 0.52, 0.35, w: 0.12), line("9.09", 0.85, 0.35, w: 0.1),
            line("매매비용", 0.03, 0.40, w: 0.12),
            line("종목명", 0.15, 0.45, h: 0.015, w: 0.1), line("평가손익", 0.43, 0.45, h: 0.015, w: 0.1),
            line("평가금액", 0.63, 0.45, h: 0.015, w: 0.1), line("현재가", 0.84, 0.45, h: 0.015, w: 0.08),
            line("주문가능", 0.04, 0.48, h: 0.015, w: 0.1), line("보유수량", 0.24, 0.48, h: 0.015, w: 0.1),
            line("수익률(%)", 0.42, 0.48, h: 0.015, w: 0.12), line("매입금액", 0.63, 0.48, h: 0.015, w: 0.1),
            line("평균단가", 0.83, 0.48, h: 0.015, w: 0.1),
            line("가나전자", 0.03, 0.53, h: 0.018, w: 0.2),
            line("-1,000,000", 0.40, 0.53, h: 0.017, w: 0.17), line("2,000,000", 0.60, 0.53, h: 0.017, w: 0.16),
            line("50,000", 0.84, 0.53, h: 0.017, w: 0.1),
            line("40", 0.10, 0.56, h: 0.017, w: 0.04), line("40", 0.30, 0.56, h: 0.017, w: 0.04),
            line("-33.33", 0.45, 0.56, h: 0.017, w: 0.1), line("3,000,000", 0.60, 0.56, h: 0.017, w: 0.16),
            line("75,000", 0.84, 0.56, h: 0.017, w: 0.1),
            line("다라화학", 0.03, 0.62, h: 0.018, w: 0.2),
            line("1,500,000", 0.41, 0.62, h: 0.017, w: 0.16), line("4,000,000", 0.60, 0.62, h: 0.017, w: 0.16),
            line("100,000", 0.83, 0.62, h: 0.017, w: 0.11),
            line("1,250", 0.05, 0.65, h: 0.017, w: 0.08), line("1,250", 0.25, 0.65, h: 0.017, w: 0.08),
            line("60.00", 0.45, 0.65, h: 0.017, w: 0.1), line("2,500,000", 0.60, 0.65, h: 0.017, w: 0.16),
            line("2,000", 0.85, 0.65, h: 0.017, w: 0.08),
            line("홈", 0.20, 0.92, w: 0.05), line("국내주식 잔고", 0.33, 0.92, w: 0.15), line("메뉴", 0.05, 0.93, w: 0.06),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.totalMinor == 6_000_000)
        #expect(result.accountLine == "123-4567-8901-0 [종합_주식] 딸 일반주식")
        #expect(result.items.map(\.name) == ["가나전자", "다라화학"])
        #expect(result.items.map(\.valueMinor) == [2_000_000, 4_000_000])
        #expect(result.isBalanced == true)
    }

    // 같은 표를 텍스트 인식이 칸을 붙여 한 줄로 읽었을 때 — 낱말 자리를 글자 수로 어림해도 열을 찾는다
    @Test("2단 표 — 칸이 붙어 한 줄로 읽혀도 평가금액 열을 고른다")
    func mergedTable() {
        let lines = [
            line("종목명", 0.15, 0.45, h: 0.015, w: 0.1),
            line("평가손익 평가금액 현재가", 0.40, 0.45, h: 0.015, w: 0.56),
            line("주문가능 보유수량", 0.04, 0.48, h: 0.015, w: 0.3),
            line("수익률(%) 매입금액 평균단가", 0.40, 0.48, h: 0.015, w: 0.56),
            line("가나전자", 0.03, 0.53, h: 0.018, w: 0.2),
            line("-1,000,000 2,000,000 50,000", 0.40, 0.53, h: 0.017, w: 0.56),
            line("40 40", 0.05, 0.56, h: 0.017, w: 0.3),
            line("-33.33 3,000,000 75,000", 0.40, 0.56, h: 0.017, w: 0.56),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.items.map(\.name) == ["가나전자"])
        #expect(result.items.map(\.valueMinor) == [2_000_000])
        #expect(result.totalMinor == nil)
    }

    // 11-20 실제 화면(둘째)의 배치 — 묶음 목록. 숫자 · 이름은 지어낸 것.
    // 환율 소수 · 아이콘 안 글자(나스닥 100 · S&P 500) · 소수 수량 · 묶음 머리(Alpha −3.2%) · 아래 다른 구역.
    // 300,000 + 450,000 + 250,000 = 1,000,000, 화면 총액 1,000,002 — 해외 종목 환산 반올림 2원(종목 3개 → 3원까지 봐줌)
    @Test("묶음 목록 — 아이콘 글자 · 묶음 머리 · 소수 수량은 종목이 아니고, 반올림 몇 원은 검산을 통과한다")
    func groupedList() {
        let lines = [
            line("달러 환율 1,352.70 +0.4%", 0.05, 0.07, w: 0.5),
            line("652원", 0.06, 0.12, h: 0.018, w: 0.1), line("$0.00", 0.55, 0.12, h: 0.018, w: 0.1),
            line("아무개의 투자", 0.05, 0.18, h: 0.017, w: 0.25),
            line("1,000,002원 ›", 0.05, 0.21, h: 0.03, w: 0.5),
            line("-50,000원 (4.8%)", 0.05, 0.25, w: 0.3),
            line("가나다 순", 0.06, 0.30, w: 0.15), line("현재가 평가금", 0.60, 0.30, w: 0.2), line("$ 원", 0.85, 0.30, w: 0.1),
            line("Alpha -3.2%", 0.05, 0.35, h: 0.018, w: 0.2),
            line("ARQ", 0.19, 0.40, h: 0.018, w: 0.1), line("0.123456주", 0.19, 0.425, h: 0.015, w: 0.2),
            line("300,000원", 0.70, 0.40, h: 0.018, w: 0.25), line("-10,000 (3.2%)", 0.68, 0.425, h: 0.015, w: 0.27),
            line("Core +1.1%", 0.05, 0.47, h: 0.018, w: 0.2),
            line("나스닥", 0.07, 0.523, h: 0.011, w: 0.08), line("100", 0.08, 0.536, h: 0.011, w: 0.05),
            line("QQXM", 0.19, 0.52, h: 0.018, w: 0.12), line("5.842373주", 0.19, 0.545, h: 0.015, w: 0.2),
            line("450,000원", 0.70, 0.52, h: 0.018, w: 0.25), line("+5,000 (1.1%)", 0.70, 0.545, h: 0.015, w: 0.25),
            line("S&P", 0.07, 0.583, h: 0.011, w: 0.06), line("500", 0.08, 0.596, h: 0.011, w: 0.05),
            line("SPXM", 0.19, 0.58, h: 0.018, w: 0.12), line("3.361911주", 0.19, 0.605, h: 0.015, w: 0.2),
            line("250,000원", 0.70, 0.58, h: 0.018, w: 0.25), line("-1,000 (0.4%)", 0.70, 0.605, h: 0.015, w: 0.25),
            line("보기 설정", 0.20, 0.66, w: 0.15), line("자세히 보기 ›", 0.62, 0.66, w: 0.2),
            line("주문내역", 0.05, 0.72, h: 0.02, w: 0.15), line("이번 달 4건 ›", 0.70, 0.72, w: 0.2),
            line("증권", 0.30, 0.93, w: 0.06), line("관심", 0.48, 0.93, w: 0.06),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.totalMinor == 1_000_002)
        #expect(result.accountLine == "아무개의 투자")
        #expect(result.items.map(\.name) == ["ARQ", "QQXM", "SPXM"])
        #expect(result.items.map(\.valueMinor) == [300_000, 450_000, 250_000])
        #expect(result.isBalanced == true)
    }
}
