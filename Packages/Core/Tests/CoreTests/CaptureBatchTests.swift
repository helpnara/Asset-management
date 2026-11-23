import Foundation
import Testing
@testable import Core

/// 캡처 여러 장 → 계좌별 묶음 → 앱 계좌 · 종목 짝 (222번). 이름 · 숫자 · 계좌는 지어낸 것.
@Suite("CaptureBatch — 묶기 · 계좌 고르기 · 계좌 안에서만 짝")
struct CaptureBatchTests {

    private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
    private func holding(_ n: Int, _ name: String, capture: String = "") -> CaptureBatch.HoldingInfo {
        .init(id: id(n), name: name, captureName: capture)
    }
    private func item(_ name: String, _ value: Int?) -> CaptureParser.Item { .init(name: name, valueMinor: value) }

    @Test("계좌 표시 — 번호(숫자 8개 이상)가 있으면 그 숫자, 없으면 빈칸을 걷은 글자")
    func accountKey() {
        #expect(CaptureBatch.accountKey("123-4567-8901-0 [종합_주식] 딸 일반주식") == "123456789010")
        #expect(CaptureBatch.accountKey("가나증권 012345678901") == "012345678901")
        #expect(CaptureBatch.accountKey("아무개의 투자") == "아무개의투자")
        #expect(CaptureBatch.accountKey("종합매매 · 아빠 · 123-45-****") == "종합매매·아빠·123-45-****")   // 숫자 5개뿐
        #expect(CaptureBatch.accountKey(nil) == "")
        #expect(CaptureBatch.accountKey("  ") == "")
    }

    @Test("짝 — 기억해 둔 증권사 이름이 먼저, 그다음 이름 맞추기, 한 종목은 한 번만")
    func pair() {
        let holdings = [
            holding(1, "TIGER 미국S&P500"),
            holding(2, "하늘로보틱스", capture: "하늘로보틱스증권자투자신탁(주식-재간접형)-Ce 펀드"),
            holding(3, "가나전자"),
        ]
        let items = [item("하늘로보틱스증권자투자신탁(주식-재간접형)-Ce 펀드", 42_000),
                     item("TIGER 미국S&P500", 473_000),
                     item("없는 종목", 1_000)]
        #expect(CaptureBatch.pair(items, with: holdings) == [id(2), id(1), nil])
        // 같은 종목을 두 번 읽어도(겹쳐 찍힘) 한 번만 짝
        #expect(CaptureBatch.pair([item("가나전자", 1), item("가나 전자", 1)], with: holdings) == [id(3), nil])
    }

    // 같은 ETF 를 IRP · 연금저축 두 계좌에 — 빌드 151 넷째 시험에서 다른 계좌와 짝지어진 경우
    @Test("계좌 고르기 — 같은 종목이 두 계좌에 있으면 기억해 둔 표시로, 없으면 짝이 더 많은 쪽, 같으면 모름")
    func suggestAccount() {
        let pensionLine = "022-0000-0000-0 [연금저축] 아빠"
        let irp = CaptureBatch.AccountInfo(id: id(10), captureKey: "",
                                           holdings: [holding(1, "TIGER 미국S&P500"), holding(2, "KODEX 국고채3년")])
        let pension = CaptureBatch.AccountInfo(id: id(20), captureKey: "", holdings: [holding(3, "TIGER 미국S&P500")])
        let pensionPage = CaptureParser.Result(accountLine: pensionLine, totalMinor: 2_000_000,
                                               items: [item("TIGER 미국S&P500", 2_000_000)])
        #expect(CaptureBatch.suggestAccount(for: pensionPage, among: [irp, pension]) == nil)   // 1 : 1 — 모름

        let remembered = CaptureBatch.AccountInfo(id: id(20), captureKey: CaptureBatch.accountKey(pensionLine),
                                                  holdings: pension.holdings)
        #expect(CaptureBatch.accountKey(pensionLine) == "022000000000")
        #expect(CaptureBatch.suggestAccount(for: pensionPage, among: [irp, remembered]) == id(20))

        let irpPage = CaptureParser.Result(accountLine: "001-0000-0000-0 [IRP] 아빠", totalMinor: 660_000,
                                           items: [item("KODEX 국고채3년", 190_000), item("TIGER 미국S&P500", 470_000)])
        #expect(CaptureBatch.suggestAccount(for: irpPage, among: [irp, remembered]) == id(10))   // 2 : 1
        // 그 계좌 안에서만 짝 — 연금저축 캡처의 TIGER 는 연금저축의 TIGER(3)
        #expect(CaptureBatch.pair(pensionPage.items, with: remembered.holdings) == [id(3)])
    }

    // 가나증권 계좌를 두 장(둘째 장은 아래로 넘겨 찍어 계좌 줄 · 총액 없음), 다른 계좌 한 장, 다시 머리 없는 한 장.
    // 첫 묶음 1,000,000 + 2,000,000 + 3,000,000 = 6,000,000 = 총액 (다라화학은 두 장에 겹쳐 찍힘 — 한 번만)
    // 226번: 머리 없는 장은 '바로 앞 묶음' 이 아니라 증거(검산 · 종목 짝)로 붙는다. 넷째 장(가나전자 한 줄)은 바로 앞이
    // 다른 계좌(아무개의 투자)지만 가나증권 계좌의 종목이고 거기 이미 있는 줄이라 가나증권으로 — 다시 찍힌 장이다.
    @Test("묶기 — 머리 없는 장은 증거로(검산 · 짝), 겹친 종목은 하나만")
    func group() {
        let gana = CaptureBatch.AccountInfo(id: id(10), captureKey: "",
                                            holdings: [holding(1, "가나전자"), holding(2, "다라화학"), holding(3, "마바바이오로직스")])
        let toss = CaptureBatch.AccountInfo(id: id(20), captureKey: "", holdings: [holding(4, "ARQ"), holding(5, "QQXM")])
        let pages = [
            CaptureParser.Result(accountLine: "가나증권 012345678901", totalMinor: 6_000_000,
                                 items: [item("가나전자", 1_000_000), item("다라화학", 2_000_000)]),
            CaptureParser.Result(accountLine: nil, totalMinor: nil,
                                 items: [item("다라화학", 2_000_000), item("마바바이오로직스", 3_000_000)]),
            CaptureParser.Result(accountLine: "아무개의 투자", totalMinor: 750_000,
                                 items: [item("ARQ", 300_000), item("QQXM", 450_000)]),
            CaptureParser.Result(accountLine: nil, totalMinor: nil, items: [item("가나전자", 1_000_000)]),
        ]
        let groups = CaptureBatch.group(pages, accounts: [gana, toss])
        #expect(groups.map(\.pages) == [[0, 1, 3], [2]])
        #expect(groups[0].result.items.map(\.name) == ["가나전자", "다라화학", "마바바이오로직스"])
        #expect(groups[0].result.totalMinor == 6_000_000)
        #expect(groups[0].result.isBalanced == true)
        #expect(groups[1].result.isBalanced == true)
        #expect(CaptureBatch.suggestAccount(for: groups[0].result, among: [gana, toss]) == id(10))
        #expect(CaptureBatch.suggestAccount(for: groups[1].result, among: [gana, toss]) == id(20))
    }

    // 11-21 사용자: "계좌 이름이 나오면 유사한 계좌라면 선택이 가능하지 않을까 … 텍스트 매칭". 계좌 번호 · 이름은 지어낸 것.
    // 같은 ETF 를 IRP · 연금저축 둘 다 가져 짝 수가 같을 때 계좌 줄 글자로 가린다.
    @Test("계좌 줄 글자 — 계좌 이름 3 · 구성원 2(낱말) · 종류 1, 짝 수가 같으면 이걸로 가린다")
    func textMatching() {
        let irp = CaptureBatch.AccountInfo(id: id(10), captureKey: "",
                                           holdings: [holding(1, "TIGER 미국S&P500"), holding(2, "KODEX 국고채3년")],
                                           owner: "아빠", name: "개인IRP", kind: "IRP")
        let pension = CaptureBatch.AccountInfo(id: id(20), captureKey: "", holdings: [holding(3, "TIGER 미국S&P500")],
                                               owner: "아빠", name: "연금저축", kind: "연금저축")
        let pensionLine = "022-1111-2222-0 [연금저축계좌(신)] 아빠 연금저축"
        let irpLine = "001-3333-4444-0 [퇴직연금_개인IRP] 아빠 IRP"
        #expect(CaptureBatch.textScore(pensionLine, irp) == 2)       // 아빠
        #expect(CaptureBatch.textScore(pensionLine, pension) == 5)   // 연금저축 3 + 아빠 2 (종류 = 이름이라 한 번만)
        #expect(CaptureBatch.textScore(irpLine, irp) == 6)           // 개인IRP 3 + 아빠 2 + IRP 1
        #expect(CaptureBatch.textScore("아무개의 투자", irp) == 0)

        // 짝 1 : 1 — 글자로 연금저축
        let pensionPage = CaptureParser.Result(accountLine: pensionLine, totalMinor: 2_000_000,
                                               items: [item("TIGER 미국S&P500", 2_000_000)])
        #expect(CaptureBatch.suggestAccount(for: pensionPage, among: [irp, pension]) == id(20))
        // 짝이 하나도 없어도 계좌 이름이 줄에 들면(3 이상) 고른다
        let emptyPage = CaptureParser.Result(accountLine: pensionLine, totalMinor: nil, items: [item("없는 종목", 1_000)])
        #expect(CaptureBatch.suggestAccount(for: emptyPage, among: [irp, pension]) == id(20))
        // 구성원만 맞는 것(2)으로는 짝 없이 고르지 않는다
        let ownerOnly = CaptureParser.Result(accountLine: "아빠 기타", totalMinor: nil, items: [item("없는 종목", 1_000)])
        #expect(CaptureBatch.suggestAccount(for: ownerOnly, among: [irp, pension]) == nil)

        // 이름이 같은 계좌(일반적립)를 딸 · 아들이 따로 — 한 글자 구성원은 낱말로만
        let daughter = CaptureBatch.AccountInfo(id: id(30), captureKey: "", holdings: [holding(4, "가나전자")],
                                                owner: "딸", name: "일반적립")
        let son = CaptureBatch.AccountInfo(id: id(40), captureKey: "", holdings: [holding(5, "가나전자")],
                                           owner: "아들", name: "일반적립")
        let daughterPage = CaptureParser.Result(accountLine: "123-4567-8901-0 [종합_주식] 딸 일반주식", totalMinor: 1_000_000,
                                                items: [item("가나전자", 1_000_000)])
        #expect(CaptureBatch.suggestAccount(for: daughterPage, among: [son, daughter]) == id(30))
    }

    // MARK: - 여러 장 이어 읽기 (226번). 줄 · 숫자는 지어낸 것 — 기댓값은 Tools/ocr-sim/batch.py 로 같은 입력을 돌려 확인했다.

    private func line(_ text: String, _ x: Double, _ top: Double, _ width: Double, _ height: Double) -> CaptureParser.Line {
        .init(text: text, x: x, top: top, width: width, height: height)
    }
    /// 상태 막대 · 아래 탭 막대 — 장마다 같은 자리에 되풀이된다.
    private var chrome: [CaptureParser.Line] {
        [line("9:41", 0.07, 0.01, 0.08, 0.02), line("홈", 0.10, 0.95, 0.05, 0.02), line("관심", 0.60, 0.95, 0.08, 0.02)]
    }
    private func row(_ name: String, _ amount: String, _ top: Double) -> [CaptureParser.Line] {
        [line(name, 0.05, top, 0.30, 0.025), line(amount, 0.70, top, 0.25, 0.025)]
    }
    private var ganaHead: [CaptureParser.Line] {
        [line("가나증권 012345678901", 0.05, 0.06, 0.40, 0.02), line("6,000,000원", 0.05, 0.09, 0.40, 0.04)]
    }
    /// 첫 장 — 계좌 줄 · 총액 6,000,000 · 종목 셋(합 4,000,000 — 아래로 더 있다).
    private var firstPage: [CaptureParser.Line] {
        chrome + ganaHead + row("가나전자", "1,000,000원", 0.40) + row("다라화학", "2,000,000원", 0.60)
            + row("마바바이오로직스", "1,000,000원", 0.80)
    }
    /// 아래로 0.4 넘겨 찍은 장 — 위 두 줄은 첫 장과 겹치고 새 종목 둘(1,500,000 + 500,000).
    private var secondPage: [CaptureParser.Line] {
        chrome + row("다라화학", "2,000,000원", 0.20) + row("마바바이오로직스", "1,000,000원", 0.40)
            + row("사아금융지주", "1,500,000원", 0.60) + row("자차중공업", "500,000원", 0.80)
    }
    private let fiveItems = ["가나전자", "다라화학", "마바바이오로직스", "사아금융지주", "자차중공업"]

    @Test("겹침 — 같은 글자 · 같은 가로 자리의 줄들로 세로 간격을 잰다, 되풀이 막대는 세지 않는다")
    func shiftBetweenPages() {
        let d = CaptureBatch.shift(firstPage, secondPage)
        #expect(d.map { abs($0 - 0.4) < 1e-9 } == true)
        #expect(CaptureBatch.shift(secondPage, firstPage) == nil)   // 거꾸로는 아래로 이어지지 않는다
        // 다른 계좌에 같은 종목(다라화학)이 한 줄 있어도 겹친 띠 전체가 안 맞으면 겹침이 아니다
        let other = chrome + [line("다른증권 098765432109", 0.05, 0.06, 0.40, 0.02), line("2,700,000원", 0.05, 0.09, 0.40, 0.04)]
            + row("다라화학", "2,000,000원", 0.60) + row("누리엔터", "700,000원", 0.80)
        #expect(CaptureBatch.shift(other, secondPage) == nil)
    }

    @Test("두 장 이어 읽기 — 첫 장만으론 합이 모자라고, 이으면 다섯 종목 · 검산 통과 (고른 차례가 거꾸로여도)")
    func stitchTwoPages() {
        let alone = CaptureParser.parse(firstPage)
        #expect(alone.totalMinor == 6_000_000)
        #expect(alone.isBalanced == false)
        #expect(CaptureBatch.gap(in: alone, pages: 1) == .missing(2_000_000))
        let second = CaptureParser.parse(secondPage)
        #expect(second.accountLine == nil && second.totalMinor == nil)   // 머리 없는 장

        for pages in [[firstPage, secondPage], [secondPage, firstPage]] {
            let groups = CaptureBatch.group(pages, accounts: [])
            #expect(groups.map(\.pages) == [[0, 1]])
            #expect(groups.first?.result.items.map(\.name) == fiveItems)
            #expect(groups.first?.result.items.map(\.valueMinor) == [1_000_000, 2_000_000, 1_000_000, 1_500_000, 500_000])
            #expect(groups.first?.result.totalMinor == 6_000_000)
            #expect(groups.first?.result.isBalanced == true)
        }
    }

    @Test("섞어 고르기 — 사이에 다른 계좌 장이 끼어도(같은 종목이 있어도) 겹침 · 검산으로 제 계좌에")
    func mixedAccounts() {
        let other = chrome + [line("다른증권 098765432109", 0.05, 0.06, 0.40, 0.02), line("2,700,000원", 0.05, 0.09, 0.40, 0.04)]
            + row("다라화학", "2,000,000원", 0.60) + row("누리엔터", "700,000원", 0.80)
        let groups = CaptureBatch.group([firstPage, other, secondPage], accounts: [])
        #expect(groups.map(\.pages) == [[0, 2], [1]])
        #expect(groups[0].result.items.map(\.name) == fiveItems)
        #expect(groups[0].result.isBalanced == true)
        #expect(groups[1].result.items.map(\.name) == ["다라화학", "누리엔터"])
        #expect(groups[1].result.isBalanced == true)
    }

    @Test("머리가 붙어 다니는 앱 — 장마다 계좌 줄 · 총액이 되풀이돼도 한 계좌, 머리는 한 번만")
    func stickyHead() {
        let groups = CaptureBatch.group([firstPage, secondPage + ganaHead], accounts: [])
        #expect(groups.map(\.pages) == [[0, 1]])
        #expect(groups.first?.result.items.map(\.name) == fiveItems)
        #expect(groups.first?.result.isBalanced == true)
    }

    @Test("검산 차이를 말로 — 못 고른 금액 · 수수료 · 소액 예치금 · 시세 움직임 · 모자람 · 넘침")
    func gapHints() {
        func result(_ total: Int?, _ values: [Int?]) -> CaptureParser.Result {
            .init(accountLine: nil, totalMinor: total,
                  items: values.enumerated().map { .init(name: "종목\($0.offset)", valueMinor: $0.element) })
        }
        #expect(CaptureBatch.gap(in: result(nil, [1_000]), pages: 1) == nil)
        #expect(CaptureBatch.gap(in: result(3_000_000, [1_000_000, 2_000_000]), pages: 2) == nil)
        #expect(CaptureBatch.gap(in: result(3_000_000, [1_000_000, 2_000_001]), pages: 2) == nil)   // 종목 수(2)원까지는 맞음
        #expect(CaptureBatch.gap(in: result(3_000_000, [1_000_000, nil]), pages: 1) == .unread(1))
        #expect(CaptureBatch.gap(in: result(3_000_000, [1_000_000]), pages: 1) == .missing(2_000_000))
        #expect(CaptureBatch.gap(in: result(3_000_000, [2_000_000, 2_000_000]), pages: 1) == .extra(1_000_000))
        // 227번 — 합 6,000,000. 총액이 작고 0.7%(42,000) 안이면 수수료 · 세금, 넘으면 넘침
        let six: [Int?] = [1_000_000, 2_000_000, 3_000_000]
        #expect(CaptureBatch.gap(in: result(5_970_000, six), pages: 1) == .fees(30_000))
        #expect(CaptureBatch.gap(in: result(5_959_000, six), pages: 1) == .fees(41_000))
        #expect(CaptureBatch.gap(in: result(5_952_000, six), pages: 1) == .extra(48_000))
        // 총액이 크고 10만 원 안이면 소액 예치금, 넘으면 모자람
        #expect(CaptureBatch.gap(in: result(6_050_000, six), pages: 1) == .deposit(50_000))
        #expect(CaptureBatch.gap(in: result(6_100_000, six), pages: 1) == .deposit(100_000))
        #expect(CaptureBatch.gap(in: result(6_150_000, six), pages: 1) == .missing(150_000))
        #expect(CaptureBatch.gap(in: result(3_000_000, [1_000_000, 1_991_000]), pages: 2) == .deposit(9_000))
        // 10만 원을 넘고 총액의 0.3% 안 — 여러 장이면 시세 움직임, 한 장이면 모자람
        #expect(CaptureBatch.gap(in: result(50_000_000, [20_000_000, 29_860_000]), pages: 2) == .drift(140_000))
        #expect(CaptureBatch.gap(in: result(50_000_000, [20_000_000, 29_860_000]), pages: 1) == .missing(140_000))
        #expect(CaptureBatch.Gap.fees(1).isExplainable && CaptureBatch.Gap.deposit(1).isExplainable)
        #expect(!CaptureBatch.Gap.drift(1).isExplainable && !CaptureBatch.Gap.missing(1).isExplainable)
    }
}
