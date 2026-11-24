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
        #expect(CaptureParser.amounts(in: "45,612,l38원") == [45_612_138])   // 굵은 1 을 l 로 읽음
        #expect(CaptureParser.amounts(in: "2,0O0,13B원") == [2_000_138])
        #expect(CaptureParser.amounts(in: "12,345,x67원").isEmpty)           // 끊긴 숫자는 고르지 않는다
        #expect(CaptureParser.amounts(in: "출금가능금액 12,345원").isEmpty)
        #expect(CaptureParser.amounts(in: "–7,123,456 (12.4%)").isEmpty)   // 마이너스를 줄표(–)로 읽음 (11-21)
        #expect(CaptureParser.amounts(in: "7,123,456 (12.4%)").isEmpty)    // 부호가 빠져도 뒤 괄호면 손익
        #expect(CaptureParser.amounts(in: "52,000,000원").contains(52_000_000))
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
        // 긴 펀드 이름 속에 앱 이름이 들어 있을 때
        let funds = ["하늘로보틱스", "하늘자산 TDF 2050"]
        #expect(CaptureParser.match("하늘로보틱스증권자투자신탁(주식-재간접형)-Ce 펀드", among: funds)?.index == 0)
    }

    /// 2단 표 화면의 글자 줄 — 요약표 `평가금액` 의 값 칸(`summary`)만 바꿔 끼운다.
    private func twoTier(summary: [CaptureParser.Line]) -> [CaptureParser.Line] {
        [
            line("‹ 내자산", 0.05, 0.07, h: 0.022, w: 0.2),
            line("자산", 0.10, 0.13, h: 0.02, w: 0.08), line("국내주식", 0.38, 0.13, h: 0.02, w: 0.15),
            line("해외주식", 0.72, 0.13, h: 0.02, w: 0.15),
            line("123-4567-8901-0 [종합_주식] 딸 일반주식", 0.05, 0.19, w: 0.6),
            line("전체", 0.03, 0.25, w: 0.06), line("담보", 0.37, 0.25, w: 0.06), line("체결", 0.48, 0.25, w: 0.06),
            line("매입금액", 0.03, 0.30, w: 0.12), line("5,500,000", 0.26, 0.30, w: 0.2),
            line("평가손익", 0.52, 0.30, w: 0.12), line("500,000", 0.80, 0.30, w: 0.15),
            line("평가금액", 0.03, 0.35, w: 0.12),
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
        ] + summary
    }

    // 11-20 실제 화면(첫째)의 배치 — 2단 표. 숫자 · 이름 · 계좌는 지어낸 것.
    // 위에 메뉴 · 탭 · 계좌 줄 · 단추 줄, 이름표 | 값 요약표, 머리줄 두 단, 한 칸에 평가금액(위) · 매입금액(아래).
    // 평가금액 2,000,000 + 4,000,000 = 6,000,000 = 요약표 평가금액 (손으로 셈). 매입금액(3,000,000)이 평가금액보다
    // 큰 손실 종목 · 부호 없는 이익(1,500,000) · 쉼표 든 수량(1,250) 을 일부러 넣었다 — 큰 값 고르기로는 틀린다.
    @Test("2단 표 — 머리줄의 평가금액 열 · 위 단을 고르고, 메뉴 · 탭 · 단추는 종목이 아니다")
    func twoTierTable() {
        let lines = twoTier(summary: [line("6,000,000", 0.26, 0.35, w: 0.2)])
        let result = CaptureParser.parse(lines)
        #expect(result.totalMinor == 6_000_000)
        #expect(result.accountLine == "123-4567-8901-0 [종합_주식] 딸 일반주식")
        #expect(result.items.map(\.name) == ["가나전자", "다라화학"])
        #expect(result.items.map(\.valueMinor) == [2_000_000, 4_000_000])
        #expect(result.isBalanced == true)
    }

    // 11-21 빌드 152 실제 — 요약표 평가금액(총액)의 끝 세 자리를 떨어뜨려 읽어 `확인 필요` 가 됐다(종목은 다 맞음)
    @Test("총액 끝 세 자리가 떨어져 읽혀도 붙이고, 앞 묶음만 읽히면 총액 없음으로")
    func splitTotal() {
        let spaced = CaptureParser.parse(twoTier(summary: [line("6,000 000", 0.26, 0.35, w: 0.2)]))
        #expect(spaced.totalMinor == 6_000_000)
        #expect(spaced.isBalanced == true)
        let apart = CaptureParser.parse(twoTier(summary: [line("6,000", 0.26, 0.35, w: 0.12), line("000", 0.39, 0.35, w: 0.06)]))
        #expect(apart.totalMinor == 6_000_000)
        #expect(apart.isBalanced == true)
        // 마지막 쉼표를 빠뜨리고 읽음 — `6,000000` (11-21 빌드 158 딸 계좌)
        let noComma = CaptureParser.parse(twoTier(summary: [line("6,000000", 0.26, 0.35, w: 0.2)]))
        #expect(noComma.totalMinor == 6_000_000)
        #expect(noComma.isBalanced == true)
        #expect(CaptureParser.amounts(in: "6,000000원") == [6_000_000])
        #expect(CaptureParser.amounts(in: "6,0000").isEmpty)          // 세 자리가 아니면 망가진 숫자 — 고르지 않는다
        #expect(CaptureParser.amounts(in: "5,123456주").isEmpty)       // 붙여도 수량이면 뺀다
        // 앞 묶음만 — 6,000 은 가장 큰 종목(4,000,000)보다 작아 총액일 수 없다
        let cut = CaptureParser.parse(twoTier(summary: [line("6,000", 0.26, 0.35, w: 0.12)]))
        #expect(cut.totalMinor == nil)
        #expect(cut.items.map(\.valueMinor) == [2_000_000, 4_000_000])
        #expect(cut.isBalanced == nil)
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
    // `3.654321수` 는 텍스트 인식이 `주` 를 `수` 로 잘못 읽은 것(빌드 150 실제 사례) — 이름에 붙으면 안 된다.
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
            line("QQXM", 0.19, 0.52, h: 0.018, w: 0.12), line("5.123456주", 0.19, 0.545, h: 0.015, w: 0.2),
            line("450,000원", 0.70, 0.52, h: 0.018, w: 0.25), line("+5,000 (1.1%)", 0.70, 0.545, h: 0.015, w: 0.25),
            line("S&P", 0.07, 0.583, h: 0.011, w: 0.06), line("500", 0.08, 0.596, h: 0.011, w: 0.05),
            line("SPXM", 0.19, 0.58, h: 0.018, w: 0.12), line("3.654321수", 0.19, 0.605, h: 0.015, w: 0.2),
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

    // 11-20 셋째 실제 화면의 배치 — 계좌 총액 없이 맨 위가 첫 종목, 종목마다 `현재가` · `현재가(장마감)` 줄. 숫자 · 이름은 지어낸 것.
    // 맨 위 종목 금액(큰 글씨)을 계좌 총액으로 잘못 보면 그 종목이 빠진다 — 같은 줄에 종목 이름이 있으면 총액이 아니다.
    @Test("총액 없는 목록 — 첫 종목 금액은 총액이 아니고, 현재가(장마감) 줄은 종목이 아니다")
    func listWithoutTotal() {
        let lines = [
            line("‹ 내 계좌", 0.03, 0.07, w: 0.2), line("기본계좌", 0.42, 0.07, h: 0.02, w: 0.15), line("관리", 0.88, 0.07, w: 0.08),
            line("· 전체", 0.55, 0.12, w: 0.08), line("주식", 0.68, 0.12, w: 0.06),
            line("VELT", 0.05, 0.17, h: 0.02, w: 0.1), line("2,430,040원", 0.70, 0.17, h: 0.02, w: 0.25),
            line("1.234567주", 0.05, 0.20, h: 0.017, w: 0.15), line("-120,000원 (-4.70%)", 0.62, 0.20, h: 0.017, w: 0.33),
            line("현재가", 0.05, 0.235, w: 0.08), line("Pre 12.34 USD ▼ -0.10 (-0.8%) ›", 0.45, 0.235, w: 0.5),
            line("가온소프트", 0.05, 0.28, h: 0.02, w: 0.2), line("5,000,000원", 0.70, 0.28, h: 0.02, w: 0.25),
            line("100주", 0.05, 0.31, h: 0.017, w: 0.08), line("+200,000원 (+4.17%)", 0.62, 0.31, h: 0.017, w: 0.33),
            line("현재가(장마감)", 0.05, 0.345, w: 0.2), line("50,000원 ▼ -2,500 (-4.80%) ›", 0.52, 0.345, w: 0.43),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.totalMinor == nil)
        #expect(result.items.map(\.name) == ["VELT", "가온소프트"])
        #expect(result.items.map(\.valueMinor) == [2_430_040, 5_000_000])
        #expect(result.isBalanced == nil)
    }

    // 같은 증권사의 다른 계좌 — 큰 총액 = 종목 합 + 출금가능금액(현금). 숫자 · 계좌는 지어낸 것.
    // 3,000,000 + 200,000 + 현금 111,001 = 3,311,001 (손으로 셈)
    @Test("총액에 현금이 든 계좌 — 출금가능금액을 더해 검산하고, 현재가 줄 · 안내 문구는 종목이 아니다")
    func totalWithCash() {
        let lines = [
            line("‹ 내 계좌", 0.03, 0.07, w: 0.2), line("ISA(중개형)", 0.40, 0.07, h: 0.02, w: 0.2), line("관리", 0.88, 0.07, w: 0.08),
            line("가나증권 012345678901", 0.05, 0.16, w: 0.4),
            line("3,311,001원", 0.05, 0.19, h: 0.03, w: 0.4), line("입금", 0.72, 0.195, h: 0.02, w: 0.08), line("송금", 0.85, 0.195, h: 0.02, w: 0.08),
            line("출금가능금액", 0.05, 0.24, w: 0.17), line("111,001원", 0.23, 0.24, w: 0.12),
            line("투자내역", 0.18, 0.31, h: 0.02, w: 0.15), line("거래내역", 0.66, 0.31, h: 0.02, w: 0.15),
            line("· 전체", 0.55, 0.37, w: 0.08),
            line("가나전자", 0.05, 0.42, h: 0.02, w: 0.2), line("3,000,000원", 0.70, 0.42, h: 0.02, w: 0.25),
            line("60주", 0.05, 0.45, h: 0.017, w: 0.08), line("-100,000원 (-3.23%)", 0.62, 0.45, h: 0.017, w: 0.33),
            line("현재가(장마감)", 0.05, 0.485, w: 0.2), line("50,000원 ▼ -620 (-1.22%) ›", 0.52, 0.485, w: 0.43),
            line("다라화학", 0.05, 0.53, h: 0.02, w: 0.2), line("200,000원", 0.70, 0.53, h: 0.02, w: 0.25),
            line("10주", 0.05, 0.56, h: 0.017, w: 0.08), line("+5,000원 (+2.56%)", 0.62, 0.56, h: 0.017, w: 0.33),
            line("현재가(장마감)", 0.05, 0.595, w: 0.2), line("20,000원 ▼ -100 (-0.50%) ›", 0.52, 0.595, w: 0.43),
            line("현재가 제공 : 가나 증권 11.20 22:53", 0.45, 0.65, w: 0.5),
            line("외화 및 해외 종목은 오늘의 기준 환율로 계산합니다", 0.35, 0.675, w: 0.6),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.totalMinor == 3_311_001)
        #expect(result.cashMinor == 111_001)
        #expect(result.accountLine == "가나증권 012345678901")
        #expect(result.items.map(\.name) == ["가나전자", "다라화학"])
        #expect(result.items.map(\.valueMinor) == [3_000_000, 200_000])
        #expect(result.expectedSumMinor == 3_311_001)
        #expect(result.isBalanced == true)
    }

    // 11-21 — 총액 없는 목록에서 QQQM 금액이 앞 두 묶음만 읽혔다(검산이 없어 그대로 들어갈 뻔 — 크게 바뀐 항목 확인이 잡음)
    @Test("목록형 종목 금액 — 끝 세 자리가 떨어져 읽혀도 붙인다, 수량 · 비율은 안 붙인다")
    func listTailJoin() {
        func lines(_ value: [CaptureParser.Line]) -> [CaptureParser.Line] {
            [
                line("‹ 내 계좌", 0.03, 0.07, w: 0.2), line("기본계좌", 0.42, 0.07, h: 0.02, w: 0.15),
                line("VELT", 0.05, 0.17, h: 0.02, w: 0.1), line("2,430,040원", 0.70, 0.17, h: 0.02, w: 0.25),
                line("1.234567주", 0.05, 0.20, h: 0.017, w: 0.15), line("-120,000원 (-4.70%)", 0.62, 0.20, h: 0.017, w: 0.33),
                line("가온소프트", 0.05, 0.28, h: 0.02, w: 0.2),
                line("100주", 0.05, 0.31, h: 0.017, w: 0.08), line("+200,000원 (+4.17%)", 0.62, 0.31, h: 0.017, w: 0.33),
            ] + value
        }
        let spaced = CaptureParser.parse(lines([line("5,000 000원", 0.70, 0.28, h: 0.02, w: 0.25)]))
        #expect(spaced.items.map(\.valueMinor) == [2_430_040, 5_000_000])
        let apart = CaptureParser.parse(lines([line("5,000,", 0.70, 0.28, h: 0.02, w: 0.13),
                                               line("000원", 0.84, 0.28, h: 0.02, w: 0.11)]))
        #expect(apart.items.map(\.valueMinor) == [2_430_040, 5_000_000])
        // 수량(주) · 비율(%) 이 뒤따르면 붙이지 않는다
        #expect(CaptureParser.lineValues(line("1,234 567주", 0.6, 0.5, w: 0.3), rows: []) == [1_234])
        #expect(CaptureParser.lineValues(line("1,234 567%", 0.6, 0.5, w: 0.3), rows: []) == [1_234])
        #expect(CaptureParser.lineValues(line("1,234 567원", 0.6, 0.5, w: 0.3), rows: []) == [1_234_567])
    }

    // 11-21 토스 실제 두 장(빌드 157 `읽은 글자 복사`) — 숫자 · 이름은 지어낸 것.
    // ① 맨 위에 계좌 탭 · 원화 · 달러 카드가 있어 총액이 37% 높이 — 위쪽 30% 규칙으로는 `총액 못 찾음`
    // ② 한 종목 금액을 `250, 001원`(쉼표 뒤 빈칸)으로 읽어 그 종목이 통째로 빠짐 ③ 아이콘이 `ㅧ` 한 낱자로 읽힘
    // 300,000 + 450,000 + 250,001 = 1,000,001, 화면 총액 1,000,003 — 환산 반올림 2원(종목 3개 → 3원까지)
    @Test("토스 계좌 탭 화면 — 총액이 첫 종목 줄 위면 찾고, 쉼표 뒤 빈칸 금액도 읽고, 낱자 조각은 종목이 아니다")
    func tossWithTabs() {
        let lines = [
            line("나스닥 100 선물 25,126.50-5.5%", 0.057, 0.090, w: 0.50),
            line("기본계좌 -18.1%", 0.0, 0.1435, w: 0.21), line("다라계좌 -15.5%", 0.27, 0.145, w: 0.27),
            line("가나계좌", 0.64, 0.145, w: 0.16),
            line("내 계좌", 0.057, 0.20, w: 0.09), line("원화", 0.088, 0.244, w: 0.06),
            line("652원", 0.088, 0.266, w: 0.10), line("$0.00", 0.548, 0.2655, w: 0.105),
            line("아무개의 투자", 0.05, 0.336, h: 0.02, w: 0.21),
            line("1,000,003원 >", 0.053, 0.368, h: 0.036, w: 0.42),
            line("-50,000원 (4.8%)", 0.054, 0.41, h: 0.02, w: 0.33),
            line("가나다 순 ✓", 0.073, 0.452, w: 0.15), line("현재가 평가금", 0.59, 0.452, w: 0.19),
            line("Alpha", 0.054, 0.513, w: 0.10), line("-3.2%>", 0.16, 0.511, w: 0.16),
            line("ARQ", 0.18, 0.558, h: 0.0175, w: 0.09), line("300,000원", 0.741, 0.5578, h: 0.024, w: 0.20),
            line("ㅧ", 0.082, 0.574, h: 0.013, w: 0.035),
            line("0.123456주", 0.177, 0.587, w: 0.16), line("-10,000 (3.2%)", 0.71, 0.587, w: 0.23),
            line("Core -1.1% >", 0.057, 0.708, w: 0.24),
            line("QQXM", 0.18, 0.7527, h: 0.018, w: 0.13), line("450,000원", 0.71, 0.7518, h: 0.0232, w: 0.23),
            line("나스닥", 0.066, 0.7606, h: 0.012, w: 0.067), line("100", 0.079, 0.7747, h: 0.009, w: 0.044),
            line("5.123456주", 0.18, 0.78, w: 0.16),
            line("SPXM", 0.18, 0.8212, h: 0.0176, w: 0.12), line("250, 001원", 0.744, 0.8194, h: 0.024, w: 0.20),
            line("S&P", 0.073, 0.83, h: 0.010, w: 0.054), line("500", 0.073, 0.8416, h: 0.0116, w: 0.05),
            line("증권", 0.29, 0.952, w: 0.05), line("관심", 0.467, 0.952, w: 0.047),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.totalMinor == 1_000_003)
        #expect(result.accountLine == "아무개의 투자")
        #expect(result.items.map(\.name) == ["ARQ", "QQXM", "SPXM"])
        #expect(result.items.map(\.valueMinor) == [300_000, 450_000, 250_001])
        #expect(result.isBalanced == true)
        #expect(CaptureParser.amounts(in: "250, 001원") == [250_001])
    }

    // 227번 — 총액이 팔면 받을 돈(수수료 · 세금을 뺀 값)이거나 예수금을 품은 화면. 숫자 · 계좌는 지어낸 것.
    // 종목 합 6,000,000. 기댓값은 Tools/ocr-sim/parser.py 로 같은 줄을 돌려 확인했다.
    @Test("비용 · 현금 줄 — 화면에 적힌 수수료는 빼고 예수금은 더해 검산하고, 그 줄은 종목이 아니다")
    func feeAndCashLines() {
        func page(_ total: String, _ extra: [CaptureParser.Line]) -> [CaptureParser.Line] {
            [line("가나증권 012345678901", 0.05, 0.06, h: 0.02, w: 0.40), line(total, 0.05, 0.09, h: 0.04, w: 0.40)] + extra
                + [line("가나전자", 0.05, 0.40, h: 0.025, w: 0.30), line("1,000,000원", 0.70, 0.40, h: 0.025, w: 0.25),
                   line("다라화학", 0.05, 0.60, h: 0.025, w: 0.30), line("2,000,000원", 0.70, 0.60, h: 0.025, w: 0.25),
                   line("마바바이오로직스", 0.05, 0.80, h: 0.025, w: 0.30), line("3,000,000원", 0.70, 0.80, h: 0.025, w: 0.25)]
        }
        let fee = [line("예상 매도수수료 · 제세금", 0.05, 0.16, h: 0.02, w: 0.40), line("-10,000원", 0.70, 0.16, h: 0.02, w: 0.25)]
        let cash = [line("예수금", 0.05, 0.16, h: 0.02, w: 0.20), line("40,000원", 0.70, 0.16, h: 0.02, w: 0.25)]
        let feeBelow = [line("예상 매도수수료 · 제세금", 0.05, 0.20, h: 0.02, w: 0.40), line("-10,000원", 0.70, 0.20, h: 0.02, w: 0.25)]

        let withFee = CaptureParser.parse(page("5,990,000원", fee))
        #expect(withFee.items.map(\.name) == ["가나전자", "다라화학", "마바바이오로직스"])
        #expect(withFee.feeMinor == 10_000)
        #expect(withFee.applied.feeMinor == 10_000 && withFee.applied.cashMinor == nil)
        #expect(withFee.isBalanced == true)

        let withCash = CaptureParser.parse(page("6,040,000원", cash))
        #expect(withCash.cashMinor == 40_000)
        #expect(withCash.isBalanced == true)

        let both = CaptureParser.parse(page("6,030,000원", cash + feeBelow))
        #expect(both.applied.cashMinor == 40_000 && both.applied.feeMinor == 10_000)
        #expect(both.isBalanced == true)

        // 화면에 비용 줄이 없으면 검산은 안 맞고, 차이로 짐작한다(CaptureBatch.gap)
        let bare = CaptureParser.parse(page("5,970,000원", []))
        #expect(bare.isBalanced == false)
        #expect(CaptureBatch.gap(in: bare, pages: 1) == .fees(30_000))
    }

    // 228번 — 11-23 실제 화면의 배치(종합잔고 · 카드형). 계좌 번호 · 이름 · 숫자는 지어낸 것.
    // `자산` 이 총액 옆 이름표인데 종목 이름으로 읽혀 총액을 못 찾고, `현금잔고(예수금)` 의 예수금은 괄호에 들어 있었고,
    // 그 금액 `350원` 은 쉼표가 없어 금액으로 안 읽혔다. 기댓값은 Tools/ocr-sim/parser.py 로 같은 줄을 돌려 확인했다.
    @Test("자산 이름표 · 아래 줄 예수금 — 자산은 종목이 아니고 총액을 찾으며, 괄호 안 예수금 · 쉼표 없는 금액을 현금으로")
    func assetLabelAndCashBelow() {
        let lines = [
            line("< 종합잔고", 0.046, 0.068, h: 0.036, w: 0.245),
            line("1234567890-01 [종합(가나 비대면)]", 0.066, 0.145, h: 0.019, w: 0.656),
            line("25,350 원", 0.678, 0.183, h: 0.032, w: 0.252), line("자산", 0.066, 0.189, h: 0.019, w: 0.076),
            line("+150원(+0.60%)", 0.647, 0.217, h: 0.019, w: 0.281),
            line("예금자보호안내 O", 0.066, 0.305, h: 0.018, w: 0.265),
            line("하늘로보틱스증권자H(주-재간)-Ce", 0.066, 0.368, h: 0.022, w: 0.656), line(":", 0.893, 0.371, h: 0.016, w: 0.019),
            line("펀드", 0.066, 0.394, h: 0.019, w: 0.073),
            line("25,000원", 0.715, 0.408, h: 0.030, w: 0.216), line("+150원(+0.60%)", 0.675, 0.443, h: 0.015, w: 0.256),
            line("현금잔고(예수금)", 0.069, 0.507, h: 0.021, w: 0.284), line(":", 0.896, 0.510, h: 0.015, w: 0.016),
            line("350원", 0.789, 0.546, h: 0.025, w: 0.142), line("0원(0%)", 0.801, 0.580, h: 0.017, w: 0.133),
            line("KOSPI", 0.066, 0.884, h: 0.014, w: 0.104), line("4,700.00 V 150.00(3.10%)", 0.281, 0.882, h: 0.018, w: 0.473),
            line("관심종목 주식현재가 종합차트 주식주문", 0.148, 0.926, h: 0.019, w: 0.697),
        ]
        let result = CaptureParser.parse(lines)
        #expect(result.accountLine == "1234567890-01 [종합(가나 비대면)]")
        #expect(result.totalMinor == 25_350)
        #expect(result.items.map(\.name) == ["하늘로보틱스증권자H(주-재간)-Ce 펀드"])
        #expect(result.items.map(\.valueMinor) == [25_000])
        #expect(result.cashMinor == 350)
        #expect(result.isBalanced == true)
        #expect(CaptureParser.looseAmount(in: "350원", signed: false) == 350)
        #expect(CaptureParser.looseAmount(in: "0원(0%)", signed: false) == 0)
        #expect(CaptureParser.looseAmount(in: "-1,200원", signed: false) == nil)
        #expect(CaptureParser.looseAmount(in: "-1,200원", signed: true) == 1_200)
        #expect(CaptureParser.looseAmount(in: "12주", signed: false) == nil)
    }

    // 229번 — 11-23 실제 화면(토스 · `$` 로 보기)의 배치. 이름 · 숫자는 지어낸 것. 총액만 원화, 종목 평가금은 달러.
    // 앱은 원화로만 적고 환율을 가져오지 않는다(ADR-0005) — 읽지 않고 세어서 `원` 으로 바꿔 찍어 달라고 알린다.
    // 기댓값은 Tools/ocr-sim/parser.py 로 같은 줄을 돌려 확인했다.
    @Test("달러로 보이는 화면 — 달러 평가금은 읽지 않고 세며, 현재가만 달러인 줄(0.93 USD)은 세지 않는다")
    func dollarValues() {
        var lines = [
            line("내 종목보기 >", 0.057, 0.19, h: 0.019, w: 0.22),
            line("100,000,000원", 0.054, 0.221, h: 0.036, w: 0.42),
            line("-1,000,000원 (1.0%)", 0.053, 0.255, h: 0.024, w: 0.38),
            line("해외주식", 0.053, 0.357, h: 0.017, w: 0.11),
        ]
        for (name, dollars, top) in [("가나테크", "$1,234.56", 0.40), ("다라에너지", "$987.65", 0.465), ("MBAX", "$2,000.00", 0.53)] {
            lines += [line(name, 0.183, top, h: 0.018, w: 0.14), line(dollars, 0.747, top, h: 0.022, w: 0.2),
                      line("12.345678주", 0.183, top + 0.026, h: 0.014, w: 0.16),
                      line("+123.45 (10.0%)", 0.69, top + 0.026, h: 0.015, w: 0.25)]
        }
        let result = CaptureParser.parse(lines)
        #expect(result.totalMinor == 100_000_000)
        #expect(result.items.isEmpty)
        #expect(result.dollarAmounts == 3)
        #expect(CaptureParser.isDollar("$3,303.22"))
        #expect(CaptureParser.isDollar("US$ 12.5"))
        #expect(!CaptureParser.isDollar("0.93 USD"))
        #expect(!CaptureParser.isDollar("$"))
        #expect(!CaptureParser.isDollar("2,430,040원"))
    }

    // 230번 — 배당금 줄을 종목으로 읽던 것. 숫자 · 계좌는 지어낸 것, 기댓값은 Tools/ocr-sim/parser.py 로 같은 줄을 돌려 확인했다.
    // 종목 합 6,000,000 = 총액. `VEGA 미국배당다우존스` 는 이름에 배당이 들어 있어도 종목이다.
    @Test("배당 이름표 줄 — 종목이 아니고 그 금액(같은 줄 · 아래 줄)은 앞 종목에도 안 붙는다, 이름에 배당이 든 종목은 그대로")
    func dividendLines() {
        let base = [line("가나증권 012345678901", 0.05, 0.06, h: 0.02, w: 0.40), line("6,000,000원", 0.05, 0.09, h: 0.04, w: 0.40),
                    line("가나전자", 0.05, 0.30, h: 0.025, w: 0.40), line("1,000,000원", 0.70, 0.30, h: 0.025, w: 0.25),
                    line("VEGA 미국배당다우존스", 0.05, 0.45, h: 0.025, w: 0.40), line("2,000,000원", 0.70, 0.45, h: 0.025, w: 0.25),
                    line("마바바이오로직스", 0.05, 0.60, h: 0.025, w: 0.40), line("3,000,000원", 0.70, 0.60, h: 0.025, w: 0.25)]
        let sameRow = base + [line("이번 달 배당금", 0.05, 0.75, h: 0.022, w: 0.30), line("12,345원", 0.70, 0.75, h: 0.030, w: 0.25)]
        let below = base + [line("배당금 내역 ›", 0.05, 0.75, h: 0.022, w: 0.30), line("받을 배당금", 0.05, 0.80, h: 0.02, w: 0.25),
                            line("8,800,000원", 0.70, 0.83, h: 0.035, w: 0.25)]
        // 11-23 실제 화면(토스)의 꼴 — 아래 구역 `주문내역 | 이번 달 n건 >` · `판매수익` · `배당금 | 이번 달 ○원 >`
        let section = base + [line("주문내역", 0.057, 0.70, h: 0.021, w: 0.142), line("이번 달 29건 >", 0.70, 0.70, h: 0.018, w: 0.246),
                              line("판매수익", 0.057, 0.747, h: 0.019, w: 0.142), line("배당금", 0.057, 0.796, h: 0.019, w: 0.107),
                              line("이번 달 5,000원 >", 0.66, 0.798, h: 0.021, w: 0.284)]
        for lines in [sameRow, below, section] {
            let result = CaptureParser.parse(lines)
            #expect(result.items.map(\.name) == ["가나전자", "VEGA 미국배당다우존스", "마바바이오로직스"])
            #expect(result.items.map(\.valueMinor) == [1_000_000, 2_000_000, 3_000_000])
            #expect(result.isBalanced == true)
        }
        #expect(CaptureParser.dividendLine("예상 배당금(세전) 12,000원"))
        #expect(CaptureParser.dividendLine("분배금 3,210원"))
        #expect(!CaptureParser.dividendLine("VEGA 미국배당다우존스"))
        #expect(!CaptureParser.dividendLine("배당 플래너"))
    }

    // 231번 — 11-23 실제 화면(비중 도넛)의 배치. 이름 · 숫자는 지어낸 것. 금액이 이름 바로 아래 왼쪽, 오른쪽은 비율뿐.
    // 기댓값은 Tools/ocr-sim/parser.py 로 같은 줄을 돌려 확인했다.
    @Test("이름 아래 왼쪽 금액 — 오른쪽에 금액이 없으면 이름 바로 아래 같은 자리의 금액만 있는 줄을 읽는다")
    func stackedLeftAmounts() {
        var lines = [line("20:45", 0.10, 0.033, h: 0.019, w: 0.14), line("총 금액", 0.057, 0.164, h: 0.013, w: 0.082),
                     line("10,000,000원", 0.056, 0.186, h: 0.043, w: 0.452)]
        for (name, amount, percent, top) in [("가나전자", "5,000,000원", "50.0%", 0.48), ("다라화학", "3,000,000원", "30.0%", 0.54),
                                             ("VEGA 200", "2,000,000원", "20.0%", 0.60)] {
            lines += [line(name, 0.161, top, h: 0.017, w: 0.13), line(percent, 0.82, top + 0.009, h: 0.02, w: 0.12),
                      line(amount, 0.160, top + 0.025, h: 0.017, w: 0.19)]
        }
        lines += [line("국내주식 해외주식", 0.41, 0.911, h: 0.02, w: 0.306), line("전체", 0.293, 0.913, h: 0.018, w: 0.069)]
        let result = CaptureParser.parse(lines)
        #expect(result.totalMinor == 10_000_000)
        #expect(result.items.map(\.name) == ["가나전자", "다라화학", "VEGA 200"])
        #expect(result.items.map(\.valueMinor) == [5_000_000, 3_000_000, 2_000_000])
        #expect(result.isBalanced == true)
    }
}
