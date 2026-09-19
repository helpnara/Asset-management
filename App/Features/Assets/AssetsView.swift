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
    /// 방금 만든 것의 id — 편집 시트의 `취소` 가 이걸 보고 지운다 (104번).
    @State private var newIDs: Set<UUID> = []
    /// 옮길 대상을 고르는 시트 (113번).
    @State private var movingHolding: Holding?
    @State private var movingAccount: Account?
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
            // 넓은 화면에서 한 줄이 끝에서 끝까지 늘어나지 않게 (161번).
            .readableWidth()
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
                    //
                    // **`+` 는 더하기 하나만 한다** (152번 2-4). 예전에는 메뉴를
                    // 열어 `구성원 추가` 를 한 번 더 골라야 했고, 그 안에 있던
                    // `구성원 순서` 때문에 순서를 바꾸는 길이 둘(`편집`, 이 메뉴)
                    // 이었다. 순서는 왼쪽 `편집` 하나로 모은다.
                    if canManageHousehold {
                        Button {
                            addMember()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("구성원 추가")
                    }
                }
            }
            // CI 가 구성원 편집 폼을 찍을 수 있게 하는 갈고리 (151번). 은퇴 연도
            // 스테퍼 · 세금 나라 · 색 견본이 제대로 섰는지 그림으로 본다.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-startMemberEdit"),
                      let first = members.first else { return }
                try? await Task.sleep(for: .milliseconds(400))
                editingMember = first
            }
            // 구성원 순서 시트 — `대표` 띠지가 맨 위 사람에게 서는지 (168번).
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-startMemberOrder") else { return }
                try? await Task.sleep(for: .milliseconds(400))
                isOrderingMembers = true
            }
            .onChange(of: route.wantsNewMember, initial: true) { _, wants in
                guard wants else { return }
                route.wantsNewMember = false
                addMember()
            }
            .sheet(isPresented: $isOrderingMembers) {
                MemberOrderView(members: members)
            }
            .sheet(item: $editingMember, onDismiss: { newIDs.removeAll() }) {
                MemberEditView(member: $0, isNew: newIDs.contains($0.id))
            }
            .sheet(item: $editingAccount, onDismiss: { newIDs.removeAll() }) {
                AccountEditView(account: $0, isNew: newIDs.contains($0.id))
            }
            .sheet(item: $editingHolding, onDismiss: { newIDs.removeAll() }) {
                HoldingEditView(holding: $0, isNew: newIDs.contains($0.id))
            }
            .navigationDestination(item: $targetingAccount) { AccountTargetView(account: $0) }
            .sheet(item: $movingHolding) { holding in
                MoveTargetSheet(title: holding.name.isEmpty ? "종목 옮기기" : "\(holding.name) 옮기기",
                                members: members.filter { mayEdit($0) },
                                pickAccounts: true,
                                current: holding.account?.id) { member, account in
                    if let account { move(holding, to: account) }
                }
            }
            .sheet(item: $movingAccount) { account in
                MoveTargetSheet(title: "\(account.weightLabel) 옮기기",
                                members: members.filter { mayEdit($0) },
                                pickAccounts: false,
                                current: account.owner?.id) { member, _ in
                    move(account, to: member)
                }
            }
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
                                .font(.scaled(12.5))
                                .foregroundStyle(Color.bodyText)
                            Text("구성원 · 지역 · 자산군 비중")
                                .font(.scaled(9.5))
                                .foregroundStyle(Color.faint)
                        }
                        Spacer()
                        Text(signedAmount(familyTotal, false))
                            .font(.figure(15, weight: .bold))
                            .foregroundStyle(Color.ink)
                            .fixedSize()
                            .layoutPriority(1)
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
                                    .font(.scaled(12.5))
                            }
                        }
                    }
                } header: {
                    memberHeader(member)
                }
            }

            // **순서 바꾸는 길은 하나다** (152번 2-4). 예전에는 `+` 메뉴에도
            // 있고 `편집` 에도 있어 둘이었다.
            //
            // **편집 모드에 매달지 않는다** (빌드 82 사용자 확인). 처음에는
            // `editMode` 가 켜졌을 때만 내놓았는데 줄이 아예 안 보였다 —
            // `EditButton` 이 만지는 `editMode` 는 목록을 감싼 컨테이너의
            // 환경값이라, **그 컨테이너를 만든 뷰 자신**(여기)에서 읽으면
            // 바뀌어도 오지 않는다. 안에 있는 자식 뷰라야 보인다.
            //
            // 자식 뷰로 옮겨 다시 숨길 수도 있지만, 숨은 손잡이를 찾게 하는
            // 것이 2-3 에서 고친 바로 그 문제였다. 목록 맨 끝에 조용히 둔다.
            //
            // **띠지의 뜻은 그 자리에 적는다** (168번, 사용자 요청). 참가자
            // 기기에는 순서 버튼이 없어도 `대표` 띠지는 보이므로 설명은 남긴다.
            if members.count > 1 && !isNarrowing {
                Section {
                    if canManageHousehold {
                        Button {
                            isOrderingMembers = true
                        } label: {
                            Label("구성원 순서 바꾸기", systemImage: "arrow.up.arrow.down")
                                .font(.scaled(12))
                                .foregroundStyle(Color.muted)
                        }
                        .buttonStyle(.plain)
                    }
                } footer: {
                    Text("맨 위 구성원이 가족 대표입니다 (`대표` 띠지). 계획 탭의 은퇴 목표가 이 사람의 은퇴 목표(연도 · 나이)를 따르고, 1페이지 로드맵의 나이도 이 사람 기준입니다." + (canManageHousehold ? " 대표를 바꾸려면 순서를 바꿔 맨 위에 두세요." : ""))
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
                        .font(.scaled(9, weight: .semibold))
                        .foregroundStyle(Color.faint)
                    Text(member.name.isEmpty ? "이름 없음" : member.name)
                        .font(.scaled(12, weight: .bold))
                        .foregroundStyle(Color.ink)
                    // **맨 위 사람이 가족 대표다** (168번). 순서가 곧 대표라 이
                    // 띠지가 "누가 대표인지" 를 보여 주는 자리다.
                    if member.objectID == members.familyHead?.objectID {
                        HeadBadge()
                    }
                    Text("\(member.age)세")
                        .font(.scaled(10))
                        .foregroundStyle(Color.faint)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // 접힌 상태가 정보 없는 상태가 되지 않게 한다.
            Text(signedAmount(total, false))
                .font(.figure(12, weight: .semibold))
                .foregroundStyle(Color.ink)
                .fixedSize()
                .layoutPriority(1)
            if let share = familyShare(member) {
                Text(share)
                    .font(.figure(10))
                    .foregroundStyle(Color.faint)
            }

            NavigationLink {
                MemberTrajectoryView(member: member)
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.scaled(11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.dad)

            if mayEdit(member) {
                Button("편집") { editingMember = member }
                    .font(.scaled(11))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.dad)
            }
        }
        .textCase(nil)
    }

    /// 계좌에 걸리는 일들 — `⋯` 버튼과 길게 누르기가 **같은 것**을 낸다.
    @ViewBuilder
    private func accountActions(_ account: Account) -> some View {
        if mayEdit(account.owner) {
            Button("계좌 편집") { editingAccount = account }
        }
        if account.canSetTargets {
            Button("목표 비중") { targetingAccount = account }
        }
        // **다른 구성원에게** (113번). 끌어 놓기는 List 안에서 안 잡혀 메뉴로.
        if mayEdit(account.owner) && members.filter({ mayEdit($0) }).count > 1 {
            Button("다른 구성원에게 옮기기…") { movingAccount = account }
        }
    }

    /// 낼 것이 하나도 없으면 `⋯` 를 그리지 않는다 — 눌러서 빈 메뉴가 뜨는 것은
    /// 잠긴 화면이 아니라 고장 난 화면으로 읽힌다.
    private func hasAccountActions(_ account: Account) -> Bool {
        mayEdit(account.owner) || account.canSetTargets
    }

    @ViewBuilder
    private func accountRows(_ account: Account) -> some View {
        Button {
            toggle(account)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded(account) ? "chevron.down" : "chevron.right")
                    .font(.scaled(8, weight: .semibold))
                    .foregroundStyle(Color.faint)
                Text(account.name.isEmpty ? account.kind.label : account.name)
                    .font(.scaled(13))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                // **메모(기관 · 주소)는 한 줄에서 접는다** (170번). 아무리 길어도
                // 금액을 못 민다 — 금액이 우선순위를 갖는다.
                if !account.institution.isEmpty {
                    Text(account.institution)
                        .font(.scaled(10))
                        .foregroundStyle(Color.faint)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                    .fixedSize()
                    .layoutPriority(1)
                // **보이는 손잡이** (152번 2-3). 계좌를 고치고 옮기는 길이
                // 길게 누르기 안에만 있었다 — 알려 주지 않으면 발견되지 않는
                // 길이고, 실제로 "옮기기가 작동 안 함"(4번) 이 그 오해였다.
                // 길게 누르기는 그대로 두고 같은 메뉴를 버튼으로도 낸다.
                if hasAccountActions(account) {
                    Menu {
                        accountActions(account)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.scaled(12, weight: .semibold))
                            .foregroundStyle(Color.faint)
                            .frame(width: Font.scaledLength(24),
                                   height: Font.scaledLength(24))
                            .contentShape(Rectangle())
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 길게 눌러도 같은 메뉴가 나온다.
        .contextMenu { accountActions(account) }

        if isExpanded(account) || isNarrowing {
            ForEach(visibleHoldings(account)) { holding in
                if mayEdit(account.owner) {
                    Button {
                        editingHolding = holding
                    } label: {
                        holdingRow(holding)
                    }
                    // **다른 계좌로** (113번). 길게 누르면 메뉴.
                    .contextMenu {
                        Button("종목 편집") { editingHolding = holding }
                        Button("다른 계좌로 옮기기…") { movingHolding = holding }
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
                                .font(.scaled(12))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.dad)
                    }

                    if account.canSetTargets {
                        Button {
                            targetingAccount = account
                        } label: {
                            Label("목표 비중", systemImage: "chart.pie")
                                .font(.scaled(12))
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
        holding.driftSlice(tolerance: Plan.primary(plans)?.driftTolerance ?? Allocation.Tolerance())
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
    /// 이 사람이 **가족 전체 자산에서** 차지하는 몫 (152번 2-5).
    ///
    /// 바로 아래 계좌 줄의 `%` 는 **그 사람 안에서**의 몫이라 기준이 다르다.
    /// 기준이 다른 것은 의도이고(2026-09-17 사용자), 같은 자리 같은 꼴이라
    /// 읽는 쪽이 헷갈리던 것만 고친다 — 구성원 줄에만 `가족의` 를 붙인다.
    /// 계좌 줄은 바로 위가 그 사람이라 기준이 자명해 그대로 둔다.
    private func familyShare(_ member: Member) -> String? {
        guard let slice = memberSlices.first(where: { $0.key == member.id.uuidString })
        else { return nil }
        return "가족의 \(slice.actualPercent)%"
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
                        .font(.scaled(12.5))
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
                    .font(.scaled(9.5))
                    .foregroundStyle(Color.faint)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(signedAmount(holding.valueMinor, holding.account?.kind.isLiability ?? false))
                    .font(.figure(12.5))
                    .foregroundStyle((holding.account?.kind.isLiability ?? false) ? Color.loss : Color.ink)
                    .fixedSize()
                    .layoutPriority(1)
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
                .font(.scaled(15, weight: .bold))
                .foregroundStyle(Color.ink)
            Text("아빠 · 엄마 · 아들 · 딸처럼 가족 단위로 나눠 관리합니다.\n한 명만 넣어도 시작할 수 있습니다.")
                .font(.scaled(12.5))
                .foregroundStyle(Color.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            if canManageHousehold {
                Button("구성원 추가") { addMember() }
                    .font(.scaled(13, weight: .medium))
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

    /// **목록은 `억 + 만` 축약이다** (170번, 설계 2.7). 훑어보는 화면이라 자릿수보다
    /// 규모가 먼저고, 아홉 자리 원 단위는 긴 메모와 폭을 다투다 두 줄로 밀렸다.
    /// 만 원 아래는 버린다 — 정확한 값은 편집 폼과 주간 점검에 원 단위로 있다.
    /// 부채는 부호로 구분한다 — 같은 450만 이 자산인지 빚인지 헷갈리면 안 된다.
    private func signedAmount(_ minorUnits: Int, _ isLiability: Bool) -> String {
        (isLiability ? "-" : "") + Won.abbreviated(Money(minorUnits: minorUnits, currency: .krw))
    }

    private func addMember() {
        // 아직 안 쓴 색을 준다 (151번). 넷을 다 쓰고 있으면 순번대로 돌린다.
        let used = Set(members.map(\.colorIndex))
        let color = (0..<Color.memberPalette.count).first { !used.contains($0) } ?? members.count
        let member = Member(context: context, name: "", colorIndex: color, sortIndex: members.count)
        newIDs.insert(member.id)
        editingMember = member
    }

    private func addAccount(to member: Member) {
        let account = Account(context: context, name: "", owner: member, sortIndex: member.sortedAccounts.count)
        newIDs.insert(account.id)
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
        newIDs.insert(holding.id)
        editingHolding = holding
    }

    // MARK: - 옮기기 (docs/08-feedback.md 113번)

    /// 종목을 다른 계좌로. 편집 시트의 "소속" 과 같은 일이다.
    private func move(_ holding: Holding, to account: Account) {
        guard mayEdit(account.owner), mayEdit(holding.account?.owner), holding.account != account else { return }
        let before = holding.account?.weightLabel ?? "이름 없음"
        holding.account = account
        holding.accountID = account.id
        holding.sortIndex = account.sortedHoldings.count
        if !account.kind.allowedAssetClasses.contains(holding.assetClass) {
            holding.assetClass = account.kind.defaultAssetClass
        }
        let owner = account.owner?.name ?? ""
        let name = holding.name.isEmpty ? "이름 없음" : holding.name
        ChangeLogger.structureChanged(
            [owner, account.weightLabel, name].filter { !$0.isEmpty }.joined(separator: " · "),
            "종목을 \(before) 에서 옮겼습니다", in: context)
        // 옮긴 계좌가 접혀 있으면 펼친다 — 옮긴 것이 보여야 옮겨졌다고 믿는다.
        if !isExpanded(account) { toggle(account) }
    }

    /// 계좌를 다른 구성원에게.
    private func move(_ account: Account, to member: Member) {
        guard mayEdit(member), mayEdit(account.owner), account.owner != member else { return }
        let before = account.owner?.name ?? "이름 없음"
        account.owner = member
        account.ownerID = member.id
        account.sortIndex = member.sortedAccounts.count
        ChangeLogger.structureChanged(
            [member.name, account.weightLabel].filter { !$0.isEmpty }.joined(separator: " · "),
            "계좌를 \(before) 에서 옮겼습니다", in: context)
        if !isExpanded(member) { toggle(member) }
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
    @Environment(\.managedObjectContext) private var context

    /// **이 화면이 직접 들고 있는 순서** (168번 6번 후속).
    ///
    /// 예전에는 부모가 넘긴 `members` 를 그대로 그리고 `onMove` 에서 `sortIndex`
    /// 만 바꿨다. 그러면 새 순서가 부모의 `@Fetched` 를 거쳐 시트로 되돌아와야
    /// 줄이 옮겨 가는데, 시트가 떠 있는 동안 그 갱신이 오지 않으면 끌어 놓은
    /// 줄이 제자리로 튕기고 띠지도 안 옮겨 간다 — 기기에서 그렇게 보였다.
    /// 순서는 여기서 움직이고, 저장소에는 그때그때 적고 곧바로 저장한다.
    @State private var order: [Member] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { member in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.member(member.colorIndex))
                                .frame(width: 10, height: 10)
                            Text(member.name.isEmpty ? "이름 없음" : member.name)
                                .font(.scaled(13))
                                .foregroundStyle(Color.ink)
                            Text(member.roleNote)
                                .font(.scaled(10))
                                .foregroundStyle(Color.faint)
                            // **맨 위가 가족 대표다** (168번). 순서가 곧 대표라
                            // 여기 표시가 "정하는 자리" 다. 따로 고르는 칸은 없다.
                            if member.objectID == order.first?.objectID {
                                HeadBadge()
                            }
                        }
                    }
                    .onMove { offsets, destination in
                        order.move(fromOffsets: offsets, toOffset: destination)
                        apply()
                    }
                } footer: {
                    Text("맨 위 사람이 가족 대표입니다 — 자산 탭 이름 옆에 `대표` 띠지가 붙고, 계획 탭의 은퇴 목표가 이 사람의 은퇴 목표(연도 · 나이)로 자동 설정됩니다. 1페이지 로드맵의 나이도 이 사람 기준입니다.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .onAppear {
                if order.isEmpty { order = members }
            }
            .navigationTitle("구성원 순서")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        apply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    /// 화면의 순서를 `sortIndex` 에 적고 **바로 저장한다.** 자동 저장(400ms)을
    /// 기다리지 않는 이유는, 시트를 닫는 순간 자산 탭과 계획 탭이 새 대표를
    /// 읽어야 하기 때문이다 — 저장 전이면 두 화면이 옛 대표를 한 번 더 그린다.
    private func apply() {
        for (position, member) in order.enumerated() where member.sortIndex != position {
            member.sortIndex = position
        }
        // 대표가 바뀌면 계획의 은퇴 목표도 새 대표의 것으로 (168번).
        Plan.primary(context.all(Plan.self))?.adoptRetirementYear(fromHeadOf: order)
        guard context.hasChanges else { return }
        try? context.save()
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


/// 옮길 곳을 고르는 시트 (113번). 종목이면 계좌를, 계좌면 구성원을 고른다.
struct MoveTargetSheet: View {
    let title: String
    let members: [Member]
    let pickAccounts: Bool
    let current: UUID?
    let onPick: (Member, Account?) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(members) { member in
                    if pickAccounts {
                        Section(member.name.isEmpty ? "이름 없음" : member.name) {
                            ForEach(member.sortedAccounts.filter { !$0.isArchived }) { account in
                                Button {
                                    onPick(member, account)
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(account.weightLabel)
                                            .foregroundStyle(Color.ink)
                                        if !account.institution.isEmpty {
                                            Text(account.institution)
                                                .font(.scaled(11))
                                                .foregroundStyle(Color.faint)
                                        }
                                        Spacer()
                                        if account.id == current {
                                            Text("지금 여기")
                                                .font(.scaled(11))
                                                .foregroundStyle(Color.muted)
                                        }
                                    }
                                }
                                .disabled(account.id == current)
                            }
                        }
                    } else {
                        Button {
                            onPick(member, nil)
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                Circle().fill(Color.member(member.colorIndex)).frame(width: 10, height: 10)
                                Text(member.name.isEmpty ? "이름 없음" : member.name)
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                if member.id == current {
                                    Text("지금 여기")
                                        .font(.scaled(11))
                                        .foregroundStyle(Color.muted)
                                }
                            }
                        }
                        .disabled(member.id == current)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
