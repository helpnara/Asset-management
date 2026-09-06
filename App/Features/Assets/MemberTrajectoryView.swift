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
    @Query(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]

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
                targetMinor: 0
            )
        }
        .padding(14)
        .background(Color.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Text("이 사람의 월 적립")
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

            if monthlyMinor != nil {
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

    private var effectiveMonthly: Int { monthlyMinor ?? member.monthlyContributionMinor }

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
