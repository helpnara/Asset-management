import Core
import CoreData
import SwiftUI

struct MemberEditView: View {
    @ObservedObject var member: Member
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    /// 열었을 때의 이름. 닫을 때 견줘서 **추가인지 이름 변경인지** 가린다
    /// (docs/08-feedback.md 29번). 만들자마자 기록하면 취소한 것까지 남는다.
    @State private var nameOnOpen: String?

    private let years = Array((1930...Calendar.current.component(.year, from: .now)).reversed())

    /// 구성원 삭제는 이 앱에서 가장 크게 지우는 일이다 — 계좌와 종목이
    /// cascade 로 전부 딸려 간다. 몇 개가 사라지는지 세어서 적는다.
    private var memberDeleteWarning: String {
        let accounts = member.sortedAccounts.count
        let holdings = member.sortedAccounts.reduce(0) { $0 + $1.sortedHoldings.count }
        guard accounts > 0 else { return "되돌릴 수 없습니다." }
        return "계좌 \(accounts)개와 종목 \(holdings)개, 적어 온 평가액이 모두 함께 사라집니다. 되돌릴 수 없습니다."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름 (아빠 · 엄마 · 아들 …)", text: $member.name)
                    TextField("설명 (본인 · 2022년생 …)", text: $member.roleNote)
                }

                Section("생년월") {
                    Picker("연", selection: $member.birthYear) {
                        ForEach(years, id: \.self) { Text(verbatim: "\($0)년").tag($0) }
                    }
                    Picker("월", selection: $member.birthMonth) {
                        ForEach(1...12, id: \.self) { Text("\($0)월").tag($0) }
                    }
                }

                Section {
                    Picker("세적", selection: $member.taxResidency) {
                        ForEach(TaxResidency.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("은퇴 목표 \(member.targetRetirementAge)세",
                            value: $member.targetRetirementAge, in: 40...90)
                } footer: {
                    if member.taxResidency.isSubjectToPFIC {
                        Text("미국 납세 의무가 있으면 한국 상장 ETF는 PFIC로 분류되어 세금이 불리합니다. 해당 종목에 경고를 표시합니다.")
                    }
                }

                Section {
                    MoneyField(title: "월 적립 (본인 부담)",
                               minorUnits: $member.monthlyContributionMinor)
                    MoneyField(title: "회사 매칭", minorUnits: $member.employerMatchMinor)
                } header: {
                    Text("월 적립")
                } footer: {
                    Text("궤적에는 **합계**가 쓰이고, 저축률 진단에는 **본인 부담만** 씁니다. 회사가 넣어 주는 돈을 내 저축으로 세면 저축률이 실제보다 높게 나옵니다.")
                }

                Section {
                    MoneyField(title: "월급 (세후)", minorUnits: $member.monthlySalaryMinor)
                    MoneyField(title: "기타 수입", minorUnits: $member.otherIncomeMinor)
                } header: {
                    Text("월 소득")
                } footer: {
                    Text("가족 전체의 합계가 **소득 대비 투자 비중** 진단에 쓰입니다 (권장 10% 이상). 한 사람이라도 적으면 진단 기준의 '세후 월 소득' 한 칸 대신 이 합계를 씁니다. 다른 화면에는 나오지 않습니다.")
                }

                Section {
                    TextField("이 사람에게만 해당하는 메모", text: $member.note, axis: .vertical)
                        .lineLimit(1...4)
                } header: {
                    Text("주석")
                } footer: {
                    Text("한도·재검토 시점처럼 그 사람에게만 걸리는 것을 적습니다. 1페이지 구성원 카드에 `※` 로 나갑니다.")
                }

                Section("표시 색") {
                    Picker("색", selection: $member.colorIndex) {
                        ForEach(0..<Color.memberPalette.count, id: \.self) { index in
                            HStack {
                                Circle().fill(Color.member(index)).frame(width: 14, height: 14)
                                Text(["첫째 색", "둘째 색", "셋째 색", "넷째 색"][index])
                            }
                            .tag(index)
                        }
                    }
                }
            }
            .navigationTitle("구성원")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DeleteButton("\(member.name.isEmpty ? "이 구성원" : member.name) 을(를) 삭제할까요?",
                                 consequence: memberDeleteWarning) {
                        ChangeLogger.structureChanged(
                            member.name.isEmpty ? "이름 없음" : member.name,
                            "구성원을 삭제했습니다", in: context
                        )
                        nameOnOpen = nil          // 지운 것을 또 기록하지 않는다
                        context.delete(member)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { if nameOnOpen == nil { nameOnOpen = member.name } }
            .onDisappear { logChange() }
        }
    }

    private func logChange() {
        guard let before = nameOnOpen else { return }
        let after = member.name
        if before.isEmpty, !after.isEmpty {
            ChangeLogger.structureChanged(after, "구성원을 추가했습니다", in: context)
        } else if !before.isEmpty, before != after, !after.isEmpty {
            ChangeLogger.structureChanged(after, "이름을 \(before) 에서 바꿨습니다", in: context)
        }
    }
}

struct AccountEditView: View {
    @ObservedObject var account: Account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.self) private var environment
    @Fetched(sort: \Member.sortIndex) private var members: [Member]

    /// 열었을 때의 이름. 쓰임은 `MemberEditView` 와 같다.
    @State private var nameOnOpen: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("계좌 이름", text: $account.name)
                    TextField("기관 (증권사 · 은행 · 보험사)", text: $account.institution)
                    Picker("종류", selection: $account.kind) {
                        ForEach(AccountKind.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    // 겹칠 때는 **왜 완료를 못 누르는지**를 입력칸 바로 아래 적는다.
                    // 다 적은 뒤 경고창으로 튕겨내지 않는다 (30번).
                    if isDuplicate {
                        Text("이미 같은 이름·기관의 계좌가 있습니다. 이름이나 기관을 다르게 적어 주세요.")
                            .foregroundStyle(Color.loss)
                    } else {
                        Text(accountFooter)
                    }
                }

                // **다른 구성원에게 옮기기** (94번, B5). 지우고 다시 만들면 이력이
                // 끊긴다. 내가 고칠 수 있는 구성원 사이에서만.
                if members.filter({ environment.mayEdit($0) }).count > 1 {
                    Section {
                        Picker("소유자", selection: ownerBinding) {
                            ForEach(members.filter { environment.mayEdit($0) }) { member in
                                Text(member.name.isEmpty ? "이름 없음" : member.name).tag(member.id)
                            }
                        }
                    } header: {
                        Text("소속")
                    } footer: {
                        Text("계좌와 그 안의 종목이 통째로 옮겨집니다. 적어 온 값은 그대로입니다.")
                    }
                }

                // 한도가 있는 계좌에만 나타난다. 일반 위탁 계좌에 한도 칸을 두면
                // 채워야 할 것이 있는 것처럼 읽힌다.
                if account.kind.hasContributionLimit {
                    Section {
                        MoneyField(title: "올해 납입액", minorUnits: $account.annualContributionMinor)
                        MoneyField(title: "연간 한도", minorUnits: $account.annualLimitMinor)
                    } header: {
                        Text("연간 한도")
                    } footer: {
                        Text("자산 진단이 이 두 값으로 \"어느 계좌부터 채울지\"를 판단합니다. **이 앱은 세법을 따라가지 않습니다** — 한도는 직접 확인해서 넣고, 바뀌면 직접 고치세요. 해가 바뀌면 납입액을 0으로 되돌립니다.")
                    }
                }

                // **세 든 집** — 전월세보증금 계좌에만. 월세 적정성 진단의 입력이다
                // (docs/05-roadmap.md 마지막 묶음 2).
                if account.kind == .leaseDeposit {
                    Section {
                        MoneyField(title: "집 매매가", minorUnits: $account.purchasePriceMinor)
                        MoneyField(title: "월세 (전세면 0)", minorUnits: $account.monthlyRentMinor)
                    } header: {
                        Text("세 든 집")
                    } footer: {
                        Text("연 월세가 매매가의 **5% 이내면 적정**으로 봅니다. 자산 진단의 '월세 적정성' 이 이 두 값으로 판단합니다. 매매가는 비슷한 집의 최근 실거래가를 적으면 됩니다.")
                    }
                }

                // **만기** — 모델에는 2차부터 있었는데 적을 자리가 없었다
                // (docs/08-feedback.md 28번). 1페이지 푸터와 할 일이 이걸 읽는다.
                Section {
                    Toggle("만기가 있는 계좌", isOn: hasMaturity)
                    if account.maturesOn != nil {
                        DatePicker("만기일", selection: maturityDate, displayedComponents: .date)
                    }
                } header: {
                    Text("만기")
                } footer: {
                    Text(maturityFooter)
                }

                Section {
                    Toggle("이 계좌만 따로 정하기", isOn: hasOwnReturn)
                    if account.expectedReturnBP != nil {
                        PercentStepper(title: "연 기대수익률", basisPoints: ownReturnBP,
                                       range: 0...2_000, step: 25)
                    } else {
                        LabeledContent("연 기대수익률") {
                            Text("계획의 \(account.kind.returnProfile.label) 값을 따름")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.muted)
                        }
                    }
                } header: {
                    Text("기대수익률")
                } footer: {
                    Text(returnFooter)
                }
            }
            .navigationTitle("계좌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DeleteButton("\(account.name.isEmpty ? account.kind.label : account.name) 을(를) 삭제할까요?",
                                 consequence: accountDeleteWarning) {
                        ChangeLogger.structureChanged(
                            logSubject,
                            "계좌를 삭제했습니다 (종목 \(account.sortedHoldings.count)개 포함)",
                            in: context
                        )
                        nameOnOpen = nil
                        context.delete(account)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }
                        .fontWeight(.semibold)
                        .disabled(isDuplicate)
                }
            }
            // 잠근 완료 버튼을 쓸어내려 빠져나가면 잠근 의미가 없다.
            .interactiveDismissDisabled(isDuplicate)
            .onAppear { if nameOnOpen == nil { nameOnOpen = account.name } }
            .onDisappear { logChange() }
        }
    }

    private var logSubject: String {
        let owner = account.owner?.name ?? ""
        let name = account.name.isEmpty ? account.kind.label : account.name
        return owner.isEmpty ? name : "\(owner) · \(name)"
    }

    private func logChange() {
        guard let before = nameOnOpen else { return }
        let after = account.name
        if before.isEmpty, !after.isEmpty {
            ChangeLogger.structureChanged(logSubject, "계좌를 추가했습니다", in: context)
        } else if !before.isEmpty, before != after, !after.isEmpty {
            ChangeLogger.structureChanged(logSubject, "이름을 \(before) 에서 바꿨습니다", in: context)
        }
    }

    /// 같은 사람 밑에 이름·기관이 같은 계좌가 이미 있나 (30번, 정책 B).
    ///
    /// 한 사람의 계좌 목록에 `일반적립` 이 둘 있으면 어느 줄이 어느 계좌인지
    /// 알 수 없다. **기관이 다르면 막지 않는다** — 같은 성격의 적립을 증권사
    /// 두 곳에 나눠 두는 것은 자연스럽고, 기관은 이미 따로 적는 칸이다.
    private var isDuplicate: Bool { account.hasDuplicateSibling }

    /// **무엇이 함께 사라지는지 세어서 적는다.** "정말 삭제할까요?" 만으로는
    /// 계좌 하나를 지우는 줄 알고 종목 열 개를 잃는다.
    private var accountDeleteWarning: String {
        let count = account.sortedHoldings.count
        guard count > 0 else { return "되돌릴 수 없습니다." }
        return "이 계좌에 담긴 종목 \(count)개와 적어 온 평가액이 함께 사라집니다. 되돌릴 수 없습니다."
    }

    private var ownerBinding: Binding<UUID> {
        Binding(
            get: { account.owner?.id ?? account.ownerID ?? UUID() },
            set: { id in
                guard let member = members.first(where: { $0.id == id }), member != account.owner else { return }
                let before = account.owner?.name ?? ""
                account.owner = member
                account.ownerID = member.id
                account.sortIndex = member.sortedAccounts.count
                ChangeLogger.structureChanged(
                    [member.name, account.weightLabel].filter { !$0.isEmpty }.joined(separator: " · "),
                    "계좌를 \(before.isEmpty ? "이름 없음" : before) 에서 옮겼습니다", in: context)
            }
        )
    }

    private var accountFooter: String {
        if account.kind.isLiability {
            return "부채 계좌입니다. 총자산에서 뺍니다."
        }
        if !account.kind.countsAsInvestable {
            return "자산에는 넣지만 '투자자산 합계'와 국가 비중에서는 뺍니다. 전월세보증금·부동산·받을 돈이 여기 해당합니다."
        }
        return "투자자산으로 셉니다."
    }

    /// 켜면 1년 뒤로 잡아 준다. 만기는 대개 몇 년 뒤라 오늘로 두면 매번 크게
    /// 돌려야 한다.
    private var hasMaturity: Binding<Bool> {
        Binding(
            get: { account.maturesOn != nil },
            set: { on in
                account.maturesOn = on
                    ? (Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
                    : nil
            }
        )
    }

    private var maturityDate: Binding<Date> {
        Binding(
            get: { account.maturesOn ?? .now },
            set: { account.maturesOn = $0 }
        )
    }

    private var maturityFooter: String {
        guard let date = account.maturesOn else {
            return "ISA·예적금처럼 기한이 있는 계좌에 적습니다. 1페이지 푸터의 `임박한 만기` 와 할 일 목록이 이 날짜를 읽습니다."
        }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        if days < 0 { return "만기가 \(-days)일 지났습니다. 연장했다면 날짜를 새로 적어 주세요." }
        if days == 0 { return "오늘이 만기입니다." }
        return "\(days)일 남았습니다. 90일 안으로 들어오면 할 일 목록에 함께 뜹니다."
    }

    /// 계좌마다 수익률을 따로 적을 수 있어야 한다 — 예금은 상품마다 금리가 다르다.
    /// 비워 두면 계획의 프로필 값을 따른다 (docs/08-feedback.md 11번).
    private var hasOwnReturn: Binding<Bool> {
        Binding(
            get: { account.expectedReturnBP != nil },
            set: { account.expectedReturnBP = $0 ? 200 : nil }
        )
    }

    private var ownReturnBP: Binding<Int> {
        Binding(
            get: { account.expectedReturnBP ?? 0 },
            set: { account.expectedReturnBP = $0 }
        )
    }

    private var returnFooter: String {
        switch account.kind.returnProfile {
        case .investment:
            return "궤적에서 이 계좌의 돈이 자라는 속도입니다. 비워 두면 계획의 연 기대수익률을 씁니다."
        case .lowYield:
            return "예적금·연금보험은 투자 수익률로 굴리지 않습니다. 금리가 바뀌면 여기서 고치세요."
        case .realEstate:
            return "부동산은 계획의 부동산 상승률을 따릅니다."
        case .fixed:
            return "전월세보증금·받을 돈은 **자라지 않는 돈**으로 봅니다. 궤적에서 명목 그대로 남습니다."
        }
    }
}

struct HoldingEditView: View {
    @ObservedObject var holding: Holding
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.self) private var environment
    @Fetched(sort: \Member.sortIndex) private var members: [Member]

    /// 열었을 때의 이름. 쓰임은 `MemberEditView` 와 같다.
    @State private var nameOnOpen: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("목표 비중 정하기", isOn: Binding(
                        get: { holding.targetWeightBP != nil },
                        set: { holding.targetWeightBP = $0 ? (holding.targetWeightBP ?? 1_000) : nil }
                    ))
                    if holding.targetWeightBP != nil {
                        PercentStepper(title: "목표 비중", basisPoints: Binding(
                            get: { holding.targetWeightBP ?? 0 },
                            set: { holding.targetWeightBP = $0 }
                        ))
                    }
                } header: {
                    Text("목표 비중")
                } footer: {
                    Text("**같은 자산군 안에서**의 비중입니다. 자산군끼리의 비중은 자산 탭 → 구성원 → 목표 비중에서 정합니다. 정해 두면 매주 점검할 때 어긋난 종목에 배지가 뜹니다.")
                }

                Section {
                    TextField("종목 이름 (VOO · 삼성전자 …)", text: $holding.name)
                    // 자산 탭에서 고쳐도 이번 주 처음이면 직전 값이 기준값으로 (91번).
                    MoneyField(title: "평가액", minorUnits: Binding(
                        get: { holding.valueMinor },
                        set: {
                            guard $0 != holding.valueMinor else { return }
                            holding.rollBaselineIfNewWeek()
                            holding.valueMinor = $0
                        }
                    ))
                } footer: {
                    // 해외 종목을 달러로 적어 넣으면 합계가 조용히 1,400배 틀린다.
                    // 다중 통화(환율 직접 입력)는 M5 이고, 그전까지는 여기서 못을 박는다.
                    //
                    // 문자열 변수를 넘기면 Text 가 마크다운을 해석하지 않아 별표가 그대로 보인다.
                    // 굵게 쓰려면 리터럴이어야 하므로 분기를 문자열이 아니라 뷰로 나눈다.
                    if holding.listingCountryCode == "KR" {
                        Text("시세를 가져오지 않습니다. 매주 직접 적어 넣는 이 숫자가 기준입니다.")
                    } else {
                        Text("시세를 가져오지 않습니다. 해외 종목도 **원화로 환산한 금액**을 적어 주세요. 이 앱의 모든 금액은 원화입니다.")
                    }
                }

                Section {
                    // **계좌가 자산군을 좁히고, 자산군이 상품 종류를 좁힌다**
                    // (docs/08-feedback.md 50번). 저장된 값이 목록 밖이면 목록에
                    // 남긴다 — 없으면 피커가 빈 칸으로 보인다.
                    Picker("자산군", selection: $holding.assetClass) {
                        ForEach(assetClassChoices) { Text($0.label).tag($0) }
                    }
                    Picker("상품 종류", selection: $holding.instrumentType) {
                        ForEach(instrumentChoices) { Text($0.label).tag($0) }
                    }
                    Picker("상장 국가", selection: $holding.listingCountryCode) {
                        Text("한국").tag("KR")
                        Text("미국").tag("US")
                        Text("기타").tag("XX")
                    }
                } header: {
                    Text("분류")
                } footer: {
                    if let kind = holding.account?.kind, kind.allowedAssetClasses.count < AssetClass.allCases.count {
                        Text("\(kind.label) 계좌에 맞는 것만 보입니다.")
                    }
                }
                .onChange(of: holding.assetClass) { _, assetClass in
                    // 자산군을 바꿨는데 상품 종류가 안 맞으면 그 자산군의 기본으로.
                    if !assetClass.allowedInstrumentTypes.contains(holding.instrumentType) {
                        holding.instrumentType = assetClass.defaultInstrumentType
                    }
                }

                // **다른 계좌로 옮기기** (94번, B5). 내가 고칠 수 있는 구성원의
                // 계좌 사이에서만. 옮기면 자산군 제한도 그 계좌 기준이 된다.
                if movableAccounts.count > 1 {
                    Section {
                        Picker("계좌", selection: accountBinding) {
                            ForEach(movableAccounts, id: \.id) { account in
                                Text("\(account.owner?.name ?? "") · \(account.weightLabel)").tag(account.id)
                            }
                        }
                    } header: {
                        Text("소속")
                    } footer: {
                        Text("적어 온 값은 그대로 따라갑니다. 지우고 다시 만들면 이력이 끊기니 여기서 옮기세요.")
                    }
                }

                Section {
                    Picker("상태", selection: $holding.status) {
                        ForEach(HoldingStatus.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("입력 주기", selection: $holding.cadence) {
                        ForEach(EntryCadence.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text(cadenceFooter)
                }

                if holding.violatesPFIC {
                    Section {
                        Label {
                            Text("미국 세적 구성원의 계좌에 한국 상장 ETF입니다. PFIC로 분류되어 세금이 징벌적입니다.")
                                .font(.system(size: 12))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .foregroundStyle(Color.loss)
                    }
                }

                Section("메모") {
                    TextField("※ 주석", text: $holding.note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("종목")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DeleteButton("\(holding.name.isEmpty ? "이 종목" : holding.name) 을(를) 삭제할까요?",
                                 consequence: "적어 온 평가액이 함께 사라집니다. 되돌릴 수 없습니다.") {
                        ChangeLogger.structureChanged(logSubject, "종목을 삭제했습니다", in: context)
                        nameOnOpen = nil
                        context.delete(holding)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { if nameOnOpen == nil { nameOnOpen = holding.name } }
            .onDisappear { logChange() }
        }
    }

    private var logSubject: String {
        let owner = holding.account?.owner?.name ?? ""
        let account = holding.account.map { $0.name.isEmpty ? $0.kind.label : $0.name } ?? ""
        let name = holding.name.isEmpty ? "이름 없음" : holding.name
        return [owner, account, name].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func logChange() {
        guard let before = nameOnOpen else { return }
        let after = holding.name
        if before.isEmpty, !after.isEmpty {
            ChangeLogger.structureChanged(logSubject, "종목을 추가했습니다", in: context)
        } else if !before.isEmpty, before != after, !after.isEmpty {
            ChangeLogger.structureChanged(logSubject, "이름을 \(before) 에서 바꿨습니다", in: context)
        }
    }

    /// 계좌 종류에 맞는 자산군. 저장된 값이 목록 밖이면 앞에 남긴다.
    private var assetClassChoices: [AssetClass] {
        let allowed = holding.account?.kind.allowedAssetClasses ?? AssetClass.allCases
        return allowed.contains(holding.assetClass) ? allowed : [holding.assetClass] + allowed
    }

    /// 자산군에 맞는 상품 종류. 위와 같은 규칙.
    private var instrumentChoices: [InstrumentType] {
        let allowed = holding.assetClass.allowedInstrumentTypes
        return allowed.contains(holding.instrumentType) ? allowed : [holding.instrumentType] + allowed
    }

    private var movableAccounts: [Account] {
        members.filter { environment.mayEdit($0) }.flatMap { $0.sortedAccounts.filter { !$0.isArchived } }
    }

    private var accountBinding: Binding<UUID> {
        Binding(
            get: { holding.account?.id ?? holding.accountID ?? UUID() },
            set: { id in
                guard let account = movableAccounts.first(where: { $0.id == id }), account != holding.account else { return }
                let before = holding.account?.weightLabel ?? ""
                holding.account = account
                holding.accountID = account.id
                holding.sortIndex = account.sortedHoldings.count
                if !account.kind.allowedAssetClasses.contains(holding.assetClass) {
                    holding.assetClass = account.kind.defaultAssetClass
                }
                ChangeLogger.structureChanged(logSubject, "종목을 \(before.isEmpty ? "이름 없음" : before) 에서 옮겼습니다", in: context)
            }
        )
    }

    private var cadenceFooter: String {
        switch holding.cadence {
        case .weekly: return "매주 토요일 점검에서 물어봅니다."
        case .monthly: return "월 1회만 물어봅니다. 연금보험 해지환급금처럼 자주 안 바뀌는 항목에 씁니다."
        case .fixed: return "주간 점검에서 건너뜁니다. 전월세보증금처럼 값이 고정된 항목에 씁니다."
        }
    }
}
