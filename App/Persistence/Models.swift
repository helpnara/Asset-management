import Core
import Foundation
import SwiftData

// CloudKit 미러링 제약을 처음부터 지킨다 (ADR-0001):
// 유니크 제약 없음 · 모든 속성에 기본값 · 모든 관계 옵셔널.
// 나중에 켜려면 스키마를 다시 만들어야 하므로 지금 지킨다.

@Model
final class Member {
    var id: UUID = UUID()
    var name: String = ""
    var roleNote: String = ""            // "본인", "2022년생"
    var birthYear: Int = 1990
    var birthMonth: Int = 1
    var taxResidencyRaw: String = TaxResidency.korea.rawValue
    var targetRetirementAge: Int = 65
    /// 이 사람 몫의 월 적립액. 계획 탭에서 "구성원별로 나눠 넣기"를 켰을 때만 쓴다.
    var monthlyContributionMinor: Int = 0
    var colorIndex: Int = 0
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Account.owner)
    var accounts: [Account]? = []

    init(name: String = "", roleNote: String = "", birthYear: Int = 1990,
         birthMonth: Int = 1, taxResidency: TaxResidency = .korea,
         targetRetirementAge: Int = 65, colorIndex: Int = 0, sortIndex: Int = 0) {
        self.name = name
        self.roleNote = roleNote
        self.birthYear = birthYear
        self.birthMonth = birthMonth
        self.taxResidencyRaw = taxResidency.rawValue
        self.targetRetirementAge = targetRetirementAge
        self.colorIndex = colorIndex
        self.sortIndex = sortIndex
    }
}

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var institution: String = ""
    var kindRaw: String = AccountKind.general.rawValue
    var isArchived: Bool = false
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    /// 올해 이 계좌에 넣은 금액. 사용자가 직접 적는다 (ADR-0005 — 가져오지 않는다).
    var annualContributionMinor: Int = 0
    /// 연간 납입 한도. 0이면 진단에서 판단하지 않는다.
    ///
    /// **앱은 세법을 따라가지 않는다.** 한도가 바뀌면 사용자가 직접 고친다.
    /// 여기에 숫자를 박아 두고 세법이 바뀌면, 앱이 조용히 틀린 조언을 하게 된다.
    var annualLimitMinor: Int = 0

    var owner: Member?

    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    var holdings: [Holding]? = []

    init(name: String = "", institution: String = "",
         kind: AccountKind = .general, owner: Member? = nil, sortIndex: Int = 0) {
        self.name = name
        self.institution = institution
        self.kindRaw = kind.rawValue
        self.owner = owner
        self.sortIndex = sortIndex
    }
}

@Model
final class Holding {
    var id: UUID = UUID()
    var name: String = ""
    var assetClassRaw: String = AssetClass.equity.rawValue
    var instrumentTypeRaw: String = InstrumentType.stock.rawValue
    var listingCountryCode: String = "KR"
    var statusRaw: String = HoldingStatus.accumulating.rawValue
    var cadenceRaw: String = EntryCadence.weekly.rawValue

    /// 사용자가 매주 직접 적어 넣는 평가액. 이 앱의 진실의 원천이다 (ADR-0005).
    var valueMinor: Int = 0
    /// 직전 점검에서 적은 값. 증감 표시에만 쓴다.
    var lastEnteredValueMinor: Int = 0
    var lastEnteredAt: Date?

    var note: String = ""
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    var account: Account?

    init(name: String = "", assetClass: AssetClass = .equity,
         instrumentType: InstrumentType = .stock, listingCountryCode: String = "KR",
         status: HoldingStatus = .accumulating, cadence: EntryCadence = .weekly,
         valueMinor: Int = 0, account: Account? = nil, sortIndex: Int = 0) {
        self.name = name
        self.assetClassRaw = assetClass.rawValue
        self.instrumentTypeRaw = instrumentType.rawValue
        self.listingCountryCode = listingCountryCode
        self.statusRaw = status.rawValue
        self.cadenceRaw = cadence.rawValue
        self.valueMinor = valueMinor
        self.account = account
        self.sortIndex = sortIndex
    }
}

// MARK: - enum 접근자
//
// 저장은 String rawValue 로 한다 (스키마 안정성 + CloudKit 호환).
// 화면 코드가 rawValue 를 직접 만지지 않도록 확장에서 감싼다.

extension Member {
    var taxResidency: TaxResidency {
        get { TaxResidency(rawValue: taxResidencyRaw) ?? .korea }
        set { taxResidencyRaw = newValue.rawValue }
    }

    var age: Int {
        let now = Calendar.current.dateComponents([.year, .month], from: .now)
        guard let year = now.year, let month = now.month else { return 0 }
        return (year - birthYear) - (month < birthMonth ? 1 : 0)
    }

    var sortedAccounts: [Account] {
        (accounts ?? []).sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }
}

extension Account {
    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .general }
        set { kindRaw = newValue.rawValue }
    }

    var sortedHoldings: [Holding] {
        (holdings ?? []).sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }
}

extension Holding {
    var assetClass: AssetClass {
        get { AssetClass(rawValue: assetClassRaw) ?? .equity }
        set { assetClassRaw = newValue.rawValue }
    }

    var instrumentType: InstrumentType {
        get { InstrumentType(rawValue: instrumentTypeRaw) ?? .stock }
        set { instrumentTypeRaw = newValue.rawValue }
    }

    var status: HoldingStatus {
        get { HoldingStatus(rawValue: statusRaw) ?? .accumulating }
        set { statusRaw = newValue.rawValue }
    }

    var cadence: EntryCadence {
        get { EntryCadence(rawValue: cadenceRaw) ?? .weekly }
        set { cadenceRaw = newValue.rawValue }
    }

    /// 사용자가 적어 넣은 그대로. **언제나 원화다** — 해외 종목도 원화로 환산해서
    /// 적는다. 환율을 앱이 다루지 않는 이유는 ADR-0005 에 적혀 있다.
    var value: Money { Money(minorUnits: valueMinor, currency: .krw) }

    /// 미국 세적자가 한국 상장 ETF를 들고 있는가 (PFIC).
    /// 저장은 막지 않고 경고만 한다 — 예외는 항상 있고 사용자가 자기 돈의 주인이다.
    var violatesPFIC: Bool {
        guard let residency = account?.owner?.taxResidency else { return false }
        return residency.isSubjectToPFIC
            && instrumentType == .etf
            && listingCountryCode == "KR"
    }

    /// 계산 계층으로 넘길 납작한 값 타입 (ADR-0002).
    func position() -> Position? {
        guard let account, let owner = account.owner else { return nil }
        return Position(
            memberID: owner.id,
            accountID: account.id,
            assetClass: assetClass,
            countryCode: listingCountryCode,
            value: value,
            isLiability: account.kind.isLiability,
            countsAsInvestable: account.kind.countsAsInvestable
        )
    }
}
