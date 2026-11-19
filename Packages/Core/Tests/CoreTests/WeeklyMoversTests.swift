import Foundation
import Testing
@testable import Core

@Suite("WeeklyMovers — 이번 주 많이 움직인 종목 (219번 E)")
struct WeeklyMoversTests {

    private func krw(_ value: Int) -> Money { Money(minorUnits: value, currency: .krw) }

    private let ids = (0..<9).map { _ in UUID() }

    private func entry(_ index: Int, _ name: String, _ value: Int) -> WeeklyMovers.Entry {
        .init(id: ids[index], name: name, detail: "", value: krw(value))
    }

    // 증감은 손으로 셈: A +50 · B −20 · C 0 · D 새 종목 · E +100 · F −200 · G +1 · H −1 · I +30
    @Test("오른 것 위 셋 · 내린 것 아래 셋, 새 종목과 그대로인 종목은 뺀다")
    func picksTopThree() {
        let current = [entry(0, "A", 150), entry(1, "B", 180), entry(2, "C", 50), entry(3, "D", 999),
                       entry(4, "E", 110), entry(5, "F", 100), entry(6, "G", 6), entry(7, "H", 6),
                       entry(8, "I", 40)]
        let previous: [UUID: Money] = [ids[0]: krw(100), ids[1]: krw(200), ids[2]: krw(50),
                                       ids[4]: krw(10), ids[5]: krw(300), ids[6]: krw(5),
                                       ids[7]: krw(7), ids[8]: krw(10)]
        let result = WeeklyMovers.top(current: current, previous: previous)
        #expect(result.gains.map(\.name) == ["E", "A", "I"])
        #expect(result.gains.map(\.delta.minorUnits) == [100, 50, 30])
        #expect(result.losses.map(\.name) == ["F", "B", "H"])
        #expect(result.losses.map(\.delta.minorUnits) == [-200, -20, -1])
    }

    @Test("같은 크기면 이름 순")
    func tieBreaksByName() {
        let current = [entry(0, "나", 20), entry(1, "가", 20), entry(2, "다", 0), entry(3, "라", 0)]
        let previous: [UUID: Money] = [ids[0]: krw(10), ids[1]: krw(10), ids[2]: krw(10), ids[3]: krw(10)]
        let result = WeeklyMovers.top(current: current, previous: previous)
        #expect(result.gains.map(\.name) == ["가", "나"])
        #expect(result.losses.map(\.name) == ["다", "라"])
    }

    // 대출 잔액 1,000 → 900 은 부르는 쪽이 −1,000 → −900 으로 넘긴다 — 순자산 +100.
    @Test("부채는 부호를 뒤집어 넘기면 갚은 만큼 오른 쪽에 선다")
    func liabilityPaidDownIsGain() {
        let current = [entry(0, "대출", -900)]
        let previous: [UUID: Money] = [ids[0]: krw(-1_000)]
        let result = WeeklyMovers.top(current: current, previous: previous)
        #expect(result.gains.map(\.delta.minorUnits) == [100])
        #expect(result.losses.isEmpty)
    }

    @Test("지난 기록이 없으면 비어 있다")
    func emptyWithoutPrevious() {
        let result = WeeklyMovers.top(current: [entry(0, "A", 10)], previous: [:])
        #expect(result.isEmpty)
    }
}
