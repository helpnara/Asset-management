import Core
import Foundation
import SwiftData
import SwiftUI

/// 1페이지 한 장을 **한 곳에서** 만든다.
///
/// PDF 로 뽑는 곳(`ExportView`)과 화면으로 미리 보는 곳(`OnePagerPreviewView`)이
/// 각자 만들면 둘이 조용히 어긋난다 — 미리보기에서 한 장에 들어가 보였는데
/// 인쇄하면 넘치는 식이다. 같은 함수를 쓰게 해서 그럴 수 없게 한다.
@MainActor
enum OnePagerBuilder {

    /// 구성원 카드 미니 차트에 세울 막대 수. 로드맵 정거장과 같은 해를 쓴다.
    private static let barLimit = 6

    static func make(
        plan: Plan?,
        members: [Member],
        holdings: [Holding],
        cashEvents: [CashEvent],
        incomes: [IncomeStream],
        principles: [Principle],
        todos: [TodoItem],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> OnePagerView {
        let rollup = Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw)
        let projection = plan?.projection(from: rollup.netWorth, cashEvents: cashEvents,
                                          incomes: incomes, members: members,
                                          calendar: calendar)
        let milestones = projection?.milestones ?? []

        return OnePagerView(
            title: plan?.title ?? "우리 가족 노후자금 준비",
            asOfNote: plan?.asOfNote ?? "",
            startedOn: plan?.startedOn,
            retirementYear: plan?.retirementYear ?? calendar.component(.year, from: today) + 23,
            declaration: plan?.declaration ?? "",
            rollup: rollup,
            members: members,
            milestones: milestones,
            cashEvents: cashEvents.filter { !$0.isAlreadyReflected },
            principles: principles,
            todos: todos,
            usShare: rollup.countryShare("US"),
            krShare: rollup.countryShare("KR"),
            memberSeries: memberSeries(plan: plan, members: members, rollup: rollup,
                                       years: barYears(plan: plan, milestones: milestones,
                                                       today: today, calendar: calendar),
                                       calendar: calendar),
            today: today,
            nextReview: ReviewWeek.nextSaturday(after: today, calendar: calendar)
        )
    }

    /// 미니 차트의 해들 — **로드맵의 정거장과 같은 해**를 쓴다
    /// (docs/08-feedback.md 26번). 1페이지 안에서 위의 로드맵 줄과 아래 카드가
    /// 같은 시간축을 가져야 읽기 쉽다.
    ///
    /// 마일스톤은 달성 여부에 따라 개수가 달라지므로 **지금**과 **은퇴**를
    /// 양 끝에 못 박아 최소 둘은 남게 한다.
    private static func barYears(plan: Plan?, milestones: [Milestone],
                                 today: Date, calendar: Calendar) -> [Int] {
        let thisYear = calendar.component(.year, from: today)
        var years: Set<Int> = [thisYear]
        years.formUnion(milestones.map(\.year))
        if let retirement = plan?.retirementYear { years.insert(retirement) }
        let sorted = years.sorted()
        guard sorted.count > barLimit else { return sorted }
        // 넘치면 가운데를 솎되 양 끝(지금·은퇴)은 남긴다.
        var trimmed = [sorted[0]]
        let middle = sorted.dropFirst().dropLast()
        let step = max(1, middle.count / (barLimit - 2))
        for (offset, year) in middle.enumerated() where offset % step == 0 {
            if trimmed.count < barLimit - 1 { trimmed.append(year) }
        }
        trimmed.append(sorted[sorted.count - 1])
        return trimmed
    }

    /// 사람마다 자기 몫만 굴린다. 수익률·물가 가정은 가구 공통이다 —
    /// `MemberTrajectoryView` 와 같은 계산이라 두 화면의 숫자가 어긋나지 않는다.
    private static func memberSeries(plan: Plan?, members: [Member], rollup: Rollup,
                                     years: [Int], calendar: Calendar) -> [OnePagerView.MemberSeries] {
        guard let plan, years.count > 1 else { return [] }
        let now = calendar.startOfDay(for: .now)
        let thisYear = calendar.component(.year, from: now)

        return members.map { member in
            let balance = rollup.byMember[member.id] ?? .zero(.krw)
            let projection = Projection.run(
                ProjectionInput(
                    startDate: now,
                    endDate: Plan.endDate(retirementYear: plan.retirementYear,
                                          notBefore: now, calendar: calendar),
                    buckets: plan.buckets(of: [member], total: balance),
                    monthlyContribution: Money(
                        minorUnits: member.monthlyContributionMinor + member.employerMatchMinor,
                        currency: .krw
                    ),
                    annualReturn: plan.annualReturn,
                    annualContributionGrowth: plan.contributionGrowth,
                    inflation: plan.inflation
                ),
                calendar: calendar
            )

            // 아이 카드에만 나이를 적는다. 원본이 그랬고, "2035년 = 13세" 가
            // 보이면 그 해가 무엇을 뜻하는지 바로 읽힌다.
            let showsAge = member.age < 20

            let bars = years.map { year -> OnePagerView.MemberSeries.Bar in
                let minor = year <= thisYear
                    ? balance.minorUnits
                    : (projection.point(inYear: year, calendar: calendar)?.nominal.minorUnits
                        ?? projection.last?.nominal.minorUnits ?? balance.minorUnits)
                return .init(year: year,
                             minor: max(0, minor),
                             age: showsAge ? max(0, year - member.birthYear) : nil)
            }
            return .init(memberID: member.id, bars: bars)
        }
    }
}
