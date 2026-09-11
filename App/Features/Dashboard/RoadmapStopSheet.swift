import Core
import SwiftUI

/// **정거장 하나의 분해** (docs/08-feedback.md 85번, C3).
///
/// "2039 · 24.2억" 이 어떻게 나온 숫자인지 — 그때까지 넣은 돈, 자란 돈, 목돈,
/// 그리고 사람마다 얼마씩인지. 로드맵 칩을 누르면 뜬다 (설계 2.2.2).
struct RoadmapStopSheet: View {
    let stop: RoadmapStrip.Stop
    let plan: Plan
    let projection: ProjectionResult
    let members: [Member]
    let rollup: Rollup

    @Environment(\.dismiss) private var dismiss

    private var year: Int { stop.year ?? Calendar.current.component(.year, from: .now) }
    private var thisYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headline
                    Rectangle().fill(Color.rule).frame(height: 1)
                    untilThen
                    thatYear
                    byMember
                    Text("입력한 가정(연 \(PercentFormatter.oneDecimal(plan.annualReturn.fraction))% · 물가 \(PercentFormatter.oneDecimal(plan.inflation.fraction))%)에 따른 계산이며 미래 수익을 보장하지 않습니다. 구성원별 합은 사람마다 따로 굴린 값이라 가족 예상과 조금 다를 수 있습니다.")
                        .font(.scaled(10))
                        .foregroundStyle(Color.faint)
                        .lineSpacing(3)
                        .padding(20)
                }
            }
            .background(Color.ground)
            .navigationTitle("\(String(year))년 · \(stop.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large, .medium])
    }

    // MARK: - 조각

    private var point: ProjectionPoint? { projection.point(inYear: year) }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(detail.uppercased()).eyebrowStyle().padding(.bottom, 7)
            Text(Won.abbreviated(stop.amount ?? point?.nominal ?? .zero(.krw), suffix: "원"))
                .font(.figure(32, weight: .semibold))
                .foregroundStyle(Color.ink)
            if let point {
                Text("오늘 돈으로 \(Won.compact(point.real)) · \(year - thisYear)년 뒤")
                    .font(.scaled(11.5))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var detail: String {
        if let kind = MilestoneKind.allCases.first(where: { $0.label == stop.label }) {
            return kind.detail
        }
        return stop.isGoal ? "은퇴 시점의 예상 자산" : "그 해의 예상 자산"
    }

    /// 지금부터 그 해 말까지의 누계.
    private var untilThen: some View {
        let years = projection.years.filter { $0.year <= year }
        let contributed = years.reduce(Money.zero(.krw)) { $0 + $1.contributed }
        let lumps = years.reduce(Money.zero(.krw)) { $0 + $1.cashEvents }
        let gained = years.reduce(Money.zero(.krw)) { $0 + $1.gain }
        let withdrawn = years.reduce(Money.zero(.krw)) { $0 + $1.withdrawn }
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("지금부터 그때까지")
            Rectangle().fill(Color.rule).frame(height: 1)
            row("지금 자산", rollup.netWorth)
            row("넣을 돈 (적립)", contributed, sign: true)
            if !lumps.isZero { row("목돈 이벤트", lumps, sign: true) }
            row("자랄 돈 (수익)", gained, sign: true, tone: true)
            if !withdrawn.isZero { row("꺼내 쓸 돈 (인출)", withdrawn, sign: true) }
            row("그 해 말 예상", point?.nominal ?? .zero(.krw), emphasized: true)
        }
    }

    private var thatYear: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let summary = projection.years.first(where: { $0.year == year }) {
                sectionHeader("\(String(year))년 한 해")
                Rectangle().fill(Color.rule).frame(height: 1)
                row("적립", summary.contributed, sign: true)
                row("수익", summary.gain, sign: true, tone: true)
                if !summary.withdrawn.isZero { row("인출", summary.withdrawn, sign: true) }
            }
        }
    }

    /// 사람마다 따로 굴린다 — 구성원 궤적 화면과 같은 계산 (`Plan.memberProjection`).
    private var byMember: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !members.isEmpty {
                sectionHeader("구성원별 예상")
                Rectangle().fill(Color.rule).frame(height: 1)
                ForEach(members) { member in
                    let balance = rollup.byMember[member.id] ?? .zero(.krw)
                    let monthly = plan.memberMonthlyContributionMinor(member, familyTotal: rollup.netWorth)
                    let projected = plan.memberProjection(member, balance: balance, monthlyMinor: monthly,
                                                          through: year).point(inYear: year)?.nominal
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color.member(member.colorIndex)).frame(width: 8, height: 8)
                            Text(member.name.isEmpty ? "이름 없음" : member.name)
                                .font(.scaled(12.5))
                                .foregroundStyle(Color.ink)
                            Text("\(max(0, year - member.birthYear))세")
                                .font(.scaled(10))
                                .foregroundStyle(Color.faint)
                        }
                        Spacer()
                        Text(projected.map { Won.compact($0) } ?? "—")
                            .font(.figure(12.5, weight: .medium))
                            .foregroundStyle(Color.ink)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    Rectangle().fill(Color.rule).frame(height: 1)
                }
            }
        }
    }

    private func row(_ label: String, _ money: Money, sign: Bool = false,
                     tone: Bool = false, emphasized: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.scaled(12, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(emphasized ? Color.ink : Color.muted)
                Spacer()
                Text(Won.compact(money, sign: sign ? .always : .negativeOnly))
                    .font(.figure(12.5, weight: emphasized ? .bold : .medium))
                    .foregroundStyle(tone ? (money.isNegative ? Color.loss : Color.gain) : Color.ink)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            Rectangle().fill(Color.rule).frame(height: 1)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.scaled(14, weight: .bold))
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
    }
}
