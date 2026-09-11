import Core
import CoreData
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

    @Environment(\.managedObjectContext) private var context
    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]
    @Fetched private var holdings: [Holding]
    @Fetched private var accounts: [Account]
    @Fetched(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Fetched(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    /// 진단 이력 (A9). 점검을 끝낼 때마다 그 주의 판정이 남는다.
    @Fetched private var sessions: [ReviewSession]

    @State private var expanded: Set<String> = []
    @State private var isEditingCriteria = false
    // 진단 기준은 가구 하나에 한 벌이다 — 관리자만 바꾼다.
    @Environment(\.canManageHousehold) private var canManageHousehold

    var body: some View {
        Group {
            if let plan = plans.first {
                content(plan)
            } else {
                ProgressView().task { _ = Plan.current(in: context) }
            }
        }
        .background(Color.ground)
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
                .font(.scaled(12.5))
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)

            // 상시 고지 (docs/10 §2-2, 규제 R6). 맨 아래 긴 고지는 스크롤해야 보인다.
            Text("널리 쓰이는 경험칙이며 투자 조언이 아닙니다. 기준은 전부 직접 고칠 수 있습니다.")
                .font(.scaled(10.5))
                .foregroundStyle(Color.faint)
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
                .font(.scaled(10.5))
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
                    .font(.scaled(14, weight: .semibold))
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

            // 결론에서 파생되는 숫자 하나 — 선저축이면 투자를 뺀 생활비.
            if let detail = diagnosis.detail {
                Text(detail)
                    .font(.figure(11.5))
                    .foregroundStyle(Color.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let progress = diagnosis.progress {
                gauge(progress, color: color(diagnosis.status))
            }

            history(diagnosis)

            Text(diagnosis.action)
                .font(.scaled(12))
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
                        .font(.scaled(9))
                }
                .font(.scaled(11))
                .foregroundStyle(Color.dad)
            }

            if expanded.contains(diagnosis.id) {
                Text(diagnosis.rationale)
                    .font(.scaled(11.5))
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

    // MARK: - 이력 (A9)

    /// **언제부터 이랬나.** 최근 점검 여덟 주의 판정을 점으로, 지금 판정이 몇 주째
    /// 이어지는지를 글로 보인다. 이력이 없으면(이 칸이 생기기 전) 자리도 없다.
    @ViewBuilder
    private func history(_ diagnosis: Diagnosis) -> some View {
        let past = ReviewSession.diagnosisHistory(diagnosis.kind, sessions: sessions)
        if !past.isEmpty {
            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    ForEach(Array(past.enumerated()), id: \.offset) { _, item in
                        Circle()
                            .fill(color(item.status))
                            .frame(width: 7, height: 7)
                    }
                }
                Text(trend(diagnosis.status, past: past.map(\.status)))
                    .font(.scaled(11))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    /// 지금 판정이 몇 주째인가. 최근 점검부터 거슬러 같은 판정이 이어진 수다.
    private func trend(_ current: DiagnosisStatus, past: [DiagnosisStatus]) -> String {
        let streak = past.reversed().prefix { $0 == current }.count
        if streak == 0, let last = past.last {
            return "지난 점검엔 \(last.label) → 지금 \(current.label)"
        }
        return streak == past.count
            ? "기록된 \(streak)주 내내 \(current.label)"
            : "\(streak)주째 \(current.label)"
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

    @ViewBuilder
    private var criteriaButton: some View {
        if canManageHousehold {
            Button {
                isEditingCriteria = true
            } label: {
                Label("진단 기준 바꾸기", systemImage: "slider.horizontal.3")
                    .font(.scaled(13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(Color.ink)
        }
    }

    private var disclaimer: some View {
        Text("여기 기준은 널리 쓰이는 원칙일 뿐 정답이 아니고, 전부 직접 고칠 수 있습니다. 이 앱은 세법을 따라가지 않습니다 — 계좌 한도는 직접 확인해 넣으세요. 투자 권유가 아닙니다.")
            .font(.scaled(10.5))
            .foregroundStyle(Color.faint)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.raised)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.rule, lineWidth: 1)
            )
    }

    private var rollup: Rollup {
        Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw)
    }
}
