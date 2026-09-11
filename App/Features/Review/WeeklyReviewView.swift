import Core
import CoreData
import SwiftUI

/// 주간 점검 — 이 앱의 심장.
///
/// 스프레드시트에서 한 주를 한 행씩 채우던 감각을 그대로 옮긴다.
/// 전 종목을 목록으로 늘어놓고 위에서 아래로 훑으며 적는다. 어디까지 했는지,
/// 앞뒤 값이 어떤지가 항상 보인다.
///
/// 목표는 자산 24건을 3분 안에 끝내는 것이다 (ADR-0005).
struct WeeklyReviewView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @Environment(\.self) private var environment

    /// **적을 수 있는 구성원만 큐에 넣는다.** `editor` 는 본인 것만이다
    /// (docs/09 4단계). 총액·구성원별 분해는 `members` 전체로 낸다 — 남의
    /// 값은 못 고쳐도 가족 총액에는 들어가야 한다.
    private var editableMembers: [Member] { members.filter { environment.mayEdit($0) } }
    @Fetched private var sessions: [ReviewSession]
    @Fetched(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]
    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]

    @FocusState private var focusedID: UUID?
    @State private var visited: Set<UUID> = []
    @State private var completed: ReviewSession?
    /// **열 때 정한 큐** (105번). 월 1회 종목은 값을 적는 순간 "이 달에 적음" 이
    /// 되어 `isDue()` 가 거짓이 되는데, 큐를 매번 다시 계산하면 그 줄이 손에서
    /// 사라진다. 열 때 한 번 정하고 그대로 둔다.
    @State private var queuedIDs: Set<UUID>?
    /// 열 때의 값 — `나중에` 는 전부 되돌린다 (103번). 값은 치는 대로 저장되므로
    /// 되돌릴 것을 따로 들고 있어야 한다.
    @State private var originals: [UUID: (value: Int, baseline: Int, at: Date?)] = [:]
    /// 크게 바뀐 항목을 한 번 확인받는 중 (B2).
    @State private var isConfirmingLargeChanges = false

    /// `고정` 은 큐에서 빼고, `월 1회` 는 그 달에 이미 적었으면 뺀다 (92번).
    /// 열린 뒤에는 열 때 정한 큐를 지킨다 (105번).
    private func queue(for member: Member) -> [Holding] {
        member.sortedAccounts.flatMap { account in
            account.sortedHoldings.filter { isQueued($0) }
        }
    }

    private func isQueued(_ holding: Holding) -> Bool {
        if let queuedIDs { return queuedIDs.contains(holding.id) }
        return holding.isDue()
    }

    private var queue: [Holding] { editableMembers.flatMap { queue(for: $0) } }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(editableMembers) { member in
                            let rows = queue(for: member)
                            if !rows.isEmpty {
                                Section {
                                    // 계좌마다 소제목을 단다. 증권사 앱을 옮겨가며 적으므로
                                    // 지금 어느 계좌를 보고 있는지가 보여야 한다.
                                    ForEach(member.sortedAccounts) { account in
                                        let items = account.sortedHoldings.filter { isQueued($0) }
                                        if !items.isEmpty {
                                            accountLabel(account)
                                            ForEach(items) { holding in
                                                row(holding).id(holding.id)
                                            }
                                        }
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
            .background(Color.canvas)
            .safeAreaInset(edge: .top, spacing: 0) { progressBar }
            .navigationTitle("주간 점검")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // **취소다** (103번). 치는 대로 저장되므로 열 때 값으로 되돌린다.
                    Button("나중에") { revertAll(); dismiss() }.foregroundStyle(Color.muted)
                }
                ToolbarItemGroup(placement: .keyboard) { accessory }
            }
            .onAppear {
                if queuedIDs == nil {
                    let items = queue
                    queuedIDs = Set(items.map(\.id))
                    for holding in items {
                        originals[holding.id] = (holding.valueMinor, holding.lastEnteredValueMinor, holding.lastEnteredAt)
                    }
                }
                focusedID = queue.first?.id
            }
            // 완료 화면을 닫으면 점검 화면도 함께 닫힌다 — 현황판으로 (103번).
            .fullScreenCover(item: $completed, onDismiss: { dismiss() }) { ReviewCompleteView(session: $0) }
            // **오타를 한 번 되묻는다** (docs/08-feedback.md 81번, B2). 지난주보다
            // 30% 넘게 움직인 항목이 있으면 저장 전에 이름을 들어 보여 준다.
            // 막지는 않는다 — 진짜로 그렇게 움직였을 수 있다.
            .confirmationDialog(largeChangeTitle, isPresented: $isConfirmingLargeChanges,
                                titleVisibility: .visible) {
                Button("그대로 저장") { finish() }
                Button("되돌리기") { revertSuspicious() }
                Button("다시 보기", role: .cancel) {
                    focus(suspiciousHoldings.first?.id)
                }
            } message: {
                Text(largeChangeMessage)
            }
        }
    }

    // MARK: - 크게 바뀐 항목 (B2)

    /// 지난주 대비 30% 넘게, 그리고 10만원 넘게 움직인 것. 작은 종목의 자연스러운
    /// 출렁임까지 붙잡지 않으려고 금액 바닥을 둔다.
    private func isLargeChange(_ holding: Holding) -> Bool {
        let last = holding.lastEnteredValueMinor
        guard last != 0 else { return false }
        let delta = abs(holding.valueMinor - last)
        return delta >= 100_000 && Decimal(delta) / Decimal(abs(last)) >= Decimal(string: "0.3")!
    }

    private var suspiciousHoldings: [Holding] { queue.filter(isLargeChange) }

    private var largeChangeTitle: String {
        "크게 바뀐 항목 \(suspiciousHoldings.count)건 — 맞나요?"
    }

    private var largeChangeMessage: String {
        let names = suspiciousHoldings.prefix(3).map { holding -> String in
            let name = holding.name.isEmpty ? "이름 없음" : holding.name
            return "\(name) \(deltaText(holding))"
        }
        let more = suspiciousHoldings.count > 3 ? " 외 \(suspiciousHoldings.count - 3)건" : ""
        return names.joined(separator: "\n") + more + "\n지난주보다 30% 넘게 움직였습니다. 0 을 하나 더 쳤는지 한 번만 보세요."
    }

    /// 크게 바뀐 항목을 지난주 값으로 되돌리고 그 첫 줄로 간다 (103번).
    private func revertSuspicious() {
        let items = suspiciousHoldings
        for holding in items { holding.valueMinor = holding.lastEnteredValueMinor }
        focus(items.first?.id)
    }

    /// **확인 창이 닫힌 뒤에 준다** (107번). 창이 내려가는 중에 포커스를 주면
    /// 창이 가져가 버려 커서가 안 옮겨졌다.
    private func focus(_ id: UUID?) {
        guard let id else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            focusedID = id
        }
    }

    /// 열 때 값으로 전부 되돌린다 — `나중에` (103번).
    private func revertAll() {
        for holding in queue {
            guard let original = originals[holding.id] else { continue }
            holding.valueMinor = original.value
            holding.lastEnteredValueMinor = original.baseline
            holding.lastEnteredAt = original.at
        }
    }

    /// 완료 버튼이 부르는 곳. 크게 바뀐 것이 있으면 되묻고, 없으면 바로 끝낸다.
    private func requestFinish() {
        if suspiciousHoldings.isEmpty {
            finish()
        } else {
            focusedID = nil
            isConfirmingLargeChanges = true
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
        .background(Color.canvas)
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

    private func accountLabel(_ account: Account) -> some View {
        HStack(spacing: 6) {
            Text(account.name.isEmpty ? account.kind.label : account.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.muted)
            if !account.institution.isEmpty {
                Text(account.institution)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.faint)
            }
            if account.kind.isLiability {
                StatusBadge(text: "부채", foreground: .loss, background: Color.lossSoft)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 5)
    }

    /// 이 종목이 **자기 계좌 안에서** 목표에서 얼마나 벗어났나
    /// (docs/08-feedback.md 15번).
    private func driftSlice(_ holding: Holding) -> Allocation.Slice? {
        holding.driftSlice(tolerance: plans.first?.driftTolerance ?? Allocation.Tolerance())
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
                    // 금액을 고치는 순간 다시 계산된다 — "지금 이걸 적고 나니
                    // 비중이 틀어졌다" 를 그 자리에서 본다 (docs/08-feedback.md 14번).
                    // 숫자가 먼저다 — `15/20% 주의` 라야 얼마나 벗어났는지 읽힌다.
                    if let slice = driftSlice(holding) {
                        WeightLabel(slice: slice)
                    }
                }
                // 같은 주에 다시 열었으면 기준은 지난주가 아니라 **이번 주에 먼저
                // 적은 값**이다 (90번). 끝낼 때 기준값이 그 값으로 바뀌어 있다.
                Text("\(baselineLabel(holding)) \(Won.grouped(holding.lastEnteredValueMinor))")
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
                // **읽는 값** (80번, B1). 활성 행에서만 — 열다섯 자리 중 0 하나가
                // 더 붙었는지 치는 순간 보인다. 입력 칸이라 가리기를 안 거친다.
                if isActive && holding.valueMinor >= 10_000 {
                    Text(KoreanAmountFormatter.abbreviated(Money(minorUnits: holding.valueMinor, currency: .krw), suffix: "원"))
                        .font(.figure(10.5, weight: .medium))
                        .foregroundStyle(Color.dad)
                }
                HStack(spacing: 4) {
                    if isLargeChange(holding) {
                        StatusBadge(text: "30%↑", foreground: .loss, background: Color.lossSoft)
                    }
                    Text(deltaText(holding))
                        .font(.system(size: 10))
                        .foregroundStyle(deltaColor(holding))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(isActive ? Color.rowActive : Color.canvas)
        .overlay(alignment: .leading) {
            if isActive { Rectangle().fill(Color.ink).frame(width: 2) }
        }
        .overlay(Rectangle().fill(Color.rule).frame(height: 1), alignment: .bottom)
        .contentShape(Rectangle())
        .onTapGesture { focusedID = holding.id }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Text("값을 바꾸지 않고 넘기면 변동 없음으로 기록됩니다.\n고정 항목은 목록에서 빠지고, 월 1회 항목은 그 달에 값을 적고 나면 빠집니다.")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.faint)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                requestFinish()
            } label: {
                Text("점검 완료")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.onInk)
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

            Button("만") { multiplyFocused(by: 10_000) }
                .font(.system(size: 13))
            Button("억") { multiplyFocused(by: 100_000_000) }
                .font(.system(size: 13))

            Spacer()

            Text("\(min(currentIndex + 1, max(queue.count, 1))) / \(queue.count)")
                .font(.figure(11))
                .foregroundStyle(Color.muted)

            Spacer()

            Button("변동 없음") { move(1) }
                .font(.system(size: 13))
            Button(currentIndex >= queue.count - 1 ? "완료" : "다음") {
                if currentIndex >= queue.count - 1 { requestFinish() } else { move(1) }
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
            get: { holding.valueMinor == 0 ? "" : Won.grouped(holding.valueMinor) },
            set: {
                // **값이 실제로 바뀔 때만.** 포커스만 옮겨도 세터가 같은 값으로
                // 한 번 불리는데, 그때 기준값을 옮기면 증감이 사라진다 (CI 에서 잡음).
                let next = Int(String($0.filter(\.isNumber).prefix(15))) ?? 0
                guard next != holding.valueMinor else { return }
                // 이번 주 처음 손대는 순간 직전 값을 기준값으로 (91번).
                holding.rollBaselineIfNewWeek()
                holding.valueMinor = next
            }
        )
    }

    /// 키보드 위 `만` · `억` (93번, B3). 12 → 만 → 120,000.
    private func multiplyFocused(by factor: Int) {
        guard let focusedID, let holding = queue.first(where: { $0.id == focusedID }) else { return }
        let next = holding.valueMinor * factor
        guard holding.valueMinor > 0, next < 1_000_000_000_000_000 else { return }
        holding.rollBaselineIfNewWeek()
        holding.valueMinor = next
    }

    /// 기준값은 이번 주 처음 손대기 직전의 값이라 늘 "지난주" 다 (91번).
    private func baselineLabel(_ holding: Holding) -> String { "지난주" }

    private func deltaText(_ holding: Holding) -> String {
        let delta = holding.valueMinor - holding.lastEnteredValueMinor
        guard holding.lastEnteredValueMinor != 0 else { return "첫 기록" }
        guard delta != 0 else { return "변동 없음" }
        let percent = Decimal(abs(delta)) / Decimal(holding.lastEnteredValueMinor)
        let sign = delta > 0 ? "+" : "-"
        return "\(sign)\(Won.grouped(abs(delta))) · \(PercentFormatter.oneDecimal(percent))%"
    }

    /// 부채는 늘어나는 것이 나쁜 일이다. 같은 +112,500 이라도 자산이면 초록,
    /// 마이너스통장이면 빨강이어야 한다.
    private func deltaColor(_ holding: Holding) -> Color {
        guard holding.lastEnteredValueMinor != 0 else { return .faint }
        let delta = holding.valueMinor - holding.lastEnteredValueMinor
        guard delta != 0 else { return .faint }
        let isLiability = holding.account?.kind.isLiability ?? false
        let isGood = isLiability ? delta < 0 : delta > 0
        return isGood ? .gain : .loss
    }

    /// **주마다 기록은 하나다 — 뒤에 끝낸 사람이 갱신한다** (docs/09 4단계 정책).
    ///
    /// 넷이 각자 제 몫을 적는다. 첫 사람이 끝내면 그 주의 세션·스냅샷이 생기고,
    /// 다음 사람이 끝내면 **같은 것을 갱신**한다 — 새로 만들면 궤적에 한 주에
    /// 점이 둘 생겨 선이 꺾인다. 안 적은 구성원의 종목은 마지막 값 그대로다
    /// (종목이 현재값을 들고 있으니 따로 할 일이 없다). `totalCount` 는 가족
    /// 전체의 종목 수, `enteredCount` 는 이번 주에 누군가 적은 수다.
    private func finish() {
        let anchor = ReviewWeek.anchor(for: .now)
        let allHoldings = members
            .flatMap { $0.sortedAccounts }
            .flatMap { $0.sortedHoldings }
        let rollup = Valuation.rollUp(allHoldings.compactMap { $0.position() }, base: .krw)

        let previous = sessions
            .filter { $0.isComplete && $0.weekAnchor < anchor }
            .max { $0.weekAnchor < $1.weekAnchor }

        // 적었다는 시각만 찍는다. 기준값은 이번 주 처음 손댄 순간 이미 옮겨졌고
        // (91번), 안 건드린 종목은 기준값 == 현재값이라 "변동 없음" 이 맞다.
        for holding in queue {
            holding.rollBaselineIfNewWeek()
            holding.lastEnteredAt = .now
        }
        let askedEveryWeek = allHoldings.filter { $0.isDue() || $0.wasEntered(thisWeekOf: .now) }
        let enteredThisWeek = askedEveryWeek.filter { $0.wasEntered(thisWeekOf: .now) }.count
        // **누구 몫이 적혔나** (C8). 그 구성원의 매주 묻는 종목이 이번 주 안에
        // 전부 적혔으면 적은 것으로 센다. 묻는 종목이 하나도 없는 구성원은
        // 적을 것이 없으므로 센다 — 그 사람 때문에 연속이 끊기면 안 된다.
        var enteredMembers: Set<UUID> = []
        for member in members {
            let asked = queue(for: member)
            if asked.allSatisfy({ ($0.lastEnteredAt ?? .distantPast) >= anchor }) {
                enteredMembers.insert(member.id)
            }
        }

        let existing = sessions.first { $0.weekAnchor == anchor }
        let session = existing ?? ReviewSession(context: context, weekAnchor: anchor, totalCount: 0)
        session.totalCount = askedEveryWeek.count
        session.enteredCount = enteredThisWeek
        session.isTotalOnly = false
        session.completedAt = session.completedAt ?? .now
        session.totalValueMinor = rollup.netWorth.minorUnits
        if existing == nil {
            session.previousTotalValueMinor = previous?.totalValueMinor ?? 0
        }
        // 이어서 끝낸 사람의 몫을 **더한다** — 앞사람이 적은 것을 지우지 않는다.
        session.setEnteredMembers(session.enteredMemberIDSet.union(enteredMembers))

        let snapshot = snapshots.first { $0.weekAnchor == anchor }
            ?? Snapshot(context: context, weekAnchor: anchor, netWorthMinor: 0,
                        investableMinor: 0, liabilitiesMinor: 0)
        snapshot.netWorthMinor = rollup.netWorth.minorUnits
        snapshot.investableMinor = rollup.investable.minorUnits
        snapshot.liabilitiesMinor = rollup.liabilities.minorUnits

        // 구성원별 분해를 함께 남긴다. 이게 없으면 나중에 이 점검을 다시 열었을 때
        // 총액은 그때 값인데 구성원별은 현재 값이라 합이 안 맞는다. 갱신이면
        // 옛 줄을 지우고 새로 적는다.
        for line in snapshot.sortedLines { context.delete(line) }
        for (position, member) in members.enumerated() {
            let line = SnapshotLine(context: context,
                memberID: member.id,
                memberName: member.name,
                valueMinor: (rollup.byMember[member.id] ?? .zero(.krw)).minorUnits,
                sortIndex: position
            )
            line.snapshot = snapshot
        }

        // **무엇이 언제 바뀌었나** 를 남긴다 (docs/08-feedback.md 29번).
        // 주간 점검은 이 앱에서 가장 자주 일어나는 변경이라 첫 줄에 온다.
        let previousTotal = Money(minorUnits: session.previousTotalValueMinor, currency: .krw)
        let summary = session.previousTotalValueMinor > 0
            ? "\(Won.compact(previousTotal)) → \(Won.compact(rollup.netWorth))"
            : "\(Won.compact(rollup.netWorth))"
        ChangeLogger.record(.weeklyEntry,
                            subject: "주간 점검 · 종목 \(queue.count)건" + (existing == nil ? "" : " (이어서)"),
                            summary: summary, in: context)

        // **선을 넘겼나** (88번). 지난 점검과 이번 점검 사이를 본다.
        let streakAfter = ReviewWeek.streak(
            completedAnchors: sessions.filter(\.isComplete).map(\.weekAnchor) + [anchor], asOf: .now)
        Celebrations.check(previousTotal: session.previousTotalValueMinor,
                           newTotal: rollup.netWorth.minorUnits,
                           firstTotal: snapshots.first.map(\.netWorthMinor),
                           targetMinor: plans.first?.targetAmountMinor ?? 0,
                           streak: streakAfter, in: context)

        focusedID = nil
        completed = session
    }
}
