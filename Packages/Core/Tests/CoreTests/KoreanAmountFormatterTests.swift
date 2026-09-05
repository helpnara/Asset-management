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
