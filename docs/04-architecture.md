# 4. 기술 아키텍처

## 4.1 기술 선택

| 영역 | 선택 | 이유 |
|---|---|---|
| 최소 지원 | iOS 17.0 | SwiftData, Swift Charts, `ImageRenderer`, Observation 사용 |
| UI | SwiftUI | 화면 대부분이 목록·차트·폼. UIKit 필요 지점이 거의 없다 |
| 상태 | `@Observable` (Observation) | ObservableObject 대비 불필요한 재렌더 감소 |
| 영속성 | SwiftData | Core Data보다 모델 정의가 짧고 CloudKit 미러링을 그대로 쓴다 |
| 동기화 | CloudKit private DB | 서버 없이 기기 간 동기화. 계정 시스템 불필요 |
| 차트 | Swift Charts | 밴드(`AreaMark`) + 선 + 기준선 조합을 표준으로 지원 |
| 동시성 | Swift Concurrency | 몬테카를로 시뮬레이션을 `async`/`actor`로 |
| 테스트 | Swift Testing | 계산 로직 중심. XCTest는 UI 테스트에만 |
| 의존성 | 없음 (v1) | 외부 패키지 없이 간다. 필요해지면 그때 추가 |

## 4.2 모듈 구조

로컬 SPM 패키지로 쪼갭니다. 핵심 목적은 **계산 로직을 시뮬레이터 없이 초 단위로 테스트**하는 것입니다.

```
Assetly.xcodeproj
├─ Assetly/                 (앱 타깃 — 얇게 유지)
│   ├─ AssetlyApp.swift     @main, ModelContainer 구성, 딥링크
│   └─ Root/                탭 구성, 앱 잠금 게이트
│
├─ Packages/
│   ├─ Core/                ★ 순수 Swift. Foundation 외 의존 없음. 테스트 100% 목표
│   │   ├─ Money/           Money, Quantity, Currency, 포맷터
│   │   ├─ Portfolio/       평가·비중·수익률(XIRR) 계산
│   │   ├─ Projection/      결정론적 프로젝션 + 몬테카를로
│   │   ├─ Rules/           원칙 점검, 세적 제약, 한도 계산
│   │   └─ Ports/           QuoteProviding, FXProviding, Clock 등 프로토콜
│   │
│   ├─ Persistence/         SwiftData 모델 + Repository. Core에 의존
│   │   ├─ Models/          @Model 타입
│   │   ├─ Migration/       VersionedSchema, MigrationPlan
│   │   └─ Mapping/         @Model ↔ Core 값 타입 변환
│   │
│   ├─ Services/            기기 서비스 어댑터. Ports 구현
│   │   ├─ Scheduling/      주간 점검 알림 (UNUserNotificationCenter)
│   │   ├─ ImportExport/    CSV
│   │   └─ Export/          1페이지 PDF/PNG 렌더
│   │
│   ├─ DesignSystem/        색·타이포·숫자 포맷·공용 컴포넌트·차트 스타일
│   │
│   └─ Features/            화면. 위 패키지에만 의존
│       ├─ Dashboard/       현황판 + 1페이지 렌더러
│       ├─ Assets/          자산 목록 · 주간 점검 · 점검 완료 · 편집
│       ├─ Plan/            적립 · 연금 · 목돈 · 마일스톤 · 가정
│       ├─ Simulation/      What-if
│       └─ More/            원칙 · 유의사항 · 내보내기 · 설정
│
└─ Widgets/                 WidgetKit (v1.1)
```

**의존성 방향은 한 방향입니다.**

```
Features ─→ DesignSystem
    │           │
    ├───────────┼─→ Persistence ─→ Core
    └───────────┴─→ Services ────→ Core
```

`Core`는 SwiftData도 SwiftUI도 모릅니다. 프로젝션 엔진과 원칙 점검이
이 앱에서 가장 틀리기 쉬운 부분이고, 그래서 가장 테스트하기 쉬워야 합니다.

## 4.3 데이터 흐름

```
   SwiftData (@Model)
        │  @Query / FetchDescriptor
        ▼
   Repository ──→ Core 값 타입(Portfolio, PlanInputs)
        │
        ▼
   ViewModel (@Observable)
        │  ├─→ PortfolioCalculator   (동기, 즉시)
        │  ├─→ RuleChecker           (동기, 즉시)
        │  └─→ ProjectionEngine      (async, 백그라운드 actor)
        ▼
   SwiftUI View
```

- 화면은 **마지막 점검 값으로 즉시 그린다.** 네트워크를 기다리는 자리가 없다.
  백그라운드로 채우는 것은 몬테카를로뿐이다.
- What-if 슬라이더는 드래그 중 **결정론적 프로젝션만** 재계산하고(수 ms),
  손을 떼면 몬테카를로를 돌린다. 60fps 유지를 위한 핵심 트릭.

## 4.4 프로젝션 엔진

→ 상세: [ADR-0002](adr/0002-projection-engine.md)

```swift
public struct ProjectionInput: Sendable {
    var startDate: Date
    var openingBalances: [MemberID: [AssetClass: Money]]
    var contributions: [ContributionSchedule]   // 월 금액, 증가율, 기간, 대상 자산군
    var cashEvents: [CashEventInput]            // 반영 안 된 것만
    var incomes: [IncomeStreamInput]            // 연금
    var assumptions: [AssetClass: (mean: Double, stdev: Double)]
    var inflation: Double
    var retirement: [MemberID: (age: Int, monthlySpend: Money)]
    var horizonYears: Int
}

public struct ProjectionResult: Sendable {
    var monthly: [ProjectionPoint]              // 중앙값 경로
    var band: [ProjectionBand]?                 // p10 / p50 / p90 (몬테카를로 시)
    var byMember: [MemberID: [ProjectionPoint]]
    var successProbability: Double?             // 고갈되지 않을 확률
    var depletionAge: Int?
    var milestoneHits: [MilestoneAutoKind: Date]
}
```

월 단위로 진행하며 각 스텝에서:
1. 적립 유입 (증가율 반영, 종료 시점 확인)
2. 목돈 이벤트 적용
3. 자산군별 수익률 적용 (결정론: 기대값 / 몬테카를로: 샘플)
4. 은퇴 이후면 `생활비 − 연금소득` 만큼 인출
5. 잔고 0 도달 시 고갈 나이 기록

## 4.5 주간 점검 알림

외부 데이터를 가져오지 않으므로 네트워크 계층이 없습니다. 대신 **알림이 이 앱의 유일한 외부 트리거**이며,
알림이 도달하지 않으면 앱이 죽습니다. 그만큼 방어적으로 만듭니다.

```swift
public protocol ReviewScheduling: Sendable {
    func scheduleWeekly(weekday: Int, hour: Int, minute: Int) async throws
    func scheduleFollowUp(after: Date) async throws     // 미입력 시 재알림
    func cancelAll() async
}
```

- `UNCalendarNotificationTrigger(dateMatching: .init(weekday: 7, hour: 9), repeats: true)` — 기본 토요일 9시
- **재알림**: 토요일 알림 후 24시간 안에 점검이 완료되지 않으면 일요일 같은 시각에 1회 더.
  두 번째도 놓치면 그 주는 조용히 넘어간다(잔소리하지 않는다).
- 알림 권한 거부 상태를 앱이 알고 있어야 한다. 거부되어 있으면 현황판 상단에
  "알림이 꺼져 있어 토요일에 알려드릴 수 없습니다" 배너를 띄운다.
- 알림 본문에 금액을 넣을지는 설정으로 고른다(잠금 화면 노출).
- 확장 알림의 **총액 빠른 입력**은 `UNTextInputNotificationAction`으로 받고,
  App Group 없이 앱 프로세스에서 처리한다(Notification Content Extension은 v1에 쓰지 않는다).
- 알림 재등록은 앱 실행 시마다 idempotent하게 수행한다. 시간대 변경·기기 이전에 대비.

### 통화 — 하나로 통일한다 (2026-09 수정)

**앱이 통화를 다루지 않습니다.** 모든 금액은 원화이고, 해외 종목도 사용자가
원화로 환산해서 적습니다.

한때 통화별 입력과 환율 직접 입력을 만들었다가 걷어냈습니다. 사용자가 이미
원화로 환산해서 적고 있는데 앱이 환율을 들고 있으면, 환율을 안 넣은 종목이
합계에서 조용히 빠지는 함정만 남습니다. 자세한 이유는
[ADR-0005 후속](adr/0005-manual-entry.md)에 있습니다.

`Core` 의 `Money` 는 여전히 통화를 들고 다니고 `converted(to:rate:)` 도 있습니다.
쓰지 않을 뿐입니다 — 정말 필요해지면 그때 Core 를 열면 됩니다.

## 4.6 보안 · 프라이버시

| 항목 | 방식 |
|---|---|
| 저장 | 기기 로컬 + 사용자 개인 iCloud (CloudKit private DB). 개발자 접근 불가 |
| 앱 잠금 | `LocalAuthentication` — 실행 시 및 백그라운드 N초 후 복귀 시 Face ID |
| 화면 가리기 | 앱 전환기 스냅샷 블러, 금액 가리기 토글 |
| 파일 보호 | `NSFileProtectionComplete` |
| 비밀 값 | API 키만 Keychain. 사용자 금융 데이터는 Keychain에 넣지 않음 |
| 네트워크 | **없음.** iCloud 동기화 외에 어떤 아웃바운드 요청도 하지 않는다 |
| 로그 | 릴리즈 빌드에서 금액·종목명 로깅 금지. 크래시 리포터에도 미포함 |
| 백업 | CSV 내보내기 시 공유 시트로만 전달. 자동 업로드 없음 |

App Store 제출 시 개인정보 처리방침과 App Privacy(“데이터 미수집”) 신고가 필요합니다.

## 4.7 1페이지 렌더링

내보내기 전용 SwiftUI 뷰를 **화면용 뷰와 분리해서** 만듭니다.

- A4 비율 고정 레이아웃 (`595 × 842 pt`)
- `ImageRenderer(content:)` → `renderer.render { size, ctx in ... }` 로 PDF 생성
- 화면용 컴포넌트를 재사용하되 폰트 스케일과 여백은 별도 토큰
- 스냅샷 테스트로 회귀 방지

## 4.8 테스트 전략

| 계층 | 방식 | 목표 |
|---|---|---|
| Core (Money/Portfolio/Rules) | Swift Testing 단위 테스트 | 커버리지 높게. 경계값(0, 음수, 대금액) 필수 |
| Projection | 알려진 입력 → 손계산 기대값 비교, 몬테카를로는 통계적 성질 검증 | 회귀 방지 |
| Review | 연속 기록 계산(건너뛴 주, 총액만 기록한 주, 시간대 경계) | 경계 조건 필수 |
| Persistence | 인메모리 `ModelContainer` | 마이그레이션 포함 |
| Services | 프로토콜 목(mock) · 알림 등록은 가짜 스케줄러로 | 시간 관련은 `Clock` 주입 |
| Features | 스냅샷 테스트(1페이지 렌더 포함) | 레이아웃 회귀 방지 |
| E2E | 온보딩 → 입력 → 현황판 확인 1개 시나리오 | 최소한만 |

CI는 GitHub Actions에서 `Core` 패키지 테스트만 먼저 돌립니다(빠름).
시뮬레이터 빌드는 PR 머지 전 1회.
