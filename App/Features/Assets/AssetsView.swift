import Core
import SwiftData
import SwiftUI

/// 계속 입력하는 화면. 구성원 → 계좌 → 종목 3단.
struct AssetsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Member.sortIndex) private var members: [Member]

    @State private var editingMember: Member?
    @State private var newAccountOwner: Member?
    @State private var editingAccount: Account?
    @State private var newHoldingAccount: Account?
    @State private var editingHolding: Holding?

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addMember()
                    } label: {
                        Label("구성원 추가", systemImage: "person.badge.plus")
                    }
                }
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
            HStack {
                Text(account.name.isEmpty ? account.kind.label : account.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink)
                if !account.institution.isEmpty {
                    Text(account.institution)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.faint)
                }
                Spacer()
                Text(KoreanAmountFormatter.abbreviated(accountTotal(account)))
                    .font(.figure(12.5, weight: .medium))
                    .foregroundStyle(Color.ink)
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
                                    background: Color(hex: 0xF5E6E8))
                    }
                }
                Text("\(holding.assetClass.label) · \(holding.listingCountryCode) · \(holding.cadence.label)")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.faint)
            }
            Spacer(minLength: 8)
            Text(KoreanAmountFormatter.grouped(holding.valueMinor))
                .font(.figure(12.5))
                .foregroundStyle(Color.ink)
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
                .foregroundStyle(Color.white)
                .background(Color.ink, in: RoundedRectangle(cornerRadius: 3))
                .padding(.top, 4)
        }
        .padding(28)
    }

    // MARK: - 편집

    private func accountTotal(_ account: Account) -> Money {
        account.sortedHoldings.map(\.value).total(in: .krw)
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
        let holding = Holding(name: "", account: account, sortIndex: account.sortedHoldings.count)
        context.insert(holding)
        editingHolding = holding
    }

    private func delete(_ offsets: IndexSet, from account: Account) {
        let items = account.sortedHoldings
        for index in offsets where items.indices.contains(index) {
            context.delete(items[index])
        }
    }
}
