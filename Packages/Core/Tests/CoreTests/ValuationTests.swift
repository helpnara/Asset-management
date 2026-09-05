import Foundation
import Testing
@testable import Core

@Suite("Valuation — 현황판 합계")
struct ValuationTests {

    private let dad = UUID()
    private let son = UUID()
    private let brokerage = UUID()
    private let lease = UUID()
    private let loan = UUID()

    private func krw(_ value: Int) -> Money { Money(value, currency: .krw) }

    /// 아빠: 미국 ETF 6,000만 · 전세보증금 1억 · 마이너스통장 500만
    /// 아들: 국내 주식 2,000만
    private var family: [Position] {
        [
            Position(memberID: dad, accountID: brokerage, assetClass: .equity,
                     countryCode: "US", value: krw(60_000_000),
                     isLiability: false, countsAsInvestable: true),
            Position(memberID: dad, accountID: lease, assetClass: .realEstate,
                     countryCode: "KR", value: krw(100_000_000),
                     isLiability: false, countsAsInvestable: false),
            Position(memberID: dad, accountID: loan, assetClass: .cash,
                     countryCode: "KR", value: krw(5_000_000),
                     isLiability: true, countsAsInvestable: false),
            Position(memberID: son, accountID: brokerage, assetClass: .equity,
                     countryCode: "KR", value: krw(20_000_000),
                     isLiability: false, countsAsInvestable: true),
        ]
    }

    @Test("순자산은 자산에서 부채를 뺀 값이다")
    func netWorth() {
        let rollup = Valuation.rollUp(family, base: .krw)
        #expect(rollup.assets == krw(180_000_000))
        #expect(rollup.liabilities == krw(5_000_000))
        #expect(rollup.netWorth == krw(175_000_000))
    }

    @Test("투자자산에는 전세보증금과 부채가 들어가지 않는다")
    func investableExcludesPropertyAndDebt() {
        let rollup = Valuation.rollUp(family, base: .krw)
        #expect(rollup.investable == krw(80_000_000))
    }

    @Test("구성원별 합계는 그 사람의 부채를 음수로 반영한다")
    func perMember() {
        let rollup = Valuation.rollUp(family, base: .krw)
        #expect(rollup.byMember[dad] == krw(155_000_000))
        #expect(rollup.byMember[son] == krw(20_000_000))
    }

    @Test("자산군 배분은 부동산까지 포함한다 — 배분 도넛에 보여야 하므로")
    func byAssetClass() {
        let rollup = Valuation.rollUp(family, base: .krw)
        #expect(rollup.byAssetClass[.equity] == krw(80_000_000))
        #expect(rollup.byAssetClass[.realEstate] == krw(100_000_000))
        #expect(rollup.byAssetClass[.cash] == nil)   // 부채는 자산군에 넣지 않는다
    }

    @Test("국가 비중은 투자자산만 기준으로 센다")
    func countryWeightsUseInvestableOnly() {
        let rollup = Valuation.rollUp(family, base: .krw)
        // 보증금 1억이 KR 로 들어가면 분자가 분모보다 커져 비중이 100%를 넘는다.
        #expect(rollup.byCountry["KR"] == krw(20_000_000))
        #expect(rollup.byCountry["US"] == krw(60_000_000))
        #expect(rollup.countryShare("US") == Decimal(string: "0.75")!)
        #expect(rollup.countryShare("KR") == Decimal(string: "0.25")!)
        #expect(rollup.countryShare("JP") == 0)
    }

    @Test("비어 있는 포트폴리오도 무너지지 않는다")
    func empty() {
        let rollup = Valuation.rollUp([], base: .krw)
        #expect(rollup.netWorth == Money.zero(.krw))
        #expect(rollup.investable == Money.zero(.krw))
        #expect(rollup.byMember.isEmpty)
        #expect(rollup.countryShare("KR") == nil)   // 0으로 나누지 않는다
    }
}
