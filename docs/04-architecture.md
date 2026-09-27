# 4. 기술 아키텍처

> **2026-09-27 전수 조사로 4.1~4.3 을 지금 구조로 다시 썼다.** 처음 설계는
> SwiftData · `@Observable` · 패키지 다섯 개(`Assetly` 라는 가칭)였고, 가족 공유를
> 위해 Core Data 로 옮기면서(4차, [09](09-family-sharing.md)) 모양이 바뀌었다.

## 4.1 기술 선택

| 영역 | 선택 | 이유 |
|---|---|---|
| 최소 지원 | iOS 17.0 · Swift 6 (엄격한 동시성) | Swift Charts, `ImageRenderer` |
| UI | SwiftUI | 화면 대부분이 목록·차트·폼. 핀치 줌 하나만 UIKit(`ZoomableScrollView`) |
| 상태 | `@ObservedObject`(관리 객체) · `@Fetched`(속은 `@FetchRequest`, 겉은 `[T]`) · `@State` | ~~`@Observable`~~ — Core Data 관리 객체는 `ObservableObject` 다 |
| 영속성 | **Core Data** (`NSPersistentCloudKitContainer`) | ~~SwiftData~~ — `CKShare` 가족 공유를 SwiftData 가 못 해서 옮겼다 |
| 동기화 | CloudKit **private + shared** DB | 서버 없이 기기 간 · 가족 간 동기화. 계정 시스템 불필요 |
| 차트 | Swift Charts | 밴드(`AreaMark`) + 선 + 기준선 조합을 표준으로 지원 |
| 동시성 | Swift Concurrency | 궤적 · 몬테카를로를 `Task.detached` 로. 넘기는 것은 값 타입뿐 (관리 객체는 넘기지 않는다) |
| 테스트 | Swift Testing (`Packages/Core`) | 계산 로직 중심. 앱은 CI 스크린샷이 심판 |
| 의존성 | 없음 | 외부 패키지 없이 간다 |
| 프로젝트 | XcodeGen (`project.yml`) | `.xcodeproj` 는 생성물이라 커밋하지 않는다 |

## 4.2 모듈 구조

**패키지는 `Core` 하나다.** 핵심 목적은 **계산 로직을 시뮬레이터 없이 초 단위로 테스트**하는
것이고, 그 밖은 앱 타깃 안의 폴더로 나눈다 ([ADR-0002](adr/0002-projection-engine.md)).

```
project.yml                 XcodeGen 명세 → SlowRich.xcodeproj (생성물)
App/                        앱 타깃 "SlowRich" (표시 이름: 느린 부자)
├─ SlowRichApp.swift        @main, 저장소 구성, 공유 수락
├─ RootView.swift           탭 다섯 · 가로/iPad 좌측 메뉴 · 상태 띠(StatusBand)
├─ SlowRich.xcdatamodeld    ★ 모델의 원본
├─ Persistence/             저장소 · Generated/(@NSManaged) · 모델 확장 · 자동 저장 · 체험 자료
├─ Services/                알림 · 백업 · 가족 공유 · 동기화 감시 · 앱 잠금 · 계획선(PlanTrack) · 회고
├─ DesignSystem/            색 · 글자(Typography) · 읽을 수 있는 너비
└─ Features/                화면 — Dashboard · Assets · Review · Plan · Simulation ·
                            Diagnostics · History · Notes · Diary · More · Settings · Onboarding · Shared
Packages/Core/              ★ 순수 Swift. Foundation 외 의존 없음
├─ Money/                   Money · Ratio · Decimals(반올림 한 곳) · 한국식 금액 포맷
├─ Domain/ · Portfolio/     분류 · 평가 · 비중 · 증감 분해(ChangeAttribution)
├─ Projection/              결정론 궤적 + 몬테카를로
├─ Diagnostics/             자산 진단 일곱 규칙
├─ Retirement/              국민연금 추정 등
└─ Review/                  주 계산 · 연속 기록 · 원칙 돌리기 · 일기 연속
Tools/                      아이콘 · CloudKit 스키마 생성/대조 · 검증용 파이썬
```

~~`Widgets/` (WidgetKit)~~ — 위젯은 2026-09-22 뺐다.

**의존성 방향은 한 방향입니다.** 앱의 폴더들은 서로 쓰지만 `Core` 는 아무것도 모른다.

```
App (Features · Services · Persistence · DesignSystem) ─→ Core
```

`Core`는 Core Data 도 SwiftUI 도 모릅니다. 프로젝션 엔진과 진단이
이 앱에서 가장 틀리기 쉬운 부분이고, 그래서 가장 테스트하기 쉬워야 합니다.

## 4.3 데이터 흐름

```
   Core Data (관리 객체)
        │  @Fetched / @ObservedObject
        ▼
   화면 (SwiftUI View)
        │  값만 뽑는다 → Core 입력 (ProjectionInput · DiagnosticsInput …)
        ├─→ 평가 · 비중 · 진단          (동기, 입력이 바뀔 때 한 번)
        └─→ 궤적 · 몬테카를로           (Task.detached, `.task(id:)` 로 마지막 것만)
        ▼
   화면은 마지막으로 끝난 결과를 그리기만 한다
```

- 화면은 **마지막 점검 값으로 즉시 그린다.** 네트워크를 기다리는 자리가 없다.
- 그리는 중에 무거운 계산을 하지 않는다 (153 · 157번). 손잡이는 누르는 즉시 화면
  값만 바꾸고 250ms 뒤 한 번 쓴다 (`DeferredStepper`, 166 · 169번).
- 시간이 걸리는 일은 화면마다 표시하지 않고 **상태 띠 하나**가 알린다 (169번).
- 편집은 살아 있는 객체에 바로 쓰고 400ms 자동 저장(`Autosave`)이 저장한다. `취소` 는
  열 때 떠 둔 값으로 되돌린다 (`EditSnapshot`, 104번). 지운 객체는 다시 그리지 않는다 (189번).

## 4.4 프로젝션 엔진

→ 상세: [ADR-0002](adr/0002-projection-engine.md)

> 아래 타입은 처음 스케치다. 지금 `ProjectionInput` 은 **덩어리(bucket)별 잔고 · 수익률**,
> 월 적립, 목돈(날짜 · 금액), 연금, 은퇴 연도 · 은퇴 후 수익률 · 생활비, 지평선을 받고,
> `ProjectionResult` 는 월별 점 · 연도 요약 · 자동 마일스톤 · 바닥나는 날 · 적용된 목돈을
> 돌려준다. 구성원별 궤적은 `Plan.memberProjection` 이 사람마다 따로 굴린다.

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

*(아래 프로토콜은 스케치다. 지금은 `ReviewNotifications`(등록) · `ReviewScheduling`(언제) 두 enum 이다.)*

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
- 알림 권한 거부 상태를 앱이 알고 있어야 한다. ~~거부되어 있으면 현황판 상단에
  "알림이 꺼져 있어 토요일에 알려드릴 수 없습니다" 배너를 띄운다.~~ *(현재: 더보기의
  `알림` 줄과 알림 화면에 "알림이 꺼져 있습니다" 가 뜬다)*
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
| 파일 보호 | iOS 기본 데이터 보호 (따로 등급을 올리지 않았다) |
| 비밀 값 | 앱에 비밀 값이 없다 — API 키도 없다. 빌드 · 업로드용 키는 GitHub 시크릿에만 |
| 네트워크 | **없음.** iCloud 동기화 외에 어떤 아웃바운드 요청도 하지 않는다 |
| 로그 | 릴리즈 빌드에서 금액·종목명 로깅 금지. 크래시 리포터에도 미포함 |
| 백업 | CSV · JSON 전체 백업은 공유 시트로만 전달. 자동 업로드 없음 |
| 가족 공유 | `CKShare` — 관리자가 초대, 참가자는 구성원 단위 편집 권한(`Member.editorIDs`) |

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
| Persistence | ~~인메모리 `ModelContainer`~~ — 원격 세션은 컴파일을 못 하므로 **CI 의 3중 대조**(모델 · `@NSManaged` · CloudKit 스키마)가 심판 | 칸 하나 빠짐 방지 |
| Services | 프로토콜 목(mock) · 알림 등록은 가짜 스케줄러로 | 시간 관련은 `Clock` 주입 |
| Features | **CI 시뮬레이터 스크린샷** 30여 장(라이트 · 다크 · 큰 글씨 · 보기 전용 · iPad)을 브랜치로 되돌려 사람이 본다 | 레이아웃 회귀 방지 |
| E2E | 온보딩 → 입력 → 현황판 확인 1개 시나리오 | 최소한만 |

~~CI는 `Core` 패키지 테스트만 먼저 돌립니다. 시뮬레이터 빌드는 PR 머지 전 1회.~~

*(현재: 맥이 없어서 **CI 가 컴파일러다.** 코드를 푸시할 때마다 `ios.yml` 이 macOS 러너에서 Core 테스트 · 앱 빌드 · 스키마 대조 · 스크린샷을 돌리고, 스크린샷을 `screenshots/` 로 되돌려 커밋한다. 못 찍은 컷은 `screenshots/failed/`. 문서만 고친 푸시는 돌리지 않는다. TestFlight 는 `testflight.yml` 을 사람이 실행 — [06](06-testflight.md).)*
