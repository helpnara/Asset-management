import Core
import CoreData
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

    @Environment(\.managedObjectContext) private var context
    // 보기 전용으로 열었을 때 고칠 자리를 감춘다 (docs/09-family-sharing.md).
    @Environment(\.canEdit) private var canEdit
    @Environment(\.self) private var environment
    @Environment(\.familyRole) private var role

    /// 이 구성원의 것을 고칠 수 있나 — 관리자는 전부, `editor` 는 본인 것만.
    private func mayEdit(_ member: Member?) -> Bool { environment.mayEdit(member) }
    @Environment(\.canManageHousehold) private var canManageHousehold
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]
    // **종목·계좌를 직접 감시한다** (docs/08-feedback.md 72번). 화면은 구성원에서
    // 관계를 따라 계좌·종목을 읽는데, 종목 값이 바뀌어도 구성원 자체는 안 바뀌어
    // 다시 그릴 이유가 없었다 — 접었다 펴거나 탭을 오가야 새 값이 보였다.
    // 이 둘이 바뀌면 화면이 다시 그려진다. 몸체가 한 번 읽어 줘야 확실하다.
    @Fetched private var holdings: [Holding]
    @Fetched private var accounts: [Account]

    @State private var refreshNote: String?
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

    /// **검색 · 정렬 · 필터** (95번, B4 · 설계 2.3.1). 검색어나 필터가 있으면
    /// 접힘을 무시하고 맞는 종목이 있는 계좌만 펼쳐 보인다.
    @State private var query = ""
    @AppStorage("assets.sort") private var sortRaw = HoldingSort.manual.rawValue
    @AppStorage("assets.filter") private var filterRaw = HoldingFilter.all.rawValue

    enum HoldingSort: String, CaseIterable, Identifiable {
        case manual, amount, name
        var id: String { rawValue }
        var label: String {
            switch self {
            case .manual: return "내 순서"
            case .amount: return "금액순"
            case .name: return "이름순"
            }
        }
    }

    enum HoldingFilter: String, CaseIterable, Identifiable {
        case all, pendingThisWeek, drifting
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "전부"
            case .pendingThisWeek: return "이번 주 미입력"
            case .drifting: return "비중 어긋남"
            }
        }
    }

    private var sort: HoldingSort { HoldingSort(rawValue: sortRaw) ?? .manual }
    private var filter: HoldingFilter { HoldingFilter(rawValue: filterRaw) ?? .all }
    private var isNarrowing: Bool { !query.isEmpty || filter != .all }

    /// 이 계좌에서 보일 종목. 검색어는 종목 이름과 계좌 이름·기관에 맞춘다.
    private func visibleHoldings(_ account: Account) -> [Holding] {
        var items = account.sortedHoldings
        if !query.isEmpty {
            let accountMatches = account.name.localizedCaseInsensitiveContains(query)
                || account.institution.localizedCaseInsensitiveContains(query)
            if !accountMatches {
                items = items.filter { $0.name.localizedCaseInsensitiveContains(query) }
            }
        }
        switch filter {
        case .all: break
        case .pendingThisWeek: items = items.filter { $0.isDue() && !$0.wasEntered(thisWeekOf: .now) }
        case .drifting: items = items.filter { driftSlice($0) != nil }
        }
        switch sort {
        case .manual: break
        case .amount: items.sort { $0.valueMinor > $1.valueMinor }
        case .name: items.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
        return items
    }

    var body: some View {
        // 감시 대상을 몸체가 읽는다 — 값은 안 쓰지만 이 줄이 다시 그리기를 잇는다.
        let _ = (holdings.count, accounts.count)
        NavigationStack {
            Group {
                if members.isEmpty {
                    if SyncLoadingHint.shouldShow {
                        SyncLoadingHint()
                    } else {
                        emptyState
                    }
                } else {
                    list.syncRefreshable(note: $refreshNote)
                        .searchable(text: $query, prompt: "종목 · 계좌 · 기관")
                }
            }
            .navigationTitle("자산")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !members.isEmpty && canEdit {
                        EditButton()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !members.isEmpty {
                        Menu {
                            Picker("정렬", selection: $sortRaw) {
                                ForEach(HoldingSort.allCases) { Text($0.label).tag($0.rawValue) }
                            }
                            Picker("보기", selection: $filterRaw) {
                                ForEach(HoldingFilter.allCases) { Text($0.label).tag($0.rawValue) }
                            }
                        } label: {
                            Image(systemName: isNarrowing || sort != .manual
                                  ? "line.3.horizontal.decrease.circle.fill"
                                  : "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // 구성원을 더하고 지우는 것은 가구 전체에 걸리는 일이라
                    // 관리자만이다.
                    if canManageHousehold {
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

            if role == .editor && !members.contains(where: { mayEdit($0) }) {
                Section {
                    ReadOnlyNote(text: "변경 권한은 있지만 고칠 수 있는 구성원이 아직 없습니다. 관리자가 더보기 → 가족 → 편집 권한에서 정합니다.")
                }
            }

            ForEach(members) { member in
                Section {
                    if isExpanded(member) || isNarrowing {
                        ForEach(member.sortedAccounts.filter { !isNarrowing || !visibleHoldings($0).isEmpty }) { account in
                            accountRows(account)
                        }
                        if mayEdit(member) && !isNarrowing {
                            Button {
                                addAccount(to: member)
                            } label: {
                                Label("계좌 추가", systemImage: "plus")
                                    .font(.system(size: 12.5))
                            }
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
            if let share = familyShare(member) {
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

            if mayEdit(member) {
                Button("편집") { editingMember = member }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dad)
            }
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
                if account.hasIncompleteTargets {
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
            if mayEdit(account.owner) {
                Button("계좌 편집") { editingAccount = account }
            }
            if account.canSetTargets {
                Button("목표 비중") { targetingAccount = account }
            }
        }

        if isExpanded(account) || isNarrowing {
            ForEach(visibleHoldings(account)) { holding in
                if mayEdit(account.owner) {
                    Button {
                        editingHolding = holding
                    } label: {
                        holdingRow(holding)
                    }
                } else {
                    // 눌러도 열 것이 없으면 누를 수 있게 두지 않는다.
                    holdingRow(holding)
                }
            }
            // 삼항 안의 클로저에는 타입을 적는다. `$0` 로 두면 `nil` 쪽 때문에
            // 추론할 근거가 없어 컴파일러가 막는다.
            // 좁혀 보거나 정렬을 바꾼 상태에서는 위치가 원래 순서와 달라 밀어
            // 지우기·끌기를 잠근다 — 엉뚱한 종목이 지워진다.
            .onDelete(perform: mayEdit(account.owner) && !isNarrowing && sort == .manual ? { (offsets: IndexSet) in
                pendingHoldingDelete = HoldingDeleteRequest(account: account, offsets: offsets)
            } : nil)
            .onMove(perform: mayEdit(account.owner) && !isNarrowing && sort == .manual ? { (offsets: IndexSet, destination: Int) in
                move(offsets, to: destination, in: account)
            } : nil)

            // 버튼이 하나도 없으면 줄 자체를 안 만든다 — 빈 HStack 도 목록의
            // 한 줄이라 종목 아래에 빈 칸이 남는다 (65번, 보기 전용·현금성 계좌).
            if (mayEdit(account.owner) || account.canSetTargets) && !isNarrowing {
                HStack(spacing: 14) {
                    if mayEdit(account.owner) {
                        Button {
                            addHolding(to: account)
                        } label: {
                            Label("종목 추가", systemImage: "plus")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.dad)
                    }

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
    }

    /// 이 종목이 **자기 계좌 안에서** 어느 상태인가 (docs/08-feedback.md 15번).
    private func driftSlice(_ holding: Holding) -> Allocation.Slice? {
        holding.driftSlice(tolerance: plans.first?.driftTolerance ?? Allocation.Tolerance())
    }

    /// 이 계좌가 주인의 자산에서 차지하는 몫.
    ///
    /// **정수로 적되 같은 사람의 계좌 합이 100 이 되어야** 한다. 그래서 줄마다
    /// 따로 반올림하지 않고 `accountSlices` 가 최대잔여법으로 맞춰 둔 값을
    /// 꺼내 쓴다 (docs/08-feedback.md 18번).
    private func memberShare(of account: Account) -> String? {
        guard !account.kind.isLiability, let owner = account.owner else { return nil }
        // **이름이 아니라 계좌 자신으로 찾는다.** 이름으로 찾으면 같은 이름의
        // 계좌 둘이 같은 줄을 가리켜 둘 다 100% 로 보였다 (30번).
        guard let slice = owner.accountSlices.first(where: { $0.key == account.id.uuidString })
        else { return nil }
        return "\(slice.actualPercent)%"
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

    /// 가족 안에서 이 사람이 차지하는 비중. 여기도 합이 100 이 되게 맞춘 값을 쓴다.
    private func familyShare(_ member: Member) -> String? {
        guard let slice = memberSlices.first(where: { $0.key == member.id.uuidString })
        else { return nil }
        return "\(slice.actualPercent)%"
    }

    /// 한 번만 계산해서 여러 줄이 나눠 쓴다.
    private var memberSlices: [Allocation.Slice] {
        FamilyAllocation.memberSlices(members)
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
            VStack(alignment: .trailing, spacing: 2) {
                Text(signedAmount(holding.valueMinor, holding.account?.kind.isLiability ?? false))
                    .font(.figure(12.5))
                    .foregroundStyle((holding.account?.kind.isLiability ?? false) ? Color.loss : Color.ink)
                // **이번 주 증감** (91번, B6). 이번 주에 적힌 것만 — 지난주 값은
                // 이번 주 처음 손댈 때 기준값으로 옮겨진다.
                if let delta = holding.deltaThisWeekMinor {
                    let isLiability = holding.account?.kind.isLiability ?? false
                    let isGood = isLiability ? delta < 0 : delta > 0
                    Text(Won.compact(Money(minorUnits: delta, currency: .krw), sign: .always))
                        .font(.figure(9.5))
                        .foregroundStyle(isGood ? Color.gain : Color.loss)
                }
            }
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
            if canManageHousehold {
                Button("구성원 추가") { addMember() }
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .foregroundStyle(Color.onInk)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 3))
                    .padding(.top, 4)
            } else {
                // 참가자가 빈 화면을 봤다면 아직 동기화가 안 온 것이다.
                ReadOnlyNote(text: "관리자가 구성원을 넣으면 여기에 보입니다.")
                    .padding(.top, 4)
            }
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
        let member = Member(context: context, name: "", colorIndex: members.count, sortIndex: members.count)
        editingMember = member
    }

    private func addAccount(to member: Member) {
        let account = Account(context: context, name: "", owner: member, sortIndex: member.sortedAccounts.count)
        editingAccount = account
    }

    private func addHolding(to account: Account) {
        // 점검 주기는 계좌 종류가 정해 준다. 새 종목이 무조건 `매주` 라서
        // 전월세보증금까지 매주 물어봤다 (docs/08-feedback.md 의 Claude 질문 1).
        // 자산군과 상품 종류도 계좌가 정해 준다 — 전월세보증금 계좌에 새 종목이
        // `주식 · ETF / 개별주` 로 뜨지 않게 (docs/08-feedback.md 50번).
        let assetClass = account.kind.defaultAssetClass
        let holding = Holding(context: context, name: "", assetClass: assetClass,
                              instrumentType: assetClass.defaultInstrumentType,
                              cadence: account.kind.defaultCadence,
                              account: account, sortIndex: account.sortedHoldings.count)
        editingHolding = holding
    }

    private func delete(_ offsets: IndexSet, from account: Account) {
        let items = account.sortedHoldings
        for index in offsets where items.indices.contains(index) {
            let holding = items[index]
            let owner = account.owner?.name ?? ""
            let name = holding.name.isEmpty ? "이름 없음" : holding.name
            ChangeLogger.structureChanged(
                [owner, account.weightLabel, name].filter { !$0.isEmpty }.joined(separator: " · "),
                "종목을 삭제했습니다", in: context
            )
            context.delete(holding)
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
