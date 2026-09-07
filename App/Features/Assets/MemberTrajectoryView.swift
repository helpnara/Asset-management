import Charts
import Core
import SwiftData
import SwiftUI

/// 한 사람의 자산이 어떻게 늘어 왔고 어떻게 늘어갈지.
///
/// **월에 얼마를 더 넣으면 좋을지 판단하려고 만든 화면이다**
/// (docs/08-feedback.md 9번). 그래서 적립 손잡이가 붙어 있고, 돌리면 궤적이
/// 즉시 다시 그려진다. 시뮬레이션 탭과 달리 **한 사람만** 본다.
///
/// 과거 선은 새로 만든 데이터가 아니다. `SnapshotLine` 이 주간 점검 때마다
/// 구성원별 값을 적어 왔다 — 화면만 없었다.
struct MemberTrajectoryView: View {
    let member: Member

    @Environment(\.dismiss) private var dismiss
    @Query private var plans: [Plan]
    @Query private var holdings: [Holding]
    @Query(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]
    @Query(sort: \UserMilestone.year) private var userMilestones: [UserMilestone]

    /// 손잡이. nil 이면 지금 계획대로다.
    @State private var monthlyMinor: Int?

    private var plan: Plan? { plans.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headline
                chart
                knob
                disclaimer
            }
            .padding(16)
        }
        .background(Color.surface)
        .navigationTitle(member.name.isEmpty ? "구성원" : member.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 머리글

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("지금")
                .eyebrowStyle()
            Text(Won.abbreviated(currentBalance, suffix: "원"))
                .font(.figure(28, weight: .bold))
                .foregroundStyle(Color.ink)
            if let end = projection?.point(inYear: retirementYear)?.nominal {
                Text("\(String(retirementYear))년에 \(Won.compact(end))")
                    .font(.figure(12))
                    .foregroundStyle(Color.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 궤적

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("궤적")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.bodyText)
            TrajectoryChart(
                points: points,
                today: Calendar.current.startOfDay(for: .now),
                targetMinor: 0,
                events: events
            )
        }
        .padding(14)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// **이 사람의** 인생 이벤트만 눈금으로 세운다 (docs/08-feedback.md 32번).
    /// 가족 전체의 일(전세 만기 등)은 현황판 궤적에 있으므로 여기서는 뺀다 —
    /// 한 사람의 화면에 가족 일까지 세우면 눈금만 늘어난다.
    private var events: [TrajectoryChart.EventMark] {
        let calendar = Calendar.current
        let thisYear = calendar.component(.year, from: .now)
        return userMilestones.compactMap { milestone in
            guard milestone.memberID == member.id, milestone.year >= thisYear,
                  let date = calendar.date(from: DateComponents(year: milestone.year, month: 1, day: 1))
            else { return nil }
            return .init(date: date,
                         label: milestone.label.isEmpty ? "마일스톤" : milestone.label)
        }
    }

    /// 과거는 매주 적어 둔 구성원별 값, 미래는 이 사람 몫의 예측.
    private var points: [TrajectoryChart.Point] {
        var result: [TrajectoryChart.Point] = snapshots.compactMap { snapshot in
            guard let line = snapshot.sortedLines.first(where: { $0.memberID == member.id })
            else { return nil }
            return .init(date: snapshot.weekAnchor, minor: line.valueMinor, series: .actual)
        }
        if let projection {
            // 예측은 연 단위로만 남긴다. 매달 찍으면 선이 두꺼워지기만 한다.
            var seenYear = -1
            for point in projection.points {
                let year = Calendar.current.component(.year, from: point.date)
                guard year != seenYear else { continue }
                seenYear = year
                result.append(.init(date: point.date,
                                    minor: point.nominal.minorUnits, series: .projected))
            }
        }
        return result
    }

    // MARK: - 손잡이

    private var knob: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("이 사람의 월 적립 (회사 매칭 포함)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.bodyText)
                Spacer()
                Text(Won.abbreviated(Money(minorUnits: effectiveMonthly, currency: .krw),
                                     suffix: "원"))
                    .font(.figure(15, weight: .bold))
                    .foregroundStyle(Color.ink)
            }
            Slider(
                value: Binding(
                    get: { Double(effectiveMonthly) },
                    set: { monthlyMinor = Int(($0 / 100_000).rounded()) * 100_000 }
                ),
                in: 0...5_000_000, step: 100_000
            )
            .tint(Color.dad)

            if monthlyMinor != nil, monthlyMinor != plannedMonthly {
                Button("계획값으로 되돌리기") { monthlyMinor = nil }
                    .font(.system(size: 12))
            }
        }
        .padding(14)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var disclaimer: some View {
        Text("손잡이를 돌려도 계획은 바뀌지 않습니다. 얼마를 더 넣으면 어떻게 되는지 보는 곳입니다.")
            .font(.system(size: 10.5))
            .foregroundStyle(Color.faint)
    }

    // MARK: - 계산

    /// 이 사람 몫의 월 적립. 1페이지의 구성원 미니 차트와 **같은 계산**을 쓴다 —
    /// 두 화면의 숫자가 어긋나면 안 된다 (docs/08-feedback.md 33번).
    ///
    /// 구성원별로 나눠 넣고 있으면 그 사람 칸(본인 + 회사 매칭), 아니면 계획의
    /// 한 덩어리를 **자산 비중대로** 나눈 몫이다. 예전에는 본인 부담만 봐서,
    /// 계획에만 적어 둔 집에서는 손잡이가 0원에서 시작했다.
    private var effectiveMonthly: Int {
        monthlyMinor ?? plannedMonthly
    }

    private var plannedMonthly: Int {
        guard let plan else { return member.monthlyContributionMinor }
        let family = Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw).netWorth
        return plan.memberMonthlyContributionMinor(member, familyTotal: family)
    }

    private var retirementYear: Int {
        plan?.retirementYear ?? Calendar.current.component(.year, from: .now) + 23
    }

    private var currentBalance: Money {
        Money(minorUnits: member.sortedAccounts.reduce(0) { sum, account in
            let value = account.sortedHoldings.reduce(0) { $0 + $1.valueMinor }
            return sum + (account.kind.isLiability ? -value : value)
        }, currency: .krw)
    }

    /// 이 사람 몫만 굴린다. 수익률·물가 가정은 가구 공통이다.
    private var projection: ProjectionResult? {
        guard let plan else { return nil }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: .now)
        return Projection.run(
            ProjectionInput(
                startDate: now,
                endDate: Plan.endDate(retirementYear: retirementYear, notBefore: now,
                                      calendar: calendar),
                buckets: plan.buckets(of: [member], total: currentBalance),
                monthlyContribution: Money(minorUnits: effectiveMonthly, currency: .krw),
                annualReturn: plan.annualReturn,
                annualContributionGrowth: plan.contributionGrowth,
                inflation: plan.inflation
            ),
            calendar: calendar
        )
    }
}
