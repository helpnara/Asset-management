import Foundation
import Testing
@testable import Core

@Suite("KoreanAmountFormatter — 화면 표기 규칙")
struct KoreanAmountFormatterTests {

    private func krw(_ value: Int) -> Money { Money(value, currency: .krw) }

    @Test("표 안의 상세는 원 단위로 적는다")
    func full() {
        #expect(KoreanAmountFormatter.full(krw(302_731_078)) == "302,731,078원")
        #expect(KoreanAmountFormatter.full(krw(0)) == "0원")
        #expect(KoreanAmountFormatter.full(krw(-390_000)) == "-390,000원")
    }

    @Test("큰 금액은 억 + 만으로 축약한다")
    func abbreviated() {
        #expect(KoreanAmountFormatter.abbreviated(krw(302_731_078)) == "3억 273만")
        #expect(KoreanAmountFormatter.abbreviated(krw(253_100_000)) == "2억 5,310만")
        #expect(KoreanAmountFormatter.abbreviated(krw(15_310_000)) == "1,531만")
        #expect(KoreanAmountFormatter.abbreviated(krw(2_000_000)) == "200만")
        #expect(KoreanAmountFormatter.abbreviated(krw(100_000_000)) == "1억")
        #expect(KoreanAmountFormatter.abbreviated(krw(8_200)) == "8,200원")
    }

    @Test("차트와 로드맵은 한 단위로만 줄인다")
    func compact() {
        #expect(KoreanAmountFormatter.compact(krw(302_731_078)) == "3.0억")
        #expect(KoreanAmountFormatter.compact(krw(5_910_000_000)) == "59.1억")
        #expect(KoreanAmountFormatter.compact(krw(253_100_000)) == "2.5억")
        #expect(KoreanAmountFormatter.compact(krw(15_310_000)) == "1,531만")
        #expect(KoreanAmountFormatter.compact(krw(8_200)) == "8,200원")
    }

    @Test("증감은 양수에도 부호를 붙인다")
    func signedDelta() {
        #expect(KoreanAmountFormatter.abbreviated(krw(9_310_000), suffix: "원", sign: .always) == "+931만원")
        #expect(KoreanAmountFormatter.abbreviated(krw(-390_000), suffix: "원", sign: .always) == "-39만원")
        #expect(KoreanAmountFormatter.abbreviated(krw(0), sign: .always) == "0원")
    }

    @Test("자릿수 구분")
    func grouping() {
        #expect(KoreanAmountFormatter.grouped(0) == "0")
        #expect(KoreanAmountFormatter.grouped(999) == "999")
        #expect(KoreanAmountFormatter.grouped(1_000) == "1,000")
        #expect(KoreanAmountFormatter.grouped(1_234_567) == "1,234,567")
        #expect(KoreanAmountFormatter.grouped(-1_234_567) == "-1,234,567")
    }
}

@Suite("PercentFormatter — 비중 표기")
struct PercentFormatterTests {

    @Test("소수 첫째 자리까지 적는다")
    func oneDecimal() {
        #expect(PercentFormatter.oneDecimal(Decimal(string: "0.702")!) == "70.2")
        #expect(PercentFormatter.oneDecimal(Decimal(string: "0.298")!) == "29.8")
        #expect(PercentFormatter.oneDecimal(0) == "0.0")
        #expect(PercentFormatter.oneDecimal(1) == "100.0")
    }

    @Test("나누어떨어지지 않는 비중도 0.0 이 되지 않는다")
    func repeatingDecimal() {
        // 실제로 이 경우에 화면이 "한국 0.0 / 미국 0.0" 으로 나왔다.
        let korea = Decimal(63_900_000) / Decimal(142_050_000)   // 0.449841…
        let usa = Decimal(78_150_000) / Decimal(142_050_000)     // 0.550158…
        #expect(PercentFormatter.oneDecimal(korea) == "45.0")
        #expect(PercentFormatter.oneDecimal(usa) == "55.0")
    }

    @Test("아주 작은 비중은 0.0 으로 내려간다")
    func tiny() {
        #expect(PercentFormatter.oneDecimal(Decimal(string: "0.0004")!) == "0.0")
        #expect(PercentFormatter.oneDecimal(Decimal(string: "0.0006")!) == "0.1")
    }
}
