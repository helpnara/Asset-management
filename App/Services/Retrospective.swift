import Core
import CoreData
import Foundation

/// **월간 · 연간 회고** (docs/08-feedback.md 86 · 87번, C4 · C5).
///
/// 매주 점검의 보상이 한 달 단위로도 있어야 계속 쓴다. 한 달(또는 한 해)의
/// 기록을 한 번에 읽어 값 하나로 만든다 — 화면과 그림(공유용)이 같은 값을 쓴다.
/// 관리 객체는 여기서 끝난다. 나가는 것은 값뿐이다.
enum Retrospective {

    enum Scope: String, CaseIterable, Identifiable, Sendable {
        case month = "월간"
        case year = "연간"
        var id: String { rawValue }
    }

    struct Period: Hashable, Sendable {
        let scope: Scope
        /// 시작(포함) — 그 달 1일 또는 그 해 1월 1일.
        let start: Date
        /// 끝(제외) — 다음 달 1일 또는 다음 해 1월 1일.
        let end: Date

        var title: String {
            let calendar = Calendar.current
            let year = calendar.component(.year, from: start)
            switch scope {
            case .month: return "\(year)년 \(calendar.component(.month, from: start))월"
            case .year: return "\(year)년"
            }
        }

        /// 오늘이 속한 기간에서 `offset` 만큼 앞뒤로.
        static func containing(_ date: Date, scope: Scope, offset: Int = 0,
                               calendar: Calendar = .current) -> Period {
            let component: Calendar.Component = scope == .month ? .month : .year
            let parts: Set<Calendar.Component> = scope == .month ? [.year, .month] : [.year]
            let base = calendar.date(from: calendar.dateComponents(parts, from: date)) ?? date
            let start = calendar.date(byAdding: component, value: offset, to: base) ?? base
            let end = calendar.date(byAdding: component, value: 1, to: start) ?? start
            return Period(scope: scope, start: start, end: end)
        }

        func shifted(by delta: Int, calendar: Calendar = .current) -> Period {
            Period.containing(start, scope: scope, offset: delta, calendar: calendar)
        }

        /// 오늘을 포함하거나 지난 기간인가. 미래는 회고할 것이 없다.
        func isCurrent(asOf date: Date = .now) -> Bool { start <= date && date < end }
        func isFuture(asOf date: Date = .now) -> Bool { start > date }
    }

    struct MemberLine: Identifiable, Hashable, Sendable {
        let id: UUID
        let name: String
        let colorIndex: Int
        let start: Money?
        let end: Money?
        /// 그 기간에 제 몫을 적은 주.
        let enteredWeeks: Int

        var change: Money? {
            guard let start, let end else { return nil }
            return end - start
        }
    }

    struct Summary: Hashable, Sendable {
        let period: Period
        /// 시작 기준 스냅샷의 주차와 값 (기간 앞의 마지막 기록).
        let baseAnchor: Date?
        let baseTotal: Money?
        /// 기간 안의 마지막 기록.
        let endAnchor: Date?
        let endTotal: Money?
        let attribution: ChangeAttribution?
        /// 기간 안의 토요일 수 (오늘까지) / 끝낸 주 / 총액만 적은 주.
        let weeksInPeriod: Int
        let reviewedWeeks: Int
        let totalOnlyWeeks: Int
        let members: [MemberLine]
        let planGapText: String?
        let planGapIsAhead: Bool
        let diaryDays: Int
        let structureChanges: Int
        let planChanges: Int
        let milestones: [String]

        var hasRecords: Bool { endTotal != nil }
    }

    // MARK: - 계산

    @MainActor
    static func summarize(
        period: Period,
        snapshots: [Snapshot],
        sessions: [ReviewSession],
        members: [Member],
        plan: Plan?,
        cashEvents: [CashEvent],
        incomes: [IncomeStream],
        diary: [DiaryEntry],
        logs: [ChangeLog],
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> Summary {
        let sorted = snapshots.sorted { $0.weekAnchor < $1.weekAnchor }
        let base = sorted.last { $0.weekAnchor < period.start }
        let last = sorted.last { $0.weekAnchor >= period.start && $0.weekAnchor < period.end }

        var attribution: ChangeAttribution?
        if let base, let last, let plan {
            let days = calendar.dateComponents([.day], from: base.weekAnchor, to: last.weekAnchor).day ?? 0
            let lumps = cashEvents
                .filter { $0.date > base.weekAnchor && $0.date <= last.weekAnchor }
                .reduce(Money.zero(.krw)) { $0 + $1.amount }
            attribution = ChangeAttribution.estimate(
                from: Money(minorUnits: base.netWorthMinor, currency: .krw),
                to: Money(minorUnits: last.netWorthMinor, currency: .krw),
                monthlyContribution: plan.effectiveMonthlyContribution(members: members),
                days: days, lumpSums: lumps)
        }

        // 기간 안의 토요일 — 오늘까지만. 아직 안 온 주를 빠뜨렸다고 세지 않는다.
        var weeks = 0
        var cursor = ReviewWeek.anchor(for: period.start, calendar: calendar)
        if cursor < period.start { cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? cursor }
        let cap = min(period.end, now)
        while cursor < cap {
            weeks += 1
            cursor = calendar.date(byAdding: .day, value: 7, to: cursor) ?? cap
        }
        let inPeriod = sessions.filter { $0.isComplete && $0.weekAnchor >= period.start && $0.weekAnchor < period.end }

        let lines = members.map { member -> MemberLine in
            func value(_ snapshot: Snapshot?) -> Money? {
                snapshot?.sortedLines.first { $0.memberID == member.id }
                    .map { Money(minorUnits: $0.valueMinor, currency: .krw) }
            }
            return MemberLine(
                id: member.id,
                name: member.name.isEmpty ? "이름 없음" : member.name,
                colorIndex: member.colorIndex,
                start: value(base), end: value(last),
                enteredWeeks: inPeriod.filter { $0.enteredMemberIDSet.contains(member.id) }.count)
        }

        var gapText: String?
        var gapAhead = false
        if let last {
            let projection = PlanTrack.projection(plan: plan, snapshots: snapshots, cashEvents: cashEvents,
                                                  incomes: incomes, members: members)
            if let gap = PlanTrack.gap(projection, actual: Money(minorUnits: last.netWorthMinor, currency: .krw),
                                       at: last.weekAnchor) {
                gapText = gap.text
                gapAhead = gap.isAhead
            }
        }

        let diaryDays = diary.filter {
            $0.day >= period.start && $0.day < period.end
                && !($0.goal.isEmpty && $0.result.isEmpty && $0.gratitude.isEmpty)
        }.count
        let periodLogs = logs.filter { $0.at >= period.start && $0.at < period.end }

        return Summary(
            period: period,
            baseAnchor: base?.weekAnchor,
            baseTotal: base.map { Money(minorUnits: $0.netWorthMinor, currency: .krw) },
            endAnchor: last?.weekAnchor,
            endTotal: last.map { Money(minorUnits: $0.netWorthMinor, currency: .krw) },
            attribution: attribution,
            weeksInPeriod: weeks,
            reviewedWeeks: inPeriod.count,
            totalOnlyWeeks: inPeriod.filter(\.isTotalOnly).count,
            members: lines,
            planGapText: gapText,
            planGapIsAhead: gapAhead,
            diaryDays: diaryDays,
            structureChanges: periodLogs.filter { $0.kind == .structure }.count,
            planChanges: periodLogs.filter { $0.kind == .planValue }.count,
            milestones: periodLogs.filter { $0.kind == .milestone }.sorted { $0.at < $1.at }.map(\.subject)
        )
    }
}
