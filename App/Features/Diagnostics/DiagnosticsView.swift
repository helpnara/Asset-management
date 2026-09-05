import Core
import SwiftData
import SwiftUI

/// 자산 진단 — 상시 점검.
///
/// **가장 큰 원칙: 최종 투자 목적은 노후준비다.** 화면 맨 위에 그 문장을 두고,
/// 그 아래 규칙들은 전부 "이게 은퇴 시점의 나에게 무슨 뜻인가"로 환원된다.
///
/// 규칙은 막지 않고 알린다. 그래서 상태가 `위반` 이 아니라 `조치` 다 —
/// 무엇을 하면 되는지까지 말해야 규칙이 산다 (설계 2.7).
struct DiagnosticsView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @Environment(\.modelContext) private var context
    @Query private var plans: [Plan]
    @Query private var holdings: [Holding]
    @Query private var accounts: [Account]
    @Query(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Query(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Query(sort: \Member.sortIndex) private var members: [Member]

    @State private var expanded: Set<String> = []
    @State private var isEditingCriteria = false

    var body: some View {
        Group {
            if let plan = plans.first {
                content(plan)
            } else {
                ProgressView().task { _ = Plan.current(in: context) }
            }
        }
        .background(Color.surface.opacity(0.5))
        .navigationTitle("자산 진단")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditingCriteria) {
            if let plan = plans.first { DiagnosticsCriteriaView(plan: plan) }
        }
    }

    @ViewBuilder
    private func content(_ plan: Plan) -> some View {
        let result = Diagnostics.run(plan.diagnosticsInput(
            rollup: rollup,
            accounts: accounts,
            projection: plan.projection(from: rollup.netWorth, cashEvents: cashEvents,
                                        incomes: incomes, members: members),
            members: members
        ))

        ScrollView {
            VStack(spacing: 12) {
                summary(result)
                ForEach(result.sorted) { card($0) }
                criteriaButton
                disclaimer
            }
            .padding(14)
        }
    }

    // MARK: - 요약

    private func summary(_ result: DiagnosticsResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("최종 투자 목적은 노후준비")
                .eyebrowStyle()

            HStack(spacing: 18) {
                tally("조치", result.count(.act), .loss)
                tally("주의", result.count(.watch), Color.dad)
                tally("지킴", result.count(.pass), .gain)
                if result.count(.unknown) > 0 {
                    tally("입력 필요", result.count(.unknown), .faint)
                }
                Spacer(minLength: 0)
            }

            Text(headline(result))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    private func tally(_ label: String, _ count: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(count)")
                .font(.figure(22, weight: .bold))
                .foregroundStyle(count > 0 ? color : Color.faint)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.muted)
        }
    }

    private func headline(_ result: DiagnosticsResult) -> String {
        if result.count(.act) > 0 {
            return "할 일이 \(result.count(.act))개 있습니다. 급하지 않지만 미루면 은퇴 시점에서 되돌리기 어려워집니다."
        }
        if result.count(.watch) > 0 {
            return "당장 할 일은 없고 지켜볼 것이 \(result.count(.watch))개입니다."
        }
        if result.count(.unknown) > 0 {
            return "기준을 몇 개 더 넣으면 진단이 정확해집니다. 모르는 것은 모른다고 표시합니다."
        }
        return "기준을 모두 지키고 있습니다. 다음 점검 때 다시 봅니다."
    }

    // MARK: - 진단 카드

    private func card(_ diagnosis: Diagnosis) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(diagnosis.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Spacer()
                StatusBadge(text: diagnosis.status.label,
                            foreground: color(diagnosis.status),
                            background: color(diagnosis.status).opacity(0.12))
            }

            Text(diagnosis.headline)
                .font(.figure(12.5))
                .foregroundStyle(Color.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            if let progress = diagnosis.progress {
                gauge(progress, color: color(diagnosis.status))
            }

            Text(diagnosis.action)
                .font(.system(size: 12))
                .foregroundStyle(Color.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // 이유는 접어 둔다. 매주 볼 화면에 매번 펼쳐 두면 읽히지 않는다.
            Button {
                if expanded.contains(diagnosis.id) {
                    expanded.remove(diagnosis.id)
                } else {
                    expanded.insert(diagnosis.id)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("왜 이 기준인가")
                    Image(systemName: expanded.contains(diagnosis.id) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                }
                .font(.system(size: 11))
                .foregroundStyle(Color.dad)
            }

            if expanded.contains(diagnosis.id) {
                Text(diagnosis.rationale)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.faint)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground)
    }

    /// 게이지는 1.0 을 기준선으로 둔다. 넘어가는 규칙(부동산 상한)과
    /// 채워야 하는 규칙(저축률)이 같은 모양이라 눈이 한 번에 읽는다.
    private func gauge(_ progress: Double, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.rule)
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * min(max(progress, 0), 1.5) / 1.5)
                // 기준선. 이 선을 넘었는지 못 미쳤는지가 규칙의 전부다.
                Rectangle()
                    .fill(Color.ink.opacity(0.45))
                    .frame(width: 1.5)
                    .offset(x: geometry.size.width / 1.5)
            }
        }
        .frame(height: 6)
    }

    private func color(_ status: DiagnosisStatus) -> Color {
        switch status {
        case .pass: return .gain
        case .watch: return .dad
        case .act: return .loss
        case .unknown: return .faint
        }
    }

    // MARK: - 기준 · 고지

    private var criteriaButton: some View {
        Button {
            isEditingCriteria = true
        } label: {
            Label("진단 기준 바꾸기", systemImage: "slider.horizontal.3")
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(Color.ink)
    }

    private var disclaimer: some View {
        Text("여기 기준은 널리 쓰이는 원칙일 뿐 정답이 아니고, 전부 직접 고칠 수 있습니다. 이 앱은 세법을 따라가지 않습니다 — 계좌 한도는 직접 확인해 넣으세요. 투자 권유가 아닙니다.")
            .font(.system(size: 10.5))
            .foregroundStyle(Color.faint)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.rule, lineWidth: 1)
            )
    }

    private var rollup: Rollup {
        Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw)
    }
}
