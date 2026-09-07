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
        let stops = roadmapStops(plan: plan, projection: projection, rollup: rollup,
                                 today: today, calendar: calendar)

        // **구성원별로 나눠 넣지 않는 집은 계획에만 값이 있다.** 구성원 합만
        // 세면 종이에 `월 적립 0원` 이 찍힌다 (docs/08-feedback.md 33번).
        let splitsByMember = plan?.usesMemberContributions ?? false
        let memberTotal = members.reduce(0) { $0 + $1.monthlyContributionMinor + $1.employerMatchMinor }
        let memberOwn = members.reduce(0) { $0 + $1.monthlyContributionMinor }
        let planMonthly = plan?.monthlyContributionMinor ?? 0

        return OnePagerView(
            title: plan?.title ?? "우리 가족 노후자금 준비",
            asOfNote: plan?.asOfNote ?? "",
            startedOn: plan?.startedOn,
            startYear: plan?.startYear ?? calendar.component(.year, from: today),
            retirementYear: plan?.retirementYear ?? calendar.component(.year, from: today) + 23,
            declaration: plan?.declaration ?? "",
            rollup: rollup,
            members: members,
            roadmapStops: stops,
            cashEvents: cashEvents.filter { !$0.isAlreadyReflected },
            principles: principles,
            todos: todos,
            usShare: rollup.countryShare("US"),
            krShare: rollup.countryShare("KR"),
            // 계획에만 적어 두었으면 그 값이 곧 본인 부담이다 — 회사 매칭은
            // 구성원 칸에만 있는 값이라 계획 쪽에는 섞여 있지 않다.
            monthlyTotalMinor: splitsByMember ? memberTotal : planMonthly,
            ownContributionMinor: splitsByMember ? memberOwn : planMonthly,
            showsMemberContribution: splitsByMember,
            memberSeries: memberSeries(plan: plan, members: members, rollup: rollup,
                                       years: stops.map(\.year), calendar: calendar),
            today: today,
            nextReview: ReviewWeek.nextSaturday(after: today, calendar: calendar)
        )
    }

    /// 로드맵 정거장 — **현황판의 여섯 칸과 같은 뼈대**다.
    ///
    /// 예전에는 마일스톤만 실어서 `지금` 과 `은퇴` 가 빠졌고, 그 바람에 아래
    /// 구성원 카드의 막대(지금부터 은퇴까지)와 해가 어긋났다. 여기서 만든
    /// 연도를 미니 바차트가 그대로 쓰므로 이제 어긋날 수 없다.
    private static func roadmapStops(plan: Plan?, projection: ProjectionResult?,
                                     rollup: Rollup, today: Date,
                                     calendar: Calendar) -> [OnePagerView.Stop] {
        let thisYear = calendar.component(.year, from: today)
        var stops: [OnePagerView.Stop] = [
            .init(year: thisYear, minor: rollup.netWorth.minorUnits, label: "지금")
        ]
        for milestone in (projection?.milestones ?? []).sorted(by: { $0.year < $1.year })
        where milestone.year > thisYear {
            stops.append(.init(year: milestone.year,
                               minor: milestone.balance.minorUnits,
                               label: milestone.kind.label))
        }
        if let plan, let atRetirement = projection?.point(inYear: plan.retirementYear,
                                                         calendar: calendar) {
            // 목표 달성이 은퇴와 같은 해면 칸을 하나로 둔다 — 같은 해가 두 번
            // 서면 미니 바차트의 막대도 두 번 선다.
            if let index = stops.firstIndex(where: { $0.year == plan.retirementYear }) {
                stops[index] = .init(year: plan.retirementYear,
                                     minor: atRetirement.nominal.minorUnits,
                                     label: stops[index].label + " · 은퇴")
            } else if plan.retirementYear > thisYear {
                stops.append(.init(year: plan.retirementYear,
                                   minor: atRetirement.nominal.minorUnits,
                                   label: "은퇴"))
            }
        }
        return stops.sorted { $0.year < $1.year }
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
                    // **그 사람의 은퇴 해까지만 적립한다** (38번).
                    // 구성원 궤적 화면과 같은 값을 쓴다.
                    endDate: Plan.endDate(retirementYear: member.retirementYear,
                                          notBefore: now, calendar: calendar),
                    buckets: plan.buckets(of: [member], total: balance),
                    monthlyContribution: Money(
                        minorUnits: plan.memberMonthlyContributionMinor(member, familyTotal: rollup.netWorth),
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
