import Core
import SwiftData
import SwiftUI

/// 주간 점검 — 이 앱의 심장.
///
/// 스프레드시트에서 한 주를 한 행씩 채우던 감각을 그대로 옮긴다.
/// 전 종목을 목록으로 늘어놓고 위에서 아래로 훑으며 적는다. 어디까지 했는지,
/// 앞뒤 값이 어떤지가 항상 보인다.
///
/// 목표는 자산 24건을 3분 안에 끝내는 것이다 (ADR-0005).
struct WeeklyReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Query(sort: \Member.sortIndex) private var members: [Member]
    @Query private var sessions: [ReviewSession]

    @FocusState private var focusedID: UUID?
    @State private var visited: Set<UUID> = []
    @State private var completed: ReviewSession?

    /// `고정` 은 값이 잘 안 바뀌므로 큐에서 아예 뺀다. 매주 물어볼 항목을 줄이는 장치.
    private func queue(for member: Member) -> [Holding] {
        member.sortedAccounts.flatMap { account in
            account.sortedHoldings.filter { $0.cadence != .fixed }
        }
    }

    private var queue: [Holding] { members.flatMap { queue(for: $0) } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(members) { member in
                            let rows = queue(for: member)
                            if !rows.isEmpty {
                                Section {
                                    ForEach(rows) { holding in
                                        row(holding).id(holding.id)
                                    }
                                } header: {
                                    memberHeader(member, count: rows.count)
                                }
                            }
                        }
                        footer
                    }
                }
                .onChange(of: focusedID) { _, newValue in
                    guard let newValue else { return }
                    visited.insert(newValue)
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
            .background(Color.white)
            .safeAreaInset(edge: .top, spacing: 0) { progressBar }
            .navigationTitle("주간 점검")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("나중에") { dismiss() }.foregroundStyle(Color.muted)
                }
                ToolbarItemGroup(placement: .keyboard) { accessory }
            }
            .onAppear { focusedID = queue.first?.id }
            .fullScreenCover(item: $completed) { ReviewCompleteView(session: $0) }
        }
    }

    // MARK: - 조각

    private var progressBar: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.rule)
                    Rectangle().fill(Color.ink)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 2)
        }
        .background(Color.white)
    }

    private var fraction: CGFloat {
        guard !queue.isEmpty else { return 0 }
        return CGFloat(visited.count) / CGFloat(queue.count)
    }

    private func memberHeader(_ member: Member, count: Int) -> some View {
        HStack {
            Text(member.name.isEmpty ? "이름 없음" : member.name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.ink)
            Spacer()
            Text("\(visitedCount(member)) / \(count)")
                .font(.figure(10))
                .foregroundStyle(Color.muted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.surface)
        .overlay(Rectangle().fill(Color.rule).frame(height: 1), alignment: .bottom)
    }

    private func visitedCount(_ member: Member) -> Int {
        queue(for: member).filter { visited.contains($0.id) }.count
    }

    private func row(_ holding: Holding) -> some View {
        let isActive = focusedID == holding.id
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(holding.name.isEmpty ? "이름 없음" : holding.name)
                        .font(.system(size: 13.5, weight: isActive ? .medium : .regular))
                        .foregroundStyle(Color.ink)
                    if holding.status != .accumulating {
                        StatusBadge(text: holding.status.label,
                                    foreground: holding.status.badgeForeground,
                                    background: holding.status.badgeBackground)
                    }
                }
                Text("지난주 \(KoreanAmountFormatter.grouped(holding.lastEnteredValueMinor))")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.faint)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                TextField("0", text: valueText(holding))
                    .keyboardType(.numberPad)
                    .focused($focusedID, equals: holding.id)
                    .multilineTextAlignment(.trailing)
                    .font(.figure(isActive ? 19 : 16, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(Color.ink)
                    .frame(width: 155)
                Text(deltaText(holding))
                    .font(.system(size: 10))
                    .foregroundStyle(deltaColor(holding))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(isActive ? Color(hex: 0xF7FAFB) : Color.white)
        .overlay(alignment: .leading) {
            if isActive { Rectangle().fill(Color.ink).frame(width: 2) }
        }
        .overlay(Rectangle().fill(Color.rule).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture { focusedID = holding.id }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text("값을 바꾸지 않고 넘기면 변동 없음으로 기록됩니다.\n고정으로 표시된 항목은 목록에서 빠집니다.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.faint)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                finish()
            } label: {
                Text("점검 완료")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(20)
    }

    private var accessory: some View {
        HStack(spacing: 10) {
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(currentIndex == 0)
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .disabled(currentIndex >= queue.count - 1)

            Spacer()

            Text("\(min(currentIndex + 1, max(queue.count, 1))) / \(queue.count)")
                .font(.figure(11))
                .foregroundStyle(Color.muted)

            Spacer()

            Button("변동 없음") { move(1) }
                .font(.system(size: 13))
            Button(currentIndex >= queue.count - 1 ? "완료" : "다음") {
                if currentIndex >= queue.count - 1 { finish() } else { move(1) }
            }
            .font(.system(size: 13, weight: .semibold))
        }
    }

    // MARK: - 동작

    private var currentIndex: Int {
        guard let focusedID, let index = queue.firstIndex(where: { $0.id == focusedID }) else { return 0 }
        return index
    }

    private func move(_ delta: Int) {
        let next = currentIndex + delta
        guard queue.indices.contains(next) else { return }
        focusedID = queue[next].id
    }

    private func valueText(_ holding: Holding) -> Binding<String> {
        Binding(
            get: { holding.valueMinor == 0 ? "" : KoreanAmountFormatter.grouped(holding.valueMinor) },
            set: { holding.valueMinor = Int(String($0.filter(\.isNumber).prefix(15))) ?? 0 }
        )
    }

    private func deltaText(_ holding: Holding) -> String {
        let delta = holding.valueMinor - holding.lastEnteredValueMinor
        guard holding.lastEnteredValueMinor != 0 else { return "첫 기록" }
        guard delta != 0 else { return "변동 없음" }
        let percent = Decimal(abs(delta)) / Decimal(holding.lastEnteredValueMinor)
        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(KoreanAmountFormatter.grouped(abs(delta))) · \(PercentFormatter.oneDecimal(percent))%"
    }

    private func deltaColor(_ holding: Holding) -> Color {
        let delta = holding.valueMinor - holding.lastEnteredValueMinor
        if holding.lastEnteredValueMinor == 0 { return .faint }
        if delta > 0 { return .gain }
        if delta < 0 { return .loss }
        return .faint
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

        focusedID = nil
        completed = session
    }
}
