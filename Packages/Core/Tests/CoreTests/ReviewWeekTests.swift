import Foundation
import Testing
@testable import Core

@Suite("ReviewWeek — 토요일 기준 주차")
struct ReviewWeekTests {

    /// 테스트가 실행 환경의 시간대에 흔들리지 않도록 고정한다.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)!
    }

    @Test("토요일부터 다음 금요일까지가 한 점검 주기다")
    func anchor() {
        let saturday = date("2027-03-13")
        #expect(ReviewWeek.anchor(for: saturday, calendar: calendar) == saturday)
        // 일요일에 밀려서 적어도 그 주 토요일 기록이 된다
        #expect(ReviewWeek.anchor(for: date("2027-03-14"), calendar: calendar) == saturday)
        #expect(ReviewWeek.anchor(for: date("2027-03-17"), calendar: calendar) == saturday)
        #expect(ReviewWeek.anchor(for: date("2027-03-19"), calendar: calendar) == saturday)
        // 다음 토요일부터는 새 주기
        #expect(ReviewWeek.anchor(for: date("2027-03-20"), calendar: calendar) == date("2027-03-20"))
    }

    @Test("다음 점검일은 항상 다음 토요일이다")
    func nextSaturday() {
        #expect(ReviewWeek.nextSaturday(after: date("2027-03-13"), calendar: calendar) == date("2027-03-20"))
        #expect(ReviewWeek.nextSaturday(after: date("2027-03-17"), calendar: calendar) == date("2027-03-20"))
    }

    @Test("점검일까지 남은 일수")
    func daysUntil() {
        #expect(ReviewWeek.daysUntilReview(from: date("2027-03-13"), calendar: calendar) == 0)  // 토
        #expect(ReviewWeek.daysUntilReview(from: date("2027-03-14"), calendar: calendar) == 6)  // 일
        #expect(ReviewWeek.daysUntilReview(from: date("2027-03-18"), calendar: calendar) == 2)  // 목
        #expect(ReviewWeek.daysUntilReview(from: date("2027-03-19"), calendar: calendar) == 1)  // 금
    }

    @Test("연속 기록은 끊긴 주에서 멈춘다")
    func streak() {
        // 2026.12.19 부터 2027.03.13 까지 13주 연속
        let anchors = (0..<13).map {
            calendar.date(byAdding: .day, value: -7 * $0, to: date("2027-03-13"))!
        }
        #expect(ReviewWeek.streak(completedAnchors: anchors, asOf: date("2027-03-13"), calendar: calendar) == 13)

        // 4주 전을 빼면 거기서 끊긴다
        let withGap = anchors.filter { $0 != calendar.date(byAdding: .day, value: -28, to: date("2027-03-13"))! }
        #expect(ReviewWeek.streak(completedAnchors: withGap, asOf: date("2027-03-13"), calendar: calendar) == 4)
    }

    @Test("이번 주를 아직 안 했다고 연속 기록을 0으로 만들지 않는다")
    func doesNotPunishBeforeSaturday() {
        // 지난 주까지 12주 연속. 이번 주 토요일은 아직 오지 않았다.
        let anchors = (1...12).map {
            calendar.date(byAdding: .day, value: -7 * $0, to: date("2027-03-13"))!
        }
        #expect(ReviewWeek.streak(completedAnchors: anchors, asOf: date("2027-03-13"), calendar: calendar) == 12)
        #expect(ReviewWeek.streak(completedAnchors: anchors, asOf: date("2027-03-17"), calendar: calendar) == 12)
    }

    @Test("두 주 넘게 밀리면 연속 기록이 끊긴다")
    func brokenAfterTwoWeeks() {
        let anchors = [date("2027-02-20"), date("2027-02-13")]
        // 2027-03-13 기준으로 보면 지난 주(03-06)도 그 전(02-27)도 비어 있다
        #expect(ReviewWeek.streak(completedAnchors: anchors, asOf: date("2027-03-13"), calendar: calendar) == 0)
    }

    @Test("기록이 하나도 없으면 0이다")
    func empty() {
        #expect(ReviewWeek.streak(completedAnchors: [], asOf: date("2027-03-13"), calendar: calendar) == 0)
    }
}
