import Foundation
import Testing
@testable import Core

@Suite("ChangeAttribution — 적립분과 수익분")
struct ChangeAttributionTests {

    private func krw(_ value: Int) -> Money { Money(minorUnits: value, currency: .krw) }

    // 기댓값은 파이썬으로 따로 계산했다: 4,100,000 × 7 / 30.4375 = 942,915.8 → 942,916
    @Test("한 주치 적립을 날수로 비례해 깐다")
    func oneWeek() {
        let split = ChangeAttribution.estimate(from: krw(300_000_000), to: krw(312_300_000),
                                               monthlyContribution: krw(4_100_000), days: 7)
        #expect(split.change.minorUnits == 12_300_000)
        #expect(split.contributed.minorUnits == 942_916)
        #expect(split.gained.minorUnits == 11_357_084)
    }

    // 4,100,000 × 31 / 30.4375 = 4,175,770.0 → 4,175,770
    @Test("한 달(31일)은 월 적립보다 조금 크다")
    func oneMonth() {
        let split = ChangeAttribution.estimate(from: krw(0), to: krw(0),
                                               monthlyContribution: krw(4_100_000), days: 31)
        #expect(split.contributed.minorUnits == 4_175_770)
        #expect(split.gained.minorUnits == -4_175_770)
    }

    // 4,100,000 × 100 / 30.4375 = 13,470,225.9 → 13,470,226 + 70,000,000
    @Test("목돈은 날짜대로 그대로 더한다")
    func lumpSum() {
        let split = ChangeAttribution.estimate(from: krw(100), to: krw(100),
                                               monthlyContribution: krw(4_100_000), days: 100,
                                               lumpSums: krw(70_000_000))
        #expect(split.contributed.minorUnits == 83_470_226)
    }

    @Test("날수가 0 이거나 음수면 적립은 0")
    func zeroDays() {
        #expect(ChangeAttribution.estimate(from: krw(1), to: krw(2), monthlyContribution: krw(4_100_000), days: 0).contributed.isZero)
        #expect(ChangeAttribution.estimate(from: krw(1), to: krw(2), monthlyContribution: krw(4_100_000), days: -3).contributed.isZero)
    }
}
