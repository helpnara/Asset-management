import Foundation
import Testing
@testable import Core

/// 1페이지에 실을 운용 원칙의 주 단위 회전 (docs/08-feedback.md 24번).
///
/// **기댓값은 파이썬으로 따로 계산해 대조했다** (CLAUDE.md 규칙).
/// 기준 주(1969-12-27 토요일)에서 2026-09-05 토요일까지 20,706일 = 2,958주.
@Suite("PrincipleRotation — 주마다 도는 다섯 개")
struct PrincipleRotationTests {

    /// 표준시가 결과를 흔들지 않게 못 박는다.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    @Test("같은 점검 주 안에서는 늘 같은 다섯 개")
    func stableWithinAWeek() {
        // 토요일(9/5) · 월요일(9/7) · 금요일(9/11) 은 같은 점검 주다.
        let saturday = PrincipleRotation.indices(count: 16, take: 5, on: date(2026, 9, 5), calendar: calendar)
        let monday = PrincipleRotation.indices(count: 16, take: 5, on: date(2026, 9, 7), calendar: calendar)
        let friday = PrincipleRotation.indices(count: 16, take: 5, on: date(2026, 9, 11), calendar: calendar)
        #expect(saturday == monday)
        #expect(monday == friday)
        // 파이썬 대조: 2958주 × 5 = 14790, 14790 % 16 = 6
        #expect(saturday == [6, 7, 8, 9, 10])
    }

    @Test("주가 바뀌면 다음 다섯 개로 넘어간다")
    func advancesNextWeek() {
        let thisWeek = PrincipleRotation.indices(count: 16, take: 5, on: date(2026, 9, 7), calendar: calendar)
        let nextWeek = PrincipleRotation.indices(count: 16, take: 5, on: date(2026, 9, 12), calendar: calendar)
        #expect(thisWeek == [6, 7, 8, 9, 10])
        #expect(nextWeek == [11, 12, 13, 14, 15])
    }

    @Test("끝을 넘으면 앞으로 돌아온다")
    func wrapsAround() {
        // 주마다 시작점이 5씩 밀리므로 16을 넘는 주가 반드시 나온다.
        // 그 주에도 성질이 지켜지는지 본다 — 언제나 다섯 개이고, 전부 범위
        // 안이고, 한 주 안에서 겹치지 않는다.
        for week in 0..<40 {
            let day = calendar.date(byAdding: .day, value: 7 * week, to: date(2026, 9, 5)) ?? .now
            let picked = PrincipleRotation.indices(count: 16, take: 5, on: day, calendar: calendar)
            #expect(picked.count == 5)
            #expect(Set(picked).count == 5)
            #expect(picked.allSatisfy { (0..<16).contains($0) })
        }
    }

    @Test("한 바퀴를 돌면 뒤에 적은 원칙도 종이에 오른다")
    func everyPrincipleGetsItsTurn() {
        // 앞의 다섯 개 고정보다 나은 점이 이것이다. 16개에서 5개씩이면
        // gcd(16,5)=1 이라 16주면 전부 한 번씩은 실린다.
        var seen = Set<Int>()
        for week in 0..<16 {
            let day = calendar.date(byAdding: .day, value: 7 * week, to: date(2026, 9, 5)) ?? .now
            seen.formUnion(PrincipleRotation.indices(count: 16, take: 5, on: day, calendar: calendar))
        }
        #expect(seen == Set(0..<16))
    }

    @Test("개수가 적으면 돌리지 않고 전부 싣는다")
    func showsAllWhenFew() {
        #expect(PrincipleRotation.indices(count: 5, take: 5, on: date(2026, 9, 7), calendar: calendar) == [0, 1, 2, 3, 4])
        #expect(PrincipleRotation.indices(count: 3, take: 5, on: date(2026, 9, 7), calendar: calendar) == [0, 1, 2])
        #expect(PrincipleRotation.indices(count: 0, take: 5, on: date(2026, 9, 7), calendar: calendar).isEmpty)
    }

    @Test("기준 주 이전이어도 자리 번호가 범위를 벗어나지 않는다")
    func handlesDatesBeforeEpoch() {
        // 나머지 연산이 음수를 내면 배열 밖을 가리킨다. 접어 두었는지 본다.
        let picked = PrincipleRotation.indices(count: 16, take: 5, on: date(1969, 12, 26), calendar: calendar)
        #expect(picked.count == 5)
        #expect(picked.allSatisfy { (0..<16).contains($0) })
        // 파이썬 대조: -1주 → (-5 % 16 + 16) % 16 = 11
        #expect(picked == [11, 12, 13, 14, 15])
    }

    @Test("주차는 기준 주에서 센다")
    func weekIndexIsCountedFromEpoch() {
        #expect(PrincipleRotation.weekIndex(for: date(1969, 12, 27), calendar: calendar) == 0)
        #expect(PrincipleRotation.weekIndex(for: date(1970, 1, 3), calendar: calendar) == 1)
        #expect(PrincipleRotation.weekIndex(for: date(2026, 9, 5), calendar: calendar) == 2_958)
    }
}
