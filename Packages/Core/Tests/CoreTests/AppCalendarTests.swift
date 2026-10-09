import Foundation
import Testing
@testable import Core

/// 기기 달력 설정과 상관없이 연도를 그레고리력으로 센다 (docs/08-feedback.md 194번 D2).
@Suite("Calendar.app — 언제나 그레고리력")
struct AppCalendarTests {

    /// 2026-10-09 12:00 UTC. 어느 시간대에서 봐도 같은 해 · 같은 달이다.
    private let day = Date(timeIntervalSince1970: 1_791_547_200)

    @Test func isGregorian() {
        #expect(Calendar.app.identifier == .gregorian)
    }

    @Test func yearIsGregorianYear() {
        #expect(Calendar.app.component(.year, from: day) == 2026)
        #expect(Calendar.app.component(.month, from: day) == 10)
    }

    /// 왜 필요했나 — 기기 달력이 이것들이면 `Calendar.current` 의 올해가 이렇게 나온다.
    /// 일본력의 `8` 은 `1930...올해` 를 거꾸로 만들어 구성원 편집 화면에서 앱을 죽였다.
    @Test func deviceCalendarsWouldDisagree() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TimeZone(identifier: "UTC")!
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "UTC")!
        #expect(japanese.component(.year, from: day) == 8)       // 레이와 8년
        #expect(buddhist.component(.year, from: day) == 2569)    // 불기 2569년
    }

    @Test func birthYearRangeIsNeverEmpty() {
        let thisYear = Calendar.app.component(.year, from: day)
        #expect(thisYear >= 1930)
        #expect(!(1930...thisYear).isEmpty)
    }
}
