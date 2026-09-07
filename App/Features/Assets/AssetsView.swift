import Core
import SwiftData
import SwiftUI

/// 계속 입력하는 화면. 구성원 → 계좌 → 종목 3단.
///
/// **두 겹으로 접힌다.** 기본은 구성원 펼침 · 계좌 접힘이다. 그러면 첫 화면이
/// "누가 어떤 계좌를 얼마나 갖고 있나" 가 되는데, 그게 평소에 보고 싶은 층이다.
/// 예전에는 계좌와 종목과 `종목 추가` 줄이 전부 펼쳐져 있어 가족 넷이면
/// 스크롤이 끝없이 길었다 (docs/08-feedback.md 6번).
///
/// 접힘 상태는 `@AppStorage` 에 둔다. `@Model` 에 넣으면 CloudKit 스키마가
/// 바뀌는데, 화면 접힘 같은 것 때문에 스키마 배포를 만들 이유가 없다.
struct AssetsView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @Environment(\.modelContext) private var context
    @Query(sort: \Member.sortIndex) private var members: [Member]
    @Query private var plans: [Plan]

    @State private var editingMember: Member?
    @State private var editingAccount: Account?
    @State private var editingHolding: Holding?
    @State private var targetingAccount: Account?
    @State private var pendingHoldingDelete: HoldingDeleteRequest?
    @State private var isOrderingMembers = false
    @State private var route = AppRoute.shared
    /// CI 가 비중 화면들을 찍을 수 있게 하는 갈고리. 계산이 가장 많은 화면들인데
    /// 그림이 없으면 원격 세션에서 확인할 방법이 없다.
    @State private var showFamilyAllocation = ProcessInfo.processInfo.arguments
        .contains("-startFamilyAllocation")
    @State private var showAccountTargets = ProcessInfo.processInfo.arguments
        .contains("-startAccountTargets")

    /// 펼쳐 둔 계좌·구성원의 UUID. 기기마다 따로 기억된다 — 접힘은 원래
    /// 기기별로 다른 게 자연스럽다.
    @AppStorage("assets.expandedAccounts") private var expandedAccountsRaw = ""
    @AppStorage("assets.collapsedMembers") private var collapsedMembersRaw = ""

    var body: some View {
        NavigationStack {
            Group {
                if members.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("자산")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !members.isEmpty {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            addMember()
                        } label: {
                            Label("구성원 추가", systemImage: "person.badge.plus")
                        }
                        if members.count > 1 {
                            Button {
                                isOrderingMembers = true
                            } label: {
                                Label("구성원 순서", systemImage: "arrow.up.arrow.down")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onChange(of: route.wantsNewMember, initial: true) { _, wants in
                guard wants else { return }
                route.wantsNewMember = false
                addMember()
            }
            .sheet(isPresented: $isOrderingMembers) {
                MemberOrderView(members: members)
            }
            .sheet(item: $editingMember) { MemberEditView(member: $0) }
            .sheet(item: $editingAccount) { AccountEditView(account: $0) }
            .sheet(item: $editingHolding) { HoldingEditView(holding: $0) }
            .navigationDestination(item: $targetingAccount) { AccountTargetView(account: $0) }
            // 밀어 지우기도 확인을 거친다. 여기서 지우는 것은 그 종목에 적어 온
            // 평가액 전부라 되돌릴 방법이 없다 (docs/08-feedback.md 16번).
            .confirmationDialog("종목을 삭제할까요?",
                                isPresented: Binding(get: { pendingHoldingDelete != nil },
                                                     set: { if !$0 { pendingHoldingDelete = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingHoldingDelete) { request in
                Button("삭제", role: .destructive) {
                    delete(request.offsets, from: request.account)
                    pendingHoldingDelete = nil
                }
                Button("취소", role: .cancel) { pendingHoldingDelete = nil }
            } message: { request in
                Text("\(request.names) · 적어 온 평가액이 함께 사라집니다. 되돌릴 수 없습니다.")
            }
            .navigationDestination(isPresented: $showFamilyAllocation) {
                FamilyAllocationView()
            }
            .navigationDestination(isPresented: $showAccountTargets) {
                if let account = members.first?.sortedAccounts.first(where: \.canSetTargets) {
                    AccountTargetView(account: account)
                }
            }
        }
    }

    private var list: some View {
        List {
            Section {
                NavigationLink {
                    FamilyAllocationView()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("가족 총자산")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.bodyText)
                            Text("구성원 · 지역 · 자산군 비중")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.faint)
                        }
                        Spacer()
                        Text(signedAmount(familyTotal, false))
                            .font(.figure(15, weight: .bold))
                            .foregroundStyle(Color.ink)
                    }
                }
            }

            ForEach(members) { member in
                Section {
                    if isExpanded(member) {
                        ForEach(member.sortedAccounts) { account in
                            accountRows(account)
                        }
                        Button {
                            addAccount(to: member)
                        } label: {
                            Label("계좌 추가", systemImage: "plus")
                                .font(.system(size: 12.5))
                        }
                    }
                } header: {
                    memberHeader(member)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func memberHeader(_ member: Member) -> some View {
        let total = memberTotal(member)
        return HStack(spacing: 6) {
            Button {
                toggle(member)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded(member) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.faint)
                    Text(member.name.isEmpty ? "이름 없음" : member.name)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Text("\(member.age)세")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.faint)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // 접힌 상태가 정보 없는 상태가 되지 않게 한다.
            Text(signedAmount(total, false))
                .font(.figure(12, weight: .semibold))
                .foregroundStyle(Color.ink)
            if let share = familyShare(total) {
                Text(share)
                    .font(.figure(10))
                    .foregroundStyle(Color.faint)
            }

            NavigationLink {
                MemberTrajectoryView(member: member)
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dad)

            Button("편집") { editingMember = member }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundStyle(Color.dad)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func accountRows(_ account: Account) -> some View {
        Button {
            toggle(account)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded(account) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.faint)
                Text(account.name.isEmpty ? account.kind.label : account.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink)
                if !account.institution.isEmpty {
                    Text(account.institution)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.faint)
                }
                if account.kind.isLiability {
                    StatusBadge(text: "부채", foreground: .loss, background: Color.lossSoft)
                } else if !account.kind.countsAsInvestable {
                    StatusBadge(text: "투자자산 제외")
                }
                if account.canSetTargets && account.targetSumBP != 10_000 {
                    StatusBadge(text: "목표 미완",
                                foreground: .loss,
                                background: Color.lossSoft)
                }
                Spacer()
                // 이 계좌가 **주인의 자산에서** 차지하는 몫. 목표는 없다 —
                // 계좌 잔고는 급여와 납입 한도가 정하는 값이다.
                if let share = memberShare(of: account) {
                    Text(share)
                        .font(.figure(10))
                        .foregroundStyle(Color.faint)
                }
                Text(signedAmount(accountTotal(account).minorUnits, account.kind.isLiability))
                    .font(.figure(12.5, weight: .medium))
                    .foregroundStyle(account.kind.isLiability ? Color.loss : Color.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 계좌 자체를 고치는 길. 펼치기와 겹치지 않게 길게 눌러 연다.
        .contextMenu {
            Button("계좌 편집") { editingAccount = account }
            if account.canSetTargets {
                Button("목표 비중") { targetingAccount = account }
            }
        }

        if isExpanded(account) {
            ForEach(account.sortedHoldings) { holding in
                Button {
                    editingHolding = holding
                } label: {
                    holdingRow(holding)
                }
            }
            .onDelete { pendingHoldingDelete = HoldingDeleteRequest(account: account, offsets: $0) }
            .onMove { offsets, destination in
                move(offsets, to: destination, in: account)
            }

            HStack(spacing: 14) {
                Button {
                    addHolding(to: account)
                } label: {
                    Label("종목 추가", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.dad)

                if account.canSetTargets {
                    Button {
                        targetingAccount = account
                    } label: {
                        Label("목표 비중", systemImage: "chart.pie")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dad)
                }
            }
            .padding(.leading, 12)
        }
    }

    /// 이 종목이 **자기 계좌 안에서** 어느 상태인가 (docs/08-feedback.md 15번).
    private func driftSlice(_ holding: Holding) -> Allocation.Slice? {
        holding.driftSlice(tolerance: plans.first?.driftTolerance ?? Allocation.Tolerance())
    }

    /// 이 계좌가 주인의 자산에서 차지하는 몫.
    private func memberShare(of account: Account) -> String? {
        guard !account.kind.isLiability, let owner = account.owner else { return nil }
        let total = owner.assetTotalMinor
        guard total > 0, account.totalMinor > 0 else { return nil }
        return "\(PercentFormatter.oneDecimal(Decimal(account.totalMinor) / Decimal(total)))%"
    }

    // MARK: - 접기 · 펼치기

    private func isExpanded(_ member: Member) -> Bool {
        !collapsedMembersRaw.split(separator: ",").contains(Substring(member.id.uuidString))
    }

    private func isExpanded(_ account: Account) -> Bool {
        expandedAccountsRaw.split(separator: ",").contains(Substring(account.id.uuidString))
    }

    private func toggle(_ member: Member) {
        var ids = Set(collapsedMembersRaw.split(separator: ",").map(String.init))
        let key = member.id.uuidString
        if ids.contains(key) { ids.remove(key) } else { ids.insert(key) }
        collapsedMembersRaw = ids.sorted().joined(separator: ",")
    }

    private func toggle(_ account: Account) {
        var ids = Set(expandedAccountsRaw.split(separator: ",").map(String.init))
        let key = account.id.uuidString
        if ids.contains(key) { ids.remove(key) } else { ids.insert(key) }
        expandedAccountsRaw = ids.sorted().joined(separator: ",")
    }

    // MARK: - 합계

    private func memberTotal(_ member: Member) -> Int {
        member.sortedAccounts.reduce(0) { sum, account in
            let value = accountTotal(account).minorUnits
            return sum + (account.kind.isLiability ? -value : value)
        }
    }

    private var familyTotal: Int {
        members.reduce(0) { $0 + memberTotal($1) }
    }

    /// 가족 안에서 이 사람이 차지하는 비중. 합계가 0이거나 음수면 적지 않는다.
    private func familyShare(_ total: Int) -> String? {
        guard familyTotal > 0, total > 0 else { return nil }
        let fraction = Decimal(total) / Decimal(familyTotal)
        return "\(PercentFormatter.oneDecimal(fraction))%"
    }

    private func holdingRow(_ holding: Holding) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(holding.name.isEmpty ? "이름 없음" : holding.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.bodyText)
                    if holding.status != .accumulating {
                        StatusBadge(text: holding.status.label,
                                    foreground: holding.status.badgeForeground,
                                    background: holding.status.badgeBackground)
                    }
                    if holding.violatesPFIC {
                        StatusBadge(text: "PFIC",
                                    foreground: .loss,
                                    background: Color.lossSoft)
                    }
                    // 사용자가 요구한 자리 — **종목 이름 바로 옆**이다.
                    // 조치·주의만으로는 어떤 상황인지 알 수 없다는 지적이었다.
                    if let slice = driftSlice(holding) {
                        WeightLabel(slice: slice)
                    }
                }
                // 자산군 라벨("주식 · ETF")에 이미 가운뎃점이 있어 네 항목처럼 읽혔다.
                // 목록에서 실제로 궁금한 것은 상품 종류다.
                Text("\(holding.instrumentType.label) · \(holding.listingCountryCode) · \(holding.cadence.label)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.faint)
            }
            Spacer(minLength: 8)
            Text(signedAmount(holding.valueMinor, holding.account?.kind.isLiability ?? false))
                .font(.figure(12.5))
                .foregroundStyle((holding.account?.kind.isLiability ?? false) ? Color.loss : Color.ink)
        }
        .padding(.leading, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("구성원부터 추가하세요")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.ink)
            Text("아빠 · 엄마 · 아들 · 딸처럼 가족 단위로 나눠 관리합니다.\n한 명만 넣어도 시작할 수 있습니다.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button("구성원 추가") { addMember() }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .foregroundStyle(Color.onInk)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 3))
                .padding(.top, 4)
        }
        .padding(28)
    }

    // MARK: - 편집

    private func accountTotal(_ account: Account) -> Money {
        account.sortedHoldings.map(\.value).total(in: .krw)
    }

    /// 목록에서는 자릿수를 비교하는 게 목적이라 계좌 소계도 종목과 같은 원 단위로 적는다.
    /// 부채는 부호로 구분한다 — 같은 4,500,000 이 자산인지 빚인지 헷갈리면 안 된다.
    private func signedAmount(_ minorUnits: Int, _ isLiability: Bool) -> String {
        (isLiability ? "-" : "") + Won.grouped(minorUnits)
    }

    private func addMember() {
        let member = Member(name: "", colorIndex: members.count, sortIndex: members.count)
        context.insert(member)
        editingMember = member
    }

    private func addAccount(to member: Member) {
        let account = Account(name: "", owner: member, sortIndex: member.sortedAccounts.count)
        context.insert(account)
        editingAccount = account
    }

    private func addHolding(to account: Account) {
        // 점검 주기는 계좌 종류가 정해 준다. 새 종목이 무조건 `매주` 라서
        // 전세보증금까지 매주 물어봤다 (docs/08-feedback.md 의 Claude 질문 1).
        let holding = Holding(name: "", cadence: account.kind.defaultCadence,
                              account: account, sortIndex: account.sortedHoldings.count)
        context.insert(holding)
        editingHolding = holding
    }

    private func delete(_ offsets: IndexSet, from account: Account) {
        let items = account.sortedHoldings
        for index in offsets where items.indices.contains(index) {
            context.delete(items[index])
        }
    }

    private func move(_ offsets: IndexSet, to destination: Int, in account: Account) {
        var items = account.sortedHoldings
        items.move(fromOffsets: offsets, toOffset: destination)
        for (position, holding) in items.enumerated() {
            holding.sortIndex = position
        }
    }
}

/// 구성원 순서. 목록이 섹션으로 나뉘어 있어 제자리 드래그가 어려우므로 따로 뺐다.
struct MemberOrderView: View {
    let members: [Member]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(members) { member in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.member(member.colorIndex))
                            .frame(width: 10, height: 10)
                        Text(member.name.isEmpty ? "이름 없음" : member.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.ink)
                        Text(member.roleNote)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.faint)
                    }
                }
                .onMove { offsets, destination in
                    var items = members
                    items.move(fromOffsets: offsets, toOffset: destination)
                    for (position, member) in items.enumerated() {
                        member.sortIndex = position
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("구성원 순서")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

/// 밀어 지우려는 종목들. 확인 창이 이름을 읽어 "무엇이 사라지는지" 를 적는다.
struct HoldingDeleteRequest: Identifiable {
    let account: Account
    let offsets: IndexSet

    var id: String { "\(account.id)-\(offsets.map(String.init).joined(separator: ","))" }

    var names: String {
        let holdings = account.sortedHoldings
        let picked = offsets.compactMap { holdings.indices.contains($0) ? holdings[$0] : nil }
        return picked.map(\.weightLabel).joined(separator: " · ")
    }
}
