import Foundation
import Testing
@testable import Core

@Suite("DiaryStreak — 일기 연속 일수")
struct DiaryStreakTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    @Test("오늘까지 이어졌으면 오늘을 포함해 센다")
    func throughToday() {
        let days = [date("2026-09-08 21:10"), date("2026-09-09 07:00"), date("2026-09-10 22:30")]
        #expect(DiaryStreak.count(days: days, asOf: date("2026-09-10 23:00"), calendar: calendar) == 3)
    }

    @Test("오늘 아직 안 적었으면 어제까지의 수를 그대로 둔다")
    func notYetToday() {
        let days = [date("2026-09-08 21:10"), date("2026-09-09 07:00")]
        #expect(DiaryStreak.count(days: days, asOf: date("2026-09-10 08:00"), calendar: calendar) == 2)
    }

    @Test("하루 비면 끊긴다")
    func gapBreaks() {
        // 8일과 10일만 — 9일이 비었으니 오늘(10일) 하루뿐
        let days = [date("2026-09-08 21:10"), date("2026-09-10 22:30")]
        #expect(DiaryStreak.count(days: days, asOf: date("2026-09-10 23:00"), calendar: calendar) == 1)
        // 그제까지만 있으면 어제가 비어 0
        #expect(DiaryStreak.count(days: [date("2026-09-08 21:10")],
                                  asOf: date("2026-09-10 23:00"), calendar: calendar) == 0)
        #expect(DiaryStreak.count(days: [], asOf: date("2026-09-10 23:00"), calendar: calendar) == 0)
    }
}
