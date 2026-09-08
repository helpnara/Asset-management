import Core
import Foundation
import CoreData

// CloudKit 미러링 제약을 처음부터 지킨다 (ADR-0001):
// 유니크 제약 없음 · 모든 속성에 기본값 · 모든 관계 옵셔널.
// 나중에 켜려면 스키마를 다시 만들어야 하므로 지금 지킨다.

extension Member {
    convenience init(context: NSManagedObjectContext, name: String = "", roleNote: String = "", birthYear: Int = 1990,
         birthMonth: Int = 1, taxResidency: TaxResidency = .korea,
         targetRetirementAge: Int = 65, colorIndex: Int = 0, sortIndex: Int = 0) {
        self.init(context: context)
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

extension Account {
    convenience init(context: NSManagedObjectContext, name: String = "", institution: String = "",
         kind: AccountKind = .general, owner: Member? = nil, sortIndex: Int = 0) {
        self.init(context: context)
        self.ownerID = owner?.id
        self.name = name
        self.institution = institution
        self.kindRaw = kind.rawValue
        self.owner = owner
        self.sortIndex = sortIndex
    }
}

extension Holding {
    convenience init(context: NSManagedObjectContext, name: String = "", assetClass: AssetClass = .equity,
         instrumentType: InstrumentType = .stock, listingCountryCode: String = "KR",
         status: HoldingStatus = .accumulating, cadence: EntryCadence = .weekly,
         valueMinor: Int = 0, account: Account? = nil, sortIndex: Int = 0) {
        self.init(context: context)
        self.accountID = account?.id
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

    /// 이 사람이 은퇴하는 해 (docs/08-feedback.md 38번).
    ///
    /// `targetRetirementAge` 를 입력받아 놓고 **계산에 한 번도 안 썼다.**
    /// 은퇴 시점이 계획의 값 하나뿐이라, 부부의 은퇴 시기가 다른데도 궤적은
    /// 그것을 몰랐다. 구성원 궤적과 1페이지 미니 차트가 이 값을 쓴다.
    ///
    /// 이미 지난 나이를 적어 두었으면 올해로 본다 — 과거로 은퇴시킬 수는 없다.
    var retirementYear: Int {
        let thisYear = Calendar.current.component(.year, from: .now)
        return max(birthYear + targetRetirementAge, thisYear)
    }

    var sortedAccounts: [Account] {
        // Core Data 의 일대다는 `NSSet?` 이다. 여기 한 곳에서만 푼다.
        (accounts as? Set<Account> ?? []).sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
    }
}

extension Account {
    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .general }
        set { kindRaw = newValue.rawValue }
    }

    var sortedHoldings: [Holding] {
        (holdings as? Set<Holding> ?? []).sorted { ($0.sortIndex, $0.createdAt) < ($1.sortIndex, $1.createdAt) }
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
