import Core
import SwiftData
import SwiftUI

/// 계속 입력하는 화면. 구성원 → 계좌 → 종목 3단.
struct AssetsView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @Environment(\.modelContext) private var context
    @Query(sort: \Member.sortIndex) private var members: [Member]

    @State private var editingMember: Member?
    @State private var editingAccount: Account?
    @State private var editingHolding: Holding?
    @State private var isOrderingMembers = false
    @State private var route = AppRoute.shared

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
        }
    }

    private var list: some View {
        List {
            ForEach(members) { member in
                Section {
                    ForEach(member.sortedAccounts) { account in
                        accountRows(account)
                    }
                    Button {
                        addAccount(to: member)
                    } label: {
                        Label("계좌 추가", systemImage: "plus")
                            .font(.system(size: 12.5))
                    }
                } header: {
                    memberHeader(member)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func memberHeader(_ member: Member) -> some View {
        HStack {
            Text(member.name.isEmpty ? "이름 없음" : member.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.ink)
            Text("\(member.age)세")
                .font(.system(size: 10))
                .foregroundStyle(Color.faint)
            Spacer()
            Button("편집") { editingMember = member }
                .font(.system(size: 11))
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func accountRows(_ account: Account) -> some View {
        Button {
            editingAccount = account
        } label: {
            HStack(spacing: 6) {
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
                Spacer()
                Text(signedAmount(accountTotal(account).minorUnits, account.kind.isLiability))
                    .font(.figure(12.5, weight: .medium))
                    .foregroundStyle(account.kind.isLiability ? Color.loss : Color.ink)
            }
        }

        ForEach(account.sortedHoldings) { holding in
            Button {
                editingHolding = holding
            } label: {
                holdingRow(holding)
            }
        }
        .onDelete { offsets in
            delete(offsets, from: account)
        }
        .onMove { offsets, destination in
            move(offsets, to: destination, in: account)
        }

        Button {
            addHolding(to: account)
        } label: {
            Label("종목 추가", systemImage: "plus")
                .font(.system(size: 12))
                .foregroundStyle(Color.muted)
        }
        .padding(.leading, 12)
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
