import Foundation
import Testing
@testable import Core

/// 기기 시간대가 달라도 같은 토요일이면 같은 점검 주 (docs/08-feedback.md 194번 D3).
/// 시각은 2026-10-10(토) 자정을 각 시간대에서 잰 값 — 파이썬으로 따로 계산했다.
@Suite("ReviewWeek — 시간대가 달라도 같은 주")
struct ReviewWeekTimeZoneTests {

    private let seoul = Date(timeIntervalSince1970: 1_791_558_000)        // 토 00:00 +09:00
    private let berlinSummer = Date(timeIntervalSince1970: 1_791_583_200) // 토 00:00 +02:00
    private let losAngeles = Date(timeIntervalSince1970: 1_791_615_600)   // 토 00:00 −07:00

    @Test func sameSaturdayAcrossTimeZones() {
        #expect(ReviewWeek.isSameWeek(seoul, berlinSummer))
        #expect(ReviewWeek.isSameWeek(seoul, losAngeles))
        #expect(ReviewWeek.isSameWeek(berlinSummer, losAngeles))
        #expect(ReviewWeek.dayKey(seoul) == 20_736)
    }

    @Test func neighbouringSaturdaysDiffer() {
        let nextWeek = seoul.addingTimeInterval(7 * 86_400)
        let lastWeek = seoul.addingTimeInterval(-7 * 86_400)
        #expect(!ReviewWeek.isSameWeek(seoul, nextWeek))
        #expect(!ReviewWeek.isSameWeek(seoul, lastWeek))
        #expect(ReviewWeek.dayKey(nextWeek) - ReviewWeek.dayKey(seoul) == 7)
    }

    @Test func nearbyRangeHoldsEveryZone() {
        let range = ReviewWeek.nearbyRange(of: seoul)
        for anchor in [seoul, berlinSummer, losAngeles] {
            #expect(anchor > range.lower && anchor < range.upper)
        }
    }
}
