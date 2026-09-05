import Core
import SwiftData
import SwiftUI

struct MemberEditView: View {
    @Bindable var member: Member
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private let years = Array((1930...Calendar.current.component(.year, from: .now)).reversed())

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
                    Button("삭제", role: .destructive) {
                        context.delete(member)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

struct AccountEditView: View {
    @Bindable var account: Account
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("계좌 이름", text: $account.name)
                    TextField("기관 (미래에셋 · 토스 …)", text: $account.institution)
                    Picker("종류", selection: $account.kind) {
                        ForEach(AccountKind.allCases) { Text($0.label).tag($0) }
                    }
                } footer: {
                    Text(accountFooter)
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
            }
            .navigationTitle("계좌")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("삭제", role: .destructive) {
                        context.delete(account)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var accountFooter: String {
        if account.kind.isLiability {
            return "부채 계좌입니다. 총자산에서 뺍니다."
        }
        if !account.kind.countsAsInvestable {
            return "자산에는 넣지만 '투자자산 합계'와 국가 비중에서는 뺍니다. 전세보증금·부동산이 여기 해당합니다."
        }
        return "투자자산으로 셉니다."
    }
}

struct HoldingEditView: View {
    @Bindable var holding: Holding
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("종목 이름 (VOO · 삼성전자 …)", text: $holding.name)
                    MoneyField(title: "평가액", minorUnits: $holding.valueMinor)
                } footer: {
                    // 해외 종목을 달러로 적어 넣으면 합계가 조용히 1,400배 틀린다.
                    // 다중 통화(환율 직접 입력)는 M5 이고, 그전까지는 여기서 못을 박는다.
                    //
                    // 문자열 변수를 넘기면 Text 가 마크다운을 해석하지 않아 별표가 그대로 보인다.
                    // 굵게 쓰려면 리터럴이어야 하므로 분기를 문자열이 아니라 뷰로 나눈다.
                    if holding.listingCountryCode == "KR" {
                        Text("시세를 가져오지 않습니다. 매주 직접 적어 넣는 이 숫자가 기준입니다.")
                    } else {
                        Text("시세를 가져오지 않습니다. 해외 종목도 **원화로 환산한 금액**을 적어 주세요. 통화별 입력은 아직 없습니다.")
                    }
                }

                Section("분류") {
                    Picker("자산군", selection: $holding.assetClass) {
                        ForEach(AssetClass.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("상품 종류", selection: $holding.instrumentType) {
                        ForEach(InstrumentType.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("상장 국가", selection: $holding.listingCountryCode) {
                        Text("한국").tag("KR")
                        Text("미국").tag("US")
                        Text("기타").tag("XX")
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
                    Button("삭제", role: .destructive) {
                        context.delete(holding)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var cadenceFooter: String {
        switch holding.cadence {
        case .weekly: return "매주 토요일 점검에서 물어봅니다."
        case .monthly: return "월 1회만 물어봅니다. 연금보험 해지환급금처럼 자주 안 바뀌는 항목에 씁니다."
        case .fixed: return "주간 점검에서 건너뜁니다. 전세보증금처럼 값이 고정된 항목에 씁니다."
        }
    }
}
