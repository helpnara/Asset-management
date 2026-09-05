import Foundation
import Testing
@testable import Core

@Suite("Money — 통화 최소 단위 정수 표현")
struct MoneyTests {

    @Test("원화는 최소 단위가 1원이라 입력값이 그대로 정수로 남는다")
    func krwKeepsWholeWon() {
        let money = Money(302_731_078, currency: .krw)
        #expect(money.minorUnits == 302_731_078)
        #expect(money.amount == Decimal(302_731_078))
    }

    @Test("달러는 센트 단위로 저장된다")
    func usdStoresCents() {
        let money = Money(Decimal(string: "1234.56")!, currency: .usd)
        #expect(money.minorUnits == 123_456)
        #expect(money.amount == Decimal(string: "1234.56")!)
    }

    @Test("30년치 복리를 곱해도 오차가 누적되지 않는다")
    func compoundingStaysExact() {
        // 연 8%를 30번 곱한다. Double이면 여기서 오차가 보인다.
        var money = Money(100_000_000, currency: .krw)
        let growth = Decimal(string: "1.08")!
        for _ in 0..<30 {
            money = money.scaled(by: growth)
        }
        // 매 단계 반올림한 결과. 반올림 없는 이론값(1,006,265,689)과 5원 차이가 나는데,
        // 이 5원이 정확히 우리가 통제하려는 누적 오차다.
        #expect(money.minorUnits == 1_006_265_694)
    }

    @Test("합산은 통화가 같을 때만 성립한다")
    func summing() {
        let holdings = [
            Money(50_852_205, currency: .krw),
            Money(28_038_392, currency: .krw),
            Money(24_096_260, currency: .krw),
        ]
        #expect(holdings.total(in: .krw).minorUnits == 102_986_857)
        #expect([Money].init().total(in: .krw) == Money.zero(.krw))
    }

    @Test("뺄셈으로 부채와 증감을 표현한다")
    func subtraction() {
        let assets = Money(302_731_078, currency: .krw)
        let lastWeek = Money(293_421_078, currency: .krw)
        #expect((assets - lastWeek).minorUnits == 9_310_000)
        #expect((lastWeek - assets).isNegative)
    }

    @Test("비중은 0으로 나누지 않는다")
    func share() {
        let total = Money(200_000_000, currency: .krw)
        let position = Money(9_200_000, currency: .krw)
        #expect(position.share(of: total) == Decimal(string: "0.046")!)
        #expect(position.share(of: .zero(.krw)) == nil)
    }

    @Test("환산은 명시적으로만 일어난다")
    func conversion() {
        let usd = Money(Decimal(string: "1000.00")!, currency: .usd)
        let krw = usd.converted(to: .krw, rate: Decimal(1350))
        #expect(krw.currency == .krw)
        #expect(krw.minorUnits == 1_350_000)
        #expect(usd.converted(to: .usd, rate: Decimal(2)) == usd)
    }

    @Test("반올림 정책은 은행가 반올림이 기본이다")
    func bankersRounding() {
        // 0.5는 짝수 쪽으로 — 반복 계산에서 한쪽으로 치우치지 않는다.
        #expect(Money(Decimal(string: "2.5")!, currency: .krw).minorUnits == 2)
        #expect(Money(Decimal(string: "3.5")!, currency: .krw).minorUnits == 4)
        #expect(Money(Decimal(string: "2.5")!, currency: .krw, rounding: .up).minorUnits == 3)
    }
}

@Suite("Quantity — 소수점 8자리 고정 스케일")
struct QuantityTests {

    @Test("정수 주식 수량")
    func shares() {
        let quantity = Quantity(102)
        #expect(quantity.scaled == 10_200_000_000)
        #expect(quantity.value == Decimal(102))
    }

    @Test("암호화폐 소수 수량이 손실 없이 보존된다")
    func satoshi() {
        let quantity = Quantity(Decimal(string: "0.00000001")!)
        #expect(quantity.scaled == 1)
        #expect(quantity.value == Decimal(string: "0.00000001")!)
    }

    @Test("수량 × 단가 = 평가액")
    func valuation() {
        let quantity = Quantity(102)
        let price = Money(255_538, currency: .krw)
        #expect(quantity.value(atUnitPrice: price).minorUnits == 26_064_876)
    }
}

@Suite("Ratio — basis point 정수")
struct RatioTests {

    @Test("연 8% 기대수익률")
    func expectedReturn() {
        let ratio = Ratio(basisPoints: 800)
        #expect(ratio.percent == Decimal(8))
        #expect(ratio.fraction == Decimal(string: "0.08")!)
    }

    @Test("퍼센트 입력을 basis point로 받는다")
    func fromPercent() {
        #expect(Ratio(percent: Decimal(string: "4.6")!).basisPoints == 460)
        #expect(Ratio(percent: Decimal(100)) == .one)
    }
}
