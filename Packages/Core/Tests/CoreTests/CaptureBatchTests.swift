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
    @Test("묶기 — 머리 없는 장은 앞 묶음에, 다른 계좌를 가리키면 따로, 겹친 종목은 하나만")
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
        #expect(groups.map(\.pages) == [[0, 1], [2], [3]])
        #expect(groups[0].result.items.map(\.name) == ["가나전자", "다라화학", "마바바이오로직스"])
        #expect(groups[0].result.totalMinor == 6_000_000)
        #expect(groups[0].result.isBalanced == true)
        #expect(groups[1].result.isBalanced == true)
        #expect(groups[2].result.isBalanced == nil)
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
}

