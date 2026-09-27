# 3. 도메인 · 데이터 모델

> **원본은 `App/SlowRich.xcdatamodeld` 다** (Core Data, 4차에서 SwiftData 에서 옮겼다 —
> [09](09-family-sharing.md)). `@NSManaged` 선언(`App/Persistence/Generated/`)과
> CloudKit 스키마(`Tools/cloudkit/slowrich.ckdb`)가 거기서 파생되고, CI 가 셋을 대조한다.
> 아래 **3.1 이 지금 모델**이고(2026-09-27 전수 조사로 다시 썼다), **3.3 은 처음
> 설계할 때의 SwiftData 스케치**라 이름·칸이 다르다 — 무엇이 왜 바뀌었는지 보는 기록으로 남긴다.

## 3.1 엔티티 개요 — 지금 모델 (19개)

```
Household (가구, 공유의 뿌리 — 모든 엔티티가 household 로 매달린다)
 ├── Member (구성원) ──cascade── Account (계좌) ──cascade── Holding (종목)
 │                                                          └─cascade─ HoldingNote (왜 샀나 이력)
 ├── Plan (계획 — 적립 · 가정 · 목표 · 진단 기준을 한 곳에)
 ├── IncomeStream (연금 · 미래 소득)      ├── CashEvent (목돈 이벤트)
 ├── UserMilestone (내 마일스톤)          ├── Principle (운용 원칙)
 ├── TodoItem (챙길 것)                   ├── FamilyTarget (가족 목표 비중)
 ├── Scenario (저장한 시뮬레이션)          ├── DiaryEntry (목 · 실 · 감)
 ├── ReviewSession (주간 점검 1회)         ├── ChangeLog (변경 이력)
 ├── Snapshot (주간 총액) ──cascade── SnapshotLine (구성원별 분해)
 └── HoldingRecord (종목별 주간 값 — 종목을 지워도 남는다)
```

| 엔티티 | 속성 | 무엇 | 처음 스케치와 다른 점 |
|---|---:|---|---|
| Household | 4 | 공유 단위(`CKShare` 의 뿌리) | 제목 · 기준 시점 · 선언문은 `Plan` 으로 갔다 |
| Member | 16 | 이름 · 생년월 · 세적 · 은퇴 나이 · 월 적립 · 회사 매칭 · 월급 · `editorIDs`(편집 권한) · 색 번호 | 기대수명 · 색 코드 대신 색 번호 |
| Account | 14 | 종류 · 기관 · 연 납입 한도 · 만기 · 월세 · 매매가 | **통화 없음** (전부 원화) |
| Holding | 15 | 자산군 · 상품 유형 · 상장 국가 · 상태 · 입력 주기 · 평가액 · 목표 비중 | 통화 · 수량 · 단가 · 원가 없음 |
| HoldingNote | 4 | 종목 "왜 샀나" 한 줄 + 날짜 · 적은 사람 | 187번에서 새로 |
| HoldingRecord | 7 | 종목별 주간 값 (이름 · 계좌 이름을 함께 적어 종목을 지워도 남는다) | A3 에서 새로 — 스케치는 "종목 단위로는 저장하지 않는다" 였다 |
| Plan | 35 | 제목 · 시작 · 은퇴 연도 · 월 적립 · 수익률(자산군별) · 물가 · 은퇴 후 수익률 · 목표 · 생활비 · 인출률 · 진단 기준 · 채우는 순서 · 지평선 | 스케치의 `Household` 머리 · `ContributionPlan` · `Scenario.Assumptions` 를 합쳤다 |
| IncomeStream | 7 | 연금 이름 · 월 금액 · 시작/끝 연도 · 물가 연동 | 구성원 연결 없음 |
| CashEvent | 7 | 날짜 · 이름 · 금액(부호가 방향) · 미리 받음 · 메모 | 배치 계좌 없음. `isAlreadyReflected` 는 188번부터 앞으로의 날짜에만 뜻이 있다 |
| UserMilestone | 6 | 연도 · 이름 · 메모 · 구성원 | 자동 마일스톤은 저장하지 않고 궤적에서 계산 |
| Principle | 6 | 순서 · 제목 · 설명 · 점검 메모 | **자동 점검 규칙은 여기 없다** — 규칙은 `자산 진단`(Core `Diagnostics`)이 맡는다 |
| TodoItem | 10 | 제목 · 분류 · 기한 · 완료 · 해마다 반복 | 스케치의 `Advisory` |
| FamilyTarget | 4 | 가족 단위 목표 비중(축 · 키 · 비중) | 새로 |
| Scenario | 8 | 이름 · 월 적립 · 은퇴 연도 · 수익률 · 변동성 · 그때 예상 | `Assumptions` 는 없다 |
| ReviewSession | 11 | 주 · 시작/완료 · 적은 수 · 총액만 · 적은 구성원 · 그 주 진단 | |
| Snapshot | 5 | 주 · 순자산 · 투자자산 · 부채 | 자산군 · 국가 분해 없음 |
| SnapshotLine | 5 | 구성원별 값 (이름을 함께 적는다) | 자산군 · 국가 축 없음 |
| DiaryEntry | 6 | 날짜 · 목표 · 실적 · 감사 | 마지막 묶음에서 새로 |
| ChangeLog | 6 | 언제 · 누가 · 종류 · 대상 · 요약 | 29번 · 111번 |

**스케치에 있었지만 만들지 않은 것:** `Transaction`(거래), `ContributionAllocation`
(적립 배분), `Assumptions`, 자동 점검 규칙이 달린 `Principle`, 통화 · 환율.

**CloudKit 규칙** — 유니크 제약 없음, 모든 속성 기본값, 모든 관계 옵셔널
([ADR-0001](adr/0001-swiftdata-cloudkit.md)). 관계는 구성원 → 계좌 → 종목 → 이력만
cascade 이고, 나머지는 `Household` 에 nullify 로 매달린다.

## 3.2 설계 원칙

1. **보유 자산의 평가액이 진실의 원천이다.** 사용자가 매주 직접 적는 그 숫자다.
   ~~거래 내역은 선택 기능이며,~~ 거래 내역은 만들지 않았다 *(2026-09-27 현재)*.
2. **시세를 저장할 자리를 두지 않는다.** 외부에서 가져오지 않으므로 캐시가 없다.
   → [ADR-0005](adr/0005-manual-entry.md)
3. **금액은 스케일드 정수로 저장한다.** → [ADR-0003](adr/0003-money-representation.md)
4. **enum은 `String` rawValue로 저장한다.** 스키마 안정성과 CloudKit 호환 때문.
5. **모든 속성에 기본값을, 모든 관계를 옵셔널로.** CloudKit 미러링 제약.
   → [ADR-0001](adr/0001-swiftdata-cloudkit.md)
6. **계산 결과는 저장하지 않는다.** 단, 주간 스냅샷 · 종목별 주간 값(`HoldingRecord`)은 예외
   (과거 사실 보존). ~~프로젝션 캐시~~ 는 두지 않았다 — 궤적은 화면 밖에서 매번 굴린다(153 · 157번).

## 3.3 SwiftData 스키마 (처음 스케치 — 역사 기록)

> **지금 모델이 아니다.** 지금 모델은 3.1 과 `App/SlowRich.xcdatamodeld`. 이 절은
> 처음 무엇을 생각했는지 남겨 둔 것이다. 실제 구현 시 세부는 달라질 수 있습니다. 관계·필수 필드·enum 값 집합을 확정하는 것이 목적입니다.

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
    case leaseDeposit       // 전월세보증금
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
    var cadenceRaw: String = EntryCadence.weekly.rawValue   // 주간 점검 대상 여부

    // 평가 방식 — valuationModeRaw 에 따라 사용하는 필드가 달라진다
    var valuationModeRaw: String = ValuationMode.manualTotal.rawValue
    var quantityScaled: Int = 0                 // scale 8
    var manualUnitPriceMinor: Int = 0
    var manualValueMinor: Int = 0               // 평가액 직접 입력 (기본)
    var costBasisMinor: Int = 0                 // 매입원가 합계 (거래에서 재계산 가능)

    var lastEnteredValueMinor: Int = 0          // 직전 점검에서 적어 넣은 값 (증감 표시용)
    var lastEnteredAt: Date?                    // 마지막으로 적어 넣은 시각
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
    case manualTotal            // 평가액 직접 입력 — 기본이자 대부분
    case quantityTimesManual    // 수량 × 직접 입력 단가
}

enum EntryCadence: String, Codable, CaseIterable {
    case weekly     // 매주 점검 대상
    case monthly    // 월 1회만 (연금보험 해지환급금 등)
    case fixed      // 값이 잘 안 바뀜 — 점검에서 자동으로 건너뜀 (전월세보증금 등)
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
    var label: String = ""              // "전월세보증금 전환", "퇴직금 유입"
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

### 3.3.11 주간 점검 세션

```swift
@Model
final class ReviewSession {
    var id: UUID = UUID()
    var scheduledFor: Date = Date.now       // 그 주 토요일 (주 단위로 정규화)
    var startedAt: Date?
    var completedAt: Date?
    var enteredCount: Int = 0
    var totalCount: Int = 0
    var isTotalOnly: Bool = false           // 알림에서 총액만 적고 넘어간 주
    var totalOnlyValueMinor: Int = 0
    var note: String = ""
    var snapshotID: UUID?                   // 완료 시 만들어진 스냅샷
}
```

- 주 1건. 건너뛴 주는 세션이 없거나 `completedAt == nil` 로 남는다.
- **연속 기록 주차** = `completedAt != nil` 인 세션이 끊기지 않고 이어진 수.
- `isTotalOnly` 인 주는 궤적에 점은 찍히되 구성원·자산군 분해가 비어 있고,
  다음 점검에서 채워지면 그 주로 소급 배분한다.

### 3.3.12 스냅샷 (실제 기록)

```swift
@Model
final class Snapshot {
    var id: UUID = UUID()
    var date: Date = Date.now                       // 점검일 (주 단위로 정규화)
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

- **주 1건.** 주간 점검을 완료할 때만 만들어진다. 자동 생성하지 않는다.
- 구성원·자산군·국가 3축으로 분해해 두면 과거 배분 추이도 그릴 수 있다.
- 개별 종목 단위로는 저장하지 않는다(용량). 필요해지면 별도 테이블로 확장.
- 궤적의 "실제" 선은 이 스냅샷을 이은 것이다. 빠진 주는 선을 잇되 점은 찍지 않는다.

## 3.4 파생 계산 (저장하지 않음)

### 3.4.1 평가

*(현재: `holding.value = valueMinor` 하나 — 평가 방식 선택 · 환율은 없다. 아래는 처음 스케치)*

```
holding.value =
  switch valuationMode
    .manualTotal         → manualValue × fx(holding.currency → base)
    .quantityTimesManual → quantity × manualUnitPrice × fx

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

- ~~종목 단순 수익률 = `(평가액 − 원가) / 원가` — 거래 내역이 있을 때만~~
- ~~가구 전체 **XIRR**~~ *(현재: 둘 다 만들지 않았다. 대신 `얼마 넣어서 얼마 자랐나` 가 증감을 넣은 돈 · 목돈 · 자란 돈으로 어림한다 — `ChangeAttribution`, 82번 · 188번)*

### 3.4.5 계획 대비 실적

점검 완료 화면과 현황판의 핵심 숫자.

```
planned(t)   = 기본 시나리오 프로젝션의 t 시점 값
actual(t)    = t 주의 스냅샷 총액
gap(t)       = actual(t) − planned(t)
gapRate(t)   = gap(t) / planned(t)
```

계획선의 기준 시점은 **계획 수립일에 고정**한다. 가정을 바꿀 때마다 과거 계획선까지
움직이면 "계획보다 앞서 있다"는 말이 의미를 잃는다. ~~가정을 바꾸면 그 시점부터 새 계획선을
그리고, 이전 계획선은 옅게 남긴다.~~

*(현재: 계획선은 `최초 계획 수립일` 뒤 **처음 적은 주의 총자산**에서 출발해 계획 가정으로 굴린 선 하나다(37 · 46번, `PlanTrack`). 점 사이 날짜는 `ProjectionResult.nominal(at:)` 로 읽어 그사이 받은 목돈까지 맞춘다(188번). 목돈의 `미리 받음` 토글은 계획선에서 보지 않는다.)*

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

*(현재: Core Data **경량 마이그레이션** 하나로 간다. 칸은 더하기만 하고 지우거나 이름을 바꾸지 않는다. 칸을 더하면 `.xcdatamodeld` · `Generated/` · `.ckdb` 를 함께 고치고 CloudKit 스키마를 다시 올린다 — [06](06-testflight.md). 아래 `VersionedSchema` 는 SwiftData 시절 계획이다.)*

- ~~`VersionedSchema` + `SchemaMigrationPlan`을 처음부터 도입한다.~~ v1 출시 후에는
  경량 마이그레이션만으로 해결되지 않는 변경이 반드시 생긴다.
- CloudKit이 붙으면 **속성 삭제·이름 변경이 비싸다.** 애매하면 새 속성을 추가하고
  옛 속성은 남겨 둔다.
- 스키마 변경 시마다 "이전 버전 데이터 → 새 버전" 마이그레이션 테스트를 추가한다.
