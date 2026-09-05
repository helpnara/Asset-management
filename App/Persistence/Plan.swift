import Core
import Foundation
import SwiftData

/// 계획의 가정. 가구당 하나만 둔다.
///
/// 지금은 가구 전체를 하나의 숫자로 굴린다. 구성원별 적립 계획·연금·목돈 이벤트는
/// M2 후반에 세분화한다. 먼저 궤적 한 줄을 끝까지 그려 보는 것이 순서다.
@Model
final class Plan {
    var id: UUID = UUID()
    var title: String = "우리 가족 노후자금 준비"
    /// 계획을 세운 해. 로드맵 타임라인의 왼쪽 끝.
    var startYear: Int = Calendar.current.component(.year, from: .now)
    /// 은퇴 목표 연도. 궤적은 여기서 멈춘다.
    var retirementYear: Int = Calendar.current.component(.year, from: .now) + 23

    var monthlyContributionMinor: Int = 0
    /// 연 기대수익률 (basis point). 800 = 8%
    var annualReturnBP: Int = 800
    /// 적립액의 연 증가율. 연봉 상승률에 맞춘다.
    var contributionGrowthBP: Int = 0
    var inflationBP: Int = 200
    /// 은퇴 시점 목표 금액. 0이면 목표선을 그리지 않는다.
    var targetAmountMinor: Int = 0
    var createdAt: Date = Date.now

    init() {}
}

extension Plan {
    var annualReturn: Ratio { Ratio(basisPoints: annualReturnBP) }
    var contributionGrowth: Ratio { Ratio(basisPoints: contributionGrowthBP) }
    var inflation: Ratio { Ratio(basisPoints: inflationBP) }
    var monthlyContribution: Money { Money(minorUnits: monthlyContributionMinor, currency: .krw) }
    var targetAmount: Money { Money(minorUnits: targetAmountMinor, currency: .krw) }

    var yearsToRetirement: Int {
        max(retirementYear - Calendar.current.component(.year, from: .now), 0)
    }

    /// 오늘 잔고에서 은퇴 시점까지 굴린다.
    func projection(from balance: Money, calendar: Calendar = .current) -> ProjectionResult {
        let now = calendar.startOfDay(for: .now)
        let end = calendar.date(from: DateComponents(year: retirementYear, month: 12, day: 31)) ?? now
        return Projection.run(
            ProjectionInput(
                startDate: now,
                endDate: max(end, now),
                startingBalance: balance,
                monthlyContribution: monthlyContribution,
                annualReturn: annualReturn,
                annualContributionGrowth: contributionGrowth,
                inflation: inflation
            ),
            calendar: calendar
        )
    }

    /// 저장소에 하나뿐인 계획을 꺼내고, 없으면 만든다.
    static func current(in context: ModelContext) -> Plan {
        if let existing = (try? context.fetch(FetchDescriptor<Plan>()))?.first {
            return existing
        }
        let plan = Plan()
        context.insert(plan)
        return plan
    }
}
