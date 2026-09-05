# 3. 도메인 · 데이터 모델

## 3.1 엔티티 개요

```
Household ──┬── Member ──┬── Account ──── Holding ──── Transaction
  (가구)     │  (구성원)   │   (계좌)      (보유자산)      (거래, 선택)
             │            ├── ContributionPlan ── ContributionAllocation
             │            │   (적립 계획)          (배분: 계좌/종목별)
             │            └── IncomeStream
             │                (연금·미래소득)
             ├── CashEvent        (목돈 이벤트)
             ├── Milestone        (마일스톤)
             ├── Principle        (운용 원칙 + 자동 점검 규칙)
             ├── Advisory         (유의사항 · 기한 있는 할 일)
             ├── Scenario ──── Assumptions   (시나리오별 가정)
             └── Snapshot ──── SnapshotLine  (일별 실제 기록)

캐시(동기화 대상 아님):  QuoteCache,  FXRateCache
```

## 3.2 설계 원칙

1. **보유 자산의 평가액이 진실의 원천이다.** 거래 내역은 선택 기능이며,
   거래가 하나도 없어도 앱은 완전히 동작한다. 거래는 평균단가·수익률을 *도와줄 뿐*이다.
2. **금액은 스케일드 정수로 저장한다.** → [ADR-0003](adr/0003-money-representation.md)
3. **enum은 `String` rawValue로 저장한다.** 스키마 안정성과 CloudKit 호환 때문.
4. **모든 속성에 기본값을, 모든 관계를 옵셔널로.** CloudKit 미러링 제약.
   → [ADR-0001](adr/0001-swiftdata-cloudkit.md)
5. **계산 결과는 저장하지 않는다.** 단, 일별 스냅샷과 프로젝션 캐시는 예외
   (재계산 비용과 과거 사실 보존 때문).

## 3.3 SwiftData 스키마 (스케치)

> 실제 구현 시 세부는 달라질 수 있습니다. 관계·필수 필드·enum 값 집합을 확정하는 것이 목적입니다.

### 3.3.1 가구 · 구성원

```swift
@Model
final class Household {
    var id: UUID = UUID()
    var title: String = "우리 가족 노후자금 준비"
    var planStartDate: Date = Date.now          // "2023.11.27 ~"
    var baseCurrencyCode: String = "KRW"
    var asOfLabel: String = ""                  // "2026.08 기준 · 이사 후"
    var closingStatement: String = ""           // 푸터 한 줄
    var nextReviewDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \Member.household)
    var members: [Member]? = []
    // CashEvent / Milestone / Principle / Advisory / Scenario / Snapshot 도 동일하게 소유
}

@Model
final class Member {
    var id: UUID = UUID()
    var name: String = ""                       // "아빠"
    var roleNote: String = ""                   // "본인", "2022년생"
    var birthYearMonth: Date = Date.now         // 나이 계산의 기준
    var taxResidencyRaw: String = TaxResidency.korea.rawValue
    var targetRetirementAge: Int = 65
    var lifeExpectancy: Int = 95                // 고갈 판정 기준
    var colorHex: String = "#4E7CA1"
    var sortIndex: Int = 0
    var household: Household?

    @Relationship(deleteRule: .cascade, inverse: \Account.owner)
    var accounts: [Account]? = []
}

enum TaxResidency: String, Codable, CaseIterable {
    case korea, usa, both      // 미국 세적 → PFIC 경고 대상
}
```

### 3.3.2 계좌 · 보유 자산

```swift
@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""                       // "미래에셋 연금저축"
    var institution: String = ""
    var kindRaw: String = AccountKind.general.rawValue
    var currencyCode: String = "KRW"
    var isLiability: Bool = false               // 대출·마이너스통장
    var isExcludedFromInvestable: Bool = false  // 비상금·보증금 등 "투자자산 아님"
    var annualContributionLimitMinor: Int = 0   // 0 = 한도 없음 (연금저축 600만 등)
    var maturityDate: Date?                     // ISA 만기 등
    var isArchived: Bool = false
    var sortIndex: Int = 0
    var owner: Member?

    @Relationship(deleteRule: .cascade, inverse: \Holding.account)
    var holdings: [Holding]? = []
}

enum AccountKind: String, Codable, CaseIterable {
    case general            // 일반 위탁
    case isa
    case pensionSavings     // 연금저축
    case irp
    case retirementPension  // 퇴직연금 DB/DC
    case insurance          // 연금보험 (해지환급금 기준)
    case deposit            // 예적금·현금
    case leaseDeposit       // 전세보증금
    case realEstate
    case loan               // 부채
    case other
}

@Model
final class Holding {
    var id: UUID = UUID()
    var name: String = ""                       // "삼성전자", "VOO"
    var symbol: String?                         // "005930.KS", "VOO", "KRW-BTC"
    var assetClassRaw: String = AssetClass.equity.rawValue
    var instrumentTypeRaw: String = InstrumentType.stock.rawValue
    var listingCountryCode: String = "KR"       // PFIC 판정에 사용
    var currencyCode: String = "KRW"
    var statusRaw: String = HoldingStatus.accumulating.rawValue

    // 평가 방식 — valuationModeRaw 에 따라 사용하는 필드가 달라진다
    var valuationModeRaw: String = ValuationMode.quantityTimesQuote.rawValue
    var quantityScaled: Int = 0                 // scale 8
    var manualUnitPriceMinor: Int = 0
    var manualValueMinor: Int = 0               // 평가액 직접 입력
    var costBasisMinor: Int = 0                 // 매입원가 합계 (거래에서 재계산 가능)

    var lastQuoteMinor: Int = 0                 // 마지막으로 성공한 시세 (오프라인용 캐시)
    var lastQuoteAt: Date?
    var lastEditedValueAt: Date?                // 수동 갱신 시각 — "언제 마지막으로 손봤나"
    var note: String = ""                       // 1페이지의 ※ 주석
    var sortIndex: Int = 0
    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.holding)
    var transactions: [Transaction]? = []
}

enum HoldingStatus: String, Codable, CaseIterable {
    case accumulating   // 적립중
    case frozen         // 동결 — 신규 자금 0원
    case new            // 신규 (아직 매수 전)
    case closed         // 정리 완료
}

enum AssetClass: String, Codable, CaseIterable {
    case cash, deposit, equity, bond, reit, crypto, realEstate, pension, insurance, other
}

enum InstrumentType: String, Codable, CaseIterable {
    case stock, etf, fund, bond, cash, physical, other   // etf + listingCountry=KR → PFIC 판정
}

enum ValuationMode: String, Codable, CaseIterable {
    case quantityTimesQuote     // 수량 × 자동 시세
    case quantityTimesManual    // 수량 × 직접 입력 단가
    case manualTotal            // 평가액 직접 입력 (보험 해지환급금, 보증금 등)
}
```

### 3.3.3 거래 (선택 기능)

```swift
@Model
final class Transaction {
    var id: UUID = UUID()
    var date: Date = Date.now
    var typeRaw: String = TransactionType.buy.rawValue
    var quantityScaled: Int = 0
    var unitPriceMinor: Int = 0
    var amountMinor: Int = 0        // 현금 흐름 (수익률 계산의 입력)
    var feeMinor: Int = 0
    var taxMinor: Int = 0
    var currencyCode: String = "KRW"
    var note: String = ""
    var holding: Holding?
    var account: Account?
}

enum TransactionType: String, Codable, CaseIterable {
    case buy, sell, deposit, withdraw, dividend, interest, fee, tax, valuationAdjust
}
```

### 3.3.4 적립 계획

1페이지의 "매월 적립 261만 4천 (본인 부담 243만)" 을 구조화한 것.

```swift
@Model
final class ContributionPlan {
    var id: UUID = UUID()
    var member: Member?
    var startDate: Date = Date.now
    var endDate: Date?                  // nil = 은퇴 시점까지
    var annualGrowthRateBP: Int = 0     // 연 증가율 (basis point, 300 = 3%)
    var note: String = ""

    @Relationship(deleteRule: .cascade, inverse: \ContributionAllocation.plan)
    var allocations: [ContributionAllocation]? = []
}

@Model
final class ContributionAllocation {
    var id: UUID = UUID()
    var label: String = ""              // "일반계좌 · VOO 44%"
    var ownAmountMinor: Int = 0         // 본인 부담
    var matchAmountMinor: Int = 0       // 회사 매칭 (연금보험 100% 매칭 등)
    var account: Account?
    var holding: Holding?               // 종목까지 지정하면 자산군별 예측이 정확해진다
    var plan: ContributionPlan?
    // 월 총액 = ownAmountMinor + matchAmountMinor
}
```

### 3.3.5 미래 소득 (연금)

```swift
@Model
final class IncomeStream {
    var id: UUID = UUID()
    var member: Member?
    var name: String = "국민연금"
    var kindRaw: String = IncomeKind.nationalPension.rawValue
    var startAge: Int = 65
    var endAge: Int = 0                 // 0 = 종신
    var monthlyAmountMinor: Int = 0     // 오늘 돈 기준(실질) 또는 명목 — 아래 플래그로 구분
    var isInflationLinked: Bool = true
    var amountIsRealTerms: Bool = true
    var note: String = ""
}

enum IncomeKind: String, Codable, CaseIterable {
    case nationalPension, retirementPension, privatePension, insuranceAnnuity,
         rental, labor, other
}
```

### 3.3.6 목돈 이벤트

```swift
@Model
final class CashEvent {
    var id: UUID = UUID()
    var date: Date = Date.now
    var label: String = ""              // "전세보증금 전환", "퇴직금 유입"
    var amountMinor: Int = 0            // 부호로 방향 표현 (+유입 / -유출)
    var destinationAccount: Account?    // 어디로 들어가는가
    var sourceAccount: Account?         // 어디서 빠지는가
    var isAlreadyReflected: Bool = false // 기준 시점에 이미 반영됨 → 예측에서 제외 (중복 계산 방지)
    var note: String = ""
}
```

> `isAlreadyReflected` 는 1페이지의 *"이 표의 모든 금액은 이사 완료 후 기준 — 중복 계산 방지"*
> 문제를 그대로 모델링한 것입니다. 실제로 겪은 문제이므로 데이터 모델에 넣습니다.

### 3.3.7 마일스톤

```swift
@Model
final class Milestone {
    var id: UUID = UUID()
    var year: Int = 2049
    var label: String = ""                  // "일하지 않아도 되는 시점"
    var detail: String = ""
    var autoKindRaw: String = MilestoneAutoKind.none.rawValue
    var targetAmountMinor: Int = 0          // 0 = 예측값 사용
    var sortIndex: Int = 0
}

enum MilestoneAutoKind: String, Codable, CaseIterable {
    case none                    // 사용자가 연도를 직접 지정
    case returnsExceedContrib    // 연간 수익 > 연간 적립금
    case returnsExceedSalary     // 연간 수익 > 연소득
    case assetsReachTarget       // 목표 금액 도달
    case pensionStart            // 국민연금 개시
    case retirement              // 은퇴 시점
}
```

### 3.3.8 운용 원칙 (자동 점검)

```swift
@Model
final class Principle {
    var id: UUID = UUID()
    var index: Int = 1
    var title: String = ""                  // "개별주 4% · KODEX 200 5% 상한"
    var detail: String = ""                 // "넘으면 매수 중단"
    var checkKindRaw: String = CheckKind.textOnly.rawValue
    var thresholdBP: Int = 0                // 400 = 4%
    var scopeMemberID: UUID?                // nil = 가구 전체
    var scopeHoldingID: UUID?               // 특정 종목 대상일 때
    var scopeAssetClassRaw: String?
    var scopeCountryCode: String?
    var amountMinor: Int = 0                // 금액 기준 규칙(비상금 하한 등)
    var reviewIntervalMonths: Int = 3
    var lastReviewedAt: Date?
}

enum CheckKind: String, Codable, CaseIterable {
    case textOnly              // 점검 불가 — 표시만 ("하락장에도 멈추지 않는다")
    case positionWeightCap     // 개별 종목 비중 상한
    case assetClassWeightCap   // 자산군 비중 상한
    case countryWeightCap      // 지역 비중 상한 (국내 60% 등)
    case countryTargetSplit    // 목표 배분 대비 편차 (국내 50 / 미국 50)
    case minCashReserve        // 현금성 자산 하한 (비상금)
    case frozenNoNewMoney      // 동결 종목에 신규 매수 감지
}
```

### 3.3.9 유의사항 · 할 일

```swift
@Model
final class Advisory {
    var id: UUID = UUID()
    var categoryRaw: String = AdvisoryCategory.tax.rawValue
    var title: String = ""
    var body: String = ""
    var dueDate: Date?
    var isDone: Bool = false
    var repeatsAnnually: Bool = false       // "매년 1월 재조정"
    var notifyDaysBefore: Int = 30
    var relatedAccountID: UUID?
    var sortIndex: Int = 0
}

enum AdvisoryCategory: String, Codable, CaseIterable {
    case tax          // 증여 신고, Form 8621, FBAR/FATCA
    case limit        // 연금저축 600만, ISA 1억
    case schedule     // 다음 점검, 만기
    case constraint   // PFIC 금지 등 제약
    case memo
}
```

### 3.3.10 시나리오 · 가정

```swift
@Model
final class Scenario {
    var id: UUID = UUID()
    var name: String = "기본"
    var isDefault: Bool = true
    var inflationRateBP: Int = 200                  // 2.0%
    var retirementMonthlySpendMinor: Int = 0        // 은퇴 후 목표 생활비 (실질)
    var overrideRetirementAge: Int = 0              // 0 = 구성원 설정 사용
    var contributionMultiplierBP: Int = 10_000      // 10000 = 100% (What-if 슬라이더)
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \AssetClassAssumption.scenario)
    var assumptions: [AssetClassAssumption]? = []
}

@Model
final class AssetClassAssumption {
    var id: UUID = UUID()
    var assetClassRaw: String = AssetClass.equity.rawValue
    var expectedReturnBP: Int = 800                 // 연 8.0%
    var volatilityBP: Int = 1500                    // 연 15.0% (몬테카를로용)
    var scenario: Scenario?
}
```

### 3.3.11 스냅샷 (실제 기록)

```swift
@Model
final class Snapshot {
    var id: UUID = UUID()
    var date: Date = Date.now                       // 일 단위로 정규화
    var totalNetWorthMinor: Int = 0
    var investableMinor: Int = 0
    var liabilityMinor: Int = 0
    var baseCurrencyCode: String = "KRW"

    @Relationship(deleteRule: .cascade, inverse: \SnapshotLine.snapshot)
    var lines: [SnapshotLine]? = []
}

@Model
final class SnapshotLine {
    var id: UUID = UUID()
    var memberID: UUID?
    var assetClassRaw: String = AssetClass.equity.rawValue
    var countryCode: String = "KR"
    var valueMinor: Int = 0
    var snapshot: Snapshot?
}
```

- 하루 1건. 앱 실행 시 또는 BGAppRefresh로 기록.
- 구성원·자산군·국가 3축으로 분해해 두면 과거 배분 추이도 그릴 수 있다.
- 개별 종목 단위로는 저장하지 않는다(용량). 필요해지면 별도 테이블로 확장.

## 3.4 파생 계산 (저장하지 않음)

### 3.4.1 평가

```
holding.value =
  switch valuationMode
    .quantityTimesQuote  → quantity × (quote ?? lastQuote) × fx(holding.currency → base)
    .quantityTimesManual → quantity × manualUnitPrice × fx
    .manualTotal         → manualValue × fx

account.value    = Σ holdings.value       (isLiability 이면 음수로 집계)
member.value     = Σ accounts.value
household.total  = Σ members.value
investable       = Σ where !account.isExcludedFromInvestable && !isLiability
netWorth         = 자산 합계 − 부채 합계
```

### 3.4.2 비중

```
positionWeight(h)  = h.value / investable
assetClassWeight   = Σ(자산군) / investable
countryWeight      = Σ(listingCountry) / investable
```

### 3.4.3 수익률

- 종목 단순 수익률 = `(평가액 − 원가) / 원가` — 거래 내역이 있을 때만
- 가구 전체 **XIRR** — 외부 현금흐름(입금/출금/적립)과 현재 평가액으로 계산.
  Newton–Raphson, 발산 시 이분법 폴백. → [ADR-0002](adr/0002-projection-engine.md)

### 3.4.4 원칙 점검

각 `Principle`은 `(Portfolio) -> CheckResult` 함수로 변환된다.

```swift
enum CheckResult {
    case notApplicable
    case pass(actual: Decimal)
    case violation(actual: Decimal, threshold: Decimal, offenders: [UUID])
}
```

세적 제약(PFIC)은 원칙과 별개로 항상 켜져 있는 **내장 검사**다:

```
member.taxResidency ∈ {usa, both}
  && holding.instrumentType == .etf
  && holding.listingCountry == "KR"
  → 경고
```

## 3.5 마이그레이션

- `VersionedSchema` + `SchemaMigrationPlan`을 처음부터 도입한다. v1 출시 후에는
  경량 마이그레이션만으로 해결되지 않는 변경이 반드시 생긴다.
- CloudKit이 붙으면 **속성 삭제·이름 변경이 비싸다.** 애매하면 새 속성을 추가하고
  옛 속성은 남겨 둔다.
- 스키마 변경 시마다 "이전 버전 데이터 → 새 버전" 마이그레이션 테스트를 추가한다.
