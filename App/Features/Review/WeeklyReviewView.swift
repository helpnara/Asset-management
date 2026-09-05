import Core
import SwiftData
import SwiftUI

/// 주간 점검 — 이 앱의 심장.
///
/// 목표는 자산 24건을 3분 안에 끝내는 것이다 (ADR-0005).
/// 키패드를 띄운 채 다음 항목으로 넘어가고, 지난주 값과 증감을 옆에 붙여
/// 오타를 바로 알아채게 한다.
///
/// 순서는 화면과 같은 구성원 순서(아빠 → 엄마 → 아들 → 딸)를 따른다.
struct WeeklyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Member.sortIndex) private var members: [Member]
    @Query private var sessions: [ReviewSession]

    @State private var index = 0
    @State private var completed: ReviewSession?
    @FocusState private var focused: Bool

    /// 이번 주에 물어볼 항목. `고정`은 값이 잘 안 바뀌므로 아예 건너뛴다.
    private var queue: [Holding] {
        members.flatMap { member in
            member.sortedAccounts.flatMap { account in
                account.sortedHoldings.filter { $0.cadence != .fixed }
            }
        }
    }

    private var current: Holding? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                if let current {
                    entry(current)
                } else {
                    Spacer()
                    Text("점검할 항목이 없습니다")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.muted)
                    Spacer()
                }
                accessoryBar
            }
            .background(Color.white)
            .navigationTitle("주간 점검")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("나중에") { dismiss() }.foregroundStyle(Color.muted)
                }
            }
            .fullScreenCover(item: $completed) { session in
                ReviewCompleteView(session: session)
            }
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.rule)
                Rectangle().fill(Color.ink)
                    .frame(width: proxy.size.width * progressFraction)
            }
        }
        .frame(height: 2)
    }

    private var progressFraction: CGFloat {
        guard !queue.isEmpty else { return 0 }
        return CGFloat(index) / CGFloat(queue.count)
    }

    private func entry(_ holding: Holding) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(holding.account?.owner?.name ?? "")
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Text(holding.account?.name ?? "")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.muted)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(Color.surface)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Text(holding.name.isEmpty ? "이름 없음" : holding.name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.ink)
                        if holding.status != .accumulating {
                            StatusBadge(text: holding.status.label,
                                        foreground: holding.status.badgeForeground,
                                        background: holding.status.badgeBackground)
                        }
                    }
                    Text("\(holding.instrumentType.label) · \(holding.listingCountryCode)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.faint)

                    TextField("0", text: valueText(holding))
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .font(.figure(30, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .padding(.top, 14)

                    HStack(spacing: 8) {
                        Text("지난주 \(KoreanAmountFormatter.grouped(holding.lastEnteredValueMinor))")
                            .foregroundStyle(Color.muted)
                        Text(deltaText(holding))
                            .foregroundStyle(deltaColor(holding))
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 11.5))
                    .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)

                Spacer(minLength: 36)

                Text("값을 바꾸지 않고 넘기면 변동 없음으로 기록됩니다.\n고정으로 표시된 항목은 자동으로 건너뜁니다.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.faint)
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .onAppear { focused = true }
    }

    private var accessoryBar: some View {
        HStack(spacing: 10) {
            Button { step(-1) } label: {
                Image(systemName: "chevron.up")
                    .foregroundStyle(index == 0 ? Color.faint : Color.bodyText)
            }
            .disabled(index == 0)

            Text("\(min(index + 1, max(queue.count, 1))) / \(queue.count)")
                .font(.figure(11))
                .foregroundStyle(Color.muted)
                .frame(maxWidth: .infinity)

            Button(index >= queue.count - 1 ? "완료" : "다음") { step(1) }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 2))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(hex: 0xEDF1F3))
        .overlay(Rectangle().fill(Color.ruleStrong).frame(height: 1), alignment: .top)
    }

    // MARK: - 동작

    private func valueText(_ holding: Holding) -> Binding<String> {
        Binding(
            get: { holding.valueMinor == 0 ? "" : KoreanAmountFormatter.grouped(holding.valueMinor) },
            set: { holding.valueMinor = Int(String($0.filter(\.isNumber).prefix(15))) ?? 0 }
        )
    }

    private func deltaText(_ holding: Holding) -> String {
        let delta = holding.valueMinor - holding.lastEnteredValueMinor
        guard delta != 0 else { return "변동 없음" }
        guard holding.lastEnteredValueMinor != 0 else {
            return "첫 기록"
        }
        let percent = Decimal(abs(delta)) / Decimal(holding.lastEnteredValueMinor)
        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(KoreanAmountFormatter.grouped(abs(delta))) · \(PercentFormatter.oneDecimal(percent))%"
    }

    private func deltaColor(_ holding: Holding) -> Color {
        let delta = holding.valueMinor - holding.lastEnteredValueMinor
        if delta > 0 { return .gain }
        if delta < 0 { return .loss }
        return .faint
    }

    private func step(_ direction: Int) {
        let next = index + direction
        if next >= queue.count {
            finish()
        } else if next >= 0 {
            index = next
        }
    }

    private func finish() {
        let anchor = ReviewWeek.anchor(for: .now)
        let allHoldings = members
            .flatMap { $0.sortedAccounts }
            .flatMap { $0.sortedHoldings }
        let rollup = Valuation.rollUp(allHoldings.compactMap { $0.position() }, base: .krw)

        let previous = sessions
            .filter { $0.isComplete && $0.weekAnchor < anchor }
            .max { $0.weekAnchor < $1.weekAnchor }

        let session = ReviewSession(weekAnchor: anchor, totalCount: queue.count)
        session.enteredCount = queue.count
        session.completedAt = .now
        session.totalValueMinor = rollup.netWorth.minorUnits
        session.previousTotalValueMinor = previous?.totalValueMinor ?? 0
        context.insert(session)

        context.insert(Snapshot(
            weekAnchor: anchor,
            netWorthMinor: rollup.netWorth.minorUnits,
            investableMinor: rollup.investable.minorUnits,
            liabilitiesMinor: rollup.liabilities.minorUnits
        ))

        // 다음 주 증감 표시의 기준이 된다.
        for holding in queue {
            holding.lastEnteredValueMinor = holding.valueMinor
            holding.lastEnteredAt = .now
        }

        completed = session
    }
}
