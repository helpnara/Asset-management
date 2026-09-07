import Core
import Foundation
import SwiftData

/// 계획선 — **계획을 세운 날에서 출발해 계획 가정대로 굴린 궤적**
/// (docs/08-feedback.md 37·46번).
///
/// 로드맵 M2 의 완료 기준이 `이번 주 숫자가 계획선 위인지 아래인지 한눈에
/// 보인다` 인데, 예측선은 오늘에서 출발하므로 지난주와 견줄 수 없었다.
///
/// **한 곳에서 계산한다.** 37번에서 현황판에만 붙였다가, 정작 매주 숫자를 적고
/// 나서 보는 점검 완료 화면과 남에게 건네는 1페이지에는 없었다 — 이 저장소가
/// 반복해 온 "만들어 놓고 끝을 안 이은 것" 이다. 세 화면이 같은 함수를 쓰면
/// 그럴 수 없다.
@MainActor
enum PlanTrack {

    /// 계획선이 출발하는 자리 — 계획을 세운 뒤 **처음 적은 주**와 그때 총자산.
    ///
    /// 계획 수립 시점의 자산을 따로 저장하지 않으므로 스냅샷에서 찾는다.
    /// 수립일 이후 첫 기록이 없으면 가장 이른 기록에서 출발한다 — 계획을
    /// 나중에 적었더라도 견줄 선은 있는 편이 낫다.
    static func anchor(plan: Plan?, snapshots: [Snapshot],
                       calendar: Calendar = .current) -> (date: Date, balance: Money)? {
        let sorted = snapshots.sorted { $0.weekAnchor < $1.weekAnchor }
        guard !sorted.isEmpty else { return nil }
        let startedOn = plan?.startedOn.map { calendar.startOfDay(for: $0) }
        let found = startedOn.flatMap { start in sorted.first { $0.weekAnchor >= start } }
            ?? sorted.first
        guard let found else { return nil }
        return (found.weekAnchor, Money(minorUnits: found.netWorthMinor, currency: .krw))
    }

    /// 그 자리에서 계획 가정대로 굴린 궤적.
    ///
    /// **덩어리 구성은 지금 계좌로 나눈다.** 과거의 계좌 구성은 알 수 없기
    /// 때문이다. 그래서 계획선은 "그때 이 구성으로 시작했다면" 이고 완전한
    /// 재현이 아니다 — 그래도 견줄 선이 하나도 없는 것보다 낫다.
    static func projection(plan: Plan?, snapshots: [Snapshot], cashEvents: [CashEvent],
                           incomes: [IncomeStream], members: [Member],
                           calendar: Calendar = .current) -> ProjectionResult? {
        guard let plan, let anchor = anchor(plan: plan, snapshots: snapshots, calendar: calendar)
        else { return nil }
        let input = plan.projectionInput(from: anchor.balance, cashEvents: cashEvents,
                                         incomes: incomes, members: members,
                                         asOf: anchor.date, calendar: calendar)
        return Projection.run(input, calendar: calendar)
    }

    /// 어느 날 계획선이 가리키는 금액.
    ///
    /// **그 날짜 자리**의 값이어야 한다. 연 단위로 읽으면 그 해의 마지막 점,
    /// 즉 12월 값이라 연초에 보면 몇 달치를 앞질러 견주게 된다.
    static func onPlan(_ projection: ProjectionResult, at date: Date,
                       calendar: Calendar = .current) -> Money? {
        let day = calendar.startOfDay(for: date)
        return projection.points.last(where: { $0.date <= day })?.nominal
    }

    /// 계획선과 실제의 차이. 화면이 그대로 적을 수 있는 형태로 돌려준다.
    struct Gap: Sendable {
        let onPlan: Money
        let actual: Money
        let delta: Money
        let isAhead: Bool
        /// `계획보다 2,300만원 앞서 있습니다`
        let text: String
        /// 종이에 적는 짧은 꼴 — `계획 대비 +2,300만`
        let compact: String
    }

    static func gap(_ projection: ProjectionResult?, actual: Money, at date: Date = .now,
                    calendar: Calendar = .current) -> Gap? {
        guard let projection, let onPlan = onPlan(projection, at: date, calendar: calendar)
        else { return nil }
        let delta = actual - onPlan
        // 1% 안쪽이면 "계획대로" 다. 몇십만원 차이에 앞섰다 뒤졌다 하면
        // 그 숫자를 믿지 않게 된다.
        let threshold = max(abs(onPlan.minorUnits) / 100, 1)
        let size = Won.abbreviated(Money(minorUnits: abs(delta.minorUnits), currency: .krw),
                                   suffix: "원")
        if abs(delta.minorUnits) < threshold {
            return Gap(onPlan: onPlan, actual: actual, delta: delta, isAhead: true,
                       text: "계획선 위에 있습니다", compact: "계획대로")
        }
        let ahead = delta.minorUnits > 0
        return Gap(
            onPlan: onPlan, actual: actual, delta: delta, isAhead: ahead,
            text: ahead ? "계획보다 \(size) 앞서 있습니다" : "계획보다 \(size) 뒤에 있습니다",
            compact: "계획 대비 \(ahead ? "+" : "−")\(Won.compact(Money(minorUnits: abs(delta.minorUnits), currency: .krw)))"
        )
    }

    /// 계획을 마지막으로 고친 지 1년이 넘었나 (docs/08-feedback.md 43번).
    ///
    /// 주간 점검은 **숫자를 적는 일**이고, 1년에 한 번은 **가정 자체**를 다시
    /// 봐야 한다 — 기대수익률 · 물가 · 목표 금액 · 연금 예상액. 지금은 그럴
    /// 계기가 없어서, 처음 적은 가정이 20년을 그대로 간다.
    static func yearsSincePlanReview(_ plan: Plan?, asOf: Date = .now,
                                     calendar: Calendar = .current) -> Int? {
        guard let plan else { return nil }
        let last = plan.updatedAt ?? plan.createdAt
        let years = calendar.dateComponents([.year], from: last, to: asOf).year ?? 0
        return years >= 1 ? years : nil
    }
}
