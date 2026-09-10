# 우리 가족 노후자금 준비 — 개발 안내

가족 자산을 **매주 토요일 직접 입력**하고, 그 숫자가 계획선 위인지 아래인지를
은퇴 시점까지의 궤적으로 확인하는 iOS 앱.

설계가 코드보다 앞서 있습니다. 무엇을 만들지 헷갈리면 `docs/`를 먼저 읽으세요.
특히 `docs/adr/`의 결정은 되돌리기 비싼 것들이라 임의로 뒤집지 마세요.

## ⚠️ 이 저장소를 원격(Linux) 세션에서 다룰 때

**Claude Code 웹/원격 세션은 Linux 컨테이너라 iOS 앱을 빌드·실행·스크린샷할 수 없습니다.**
Xcode도 Swift 툴체인도 없고, 네트워크 정책상 `download.swift.org`도 막혀 있습니다.
SwiftUI·Core Data는 애초에 Apple 플랫폼 전용이라 Linux Swift로도 컴파일되지 않습니다.

따라서 원격 세션에서는:
- ✅ Swift 소스 작성·수정, 설계 문서 갱신, 계산 로직 검증(파이썬 등으로 기댓값 대조)
- ❌ `swift build` / `swift test` / `xcodebuild` / 시뮬레이터 / 앱 스크린샷

**컴파일할 수 없는 코드에 지어낸 기댓값을 넣지 마세요.** 수치 기댓값은 반드시
독립적으로 계산해서 확인한 뒤 적습니다(실제로 이 규칙 덕에 복리 테스트 오류를 잡았습니다).

**그래서 CI가 컴파일러 역할을 합니다.** `.github/workflows/ios.yml`이 푸시할 때마다
GitHub Actions의 macOS 러너에서 빌드·테스트하고, 시뮬레이터 스크린샷을 `screenshots/`에
되돌려 커밋합니다. 원격 세션에서는 **푸시한 뒤 CI 결과와 그 스크린샷으로 확인**하세요.

- 실패 로그: GitHub MCP 도구 `actions_list` / `get_job_logs`
- 화면 확인: `git pull` 후 `screenshots/*.png` 를 Read
- 문서·마크다운만 고친 푸시는 CI를 돌리지 않습니다 (`paths-ignore`)

macOS에서 작업하면 아래 명령이 전부 동작합니다.

## 처음 시작 (macOS)

```bash
git clone https://github.com/helpnara/Asset-management.git
cd Asset-management
git checkout claude/iphone-asset-management-design-7aafjc

brew install xcodegen        # 최초 1회
xcodegen generate            # SlowRich.xcodeproj 생성
cd Packages/Core && swift test && cd -   # 계산 로직 테스트 (수 초)
open SlowRich.xcodeproj       # ⌘R 로 실행
```

`claude` 를 이 디렉터리에서 실행하면 `CLAUDE.md` 를 읽고 이어서 작업합니다.

## 빌드 · 테스트 (macOS)

```bash
# 1) Xcode 프로젝트 생성 — project.yml이 원본, .xcodeproj는 생성물이라 커밋하지 않는다
brew install xcodegen
xcodegen generate

# 2) 계산 로직만 빠르게 (시뮬레이터 불필요, 수 초)
cd Packages/Core && swift test

# 3) 앱 빌드
xcodebuild -scheme SlowRich -destination 'platform=iOS Simulator,name=iPhone 16' build

# 4) 시뮬레이터에서 실행하고 스크린샷
xcrun simctl boot 'iPhone 16'
xcrun simctl install booted <경로>/SlowRich.app
xcrun simctl launch booted com.helpnara.slowrich
xcrun simctl io booted screenshot shot.png
```

## 구조

```
docs/            설계 문서. 코드보다 이게 먼저다
Tools/           일회성 생성 스크립트 (앱 아이콘 등). 결과물은 커밋하되 만드는 법도 남긴다
App/             앱 타깃 (SwiftUI). macOS에서만 빌드된다
Packages/Core/   순수 Swift. Foundation 외 의존 없음 → 어디서나 테스트된다 (ADR-0002)
project.yml      XcodeGen 명세. .xcodeproj는 여기서 생성한다
```

## 규칙

- **금액에 `Double`을 쓰지 않는다.** `Money`(통화 최소 단위 정수), `Quantity`(스케일 10⁸),
  `Ratio`(basis point)만 쓴다. 이유는 [ADR-0003](docs/adr/0003-money-representation.md).
  예외는 몬테카를로 하나뿐이고, 거기서도 정확한 숫자는 `Projection.run`(결정론)에서 가져온다.
- **반올림은 `Decimals` 한 곳에서만** 일어난다. 기본은 은행가 반올림.
- **숫자는 전부 고정폭 tabular, 우측 정렬.** `Font.figure(_:weight:)` 사용.
- **관리 객체(`NSManagedObject`)를 `async` 경계 너머로 넘기지 않는다.** 참조 타입이라
  `Sendable` 이 아니어서 Swift 6 가 "sending ... risks causing data races" 로 막는다.
  화면 쪽에서 필요한 값(Int·Date·Money 등)만 뽑아 `Sendable` 구조체로 건넨다.
  `@preconcurrency` 로 검사를 끄지 않는다 — 세 번 밟고 세 번 다 값으로 풀었다.
- **`Core`는 SwiftUI·Core Data를 import하지 않는다.** 이 경계가 깨지면 테스트가 느려지고
  원격 세션에서 검증할 수 있는 범위가 사라진다.
- **외부 네트워크 요청을 추가하지 않는다.** 시세·환율을 가져오지 않는 것은 의도된 설계다
  ([ADR-0005](docs/adr/0005-manual-entry.md)).
- **모든 금액은 원화다.** 통화별 입력과 환율 환산은 만들었다가 걷어냈다 — 사용자가
  해외 종목도 원화로 환산해서 적기 때문이다. `Money` 는 통화를 들고 다니지만
  이 앱은 `.krw` 하나만 쓴다.
- **실제 금액·기관명·계좌 정보를 커밋하지 않는다.** 테스트 픽스처와 문서의 숫자는 예시다.
- **저장 계층은 Core Data다** (4차에서 SwiftData에서 옮겼다 — [09-family-sharing](docs/09-family-sharing.md)).
  SwiftData는 `CKShare` 공유를 못 해서, 가족 공유를 하려면 옮길 수밖에 없었다.
  화면에서 쓰는 것은 `@Fetched`(속은 `@FetchRequest`, 겉은 `[T]`)와
  `@ObservedObject`다. `@Query`·`@Model`·`@Bindable`은 이제 없다.
- **모델의 원본은 `App/SlowRich.xcdatamodeld` 다.** `@NSManaged` 선언
  (`App/Persistence/Generated/`)과 CloudKit 스키마(`Tools/cloudkit/slowrich.ckdb`)가
  거기서 파생된다. **칸을 더하면 셋을 함께 고친다** — CI가 서로 대조해서
  하나만 고치면 막는다. 빠진 `@NSManaged` 선언은 컴파일을 통과하고
  화면에서 값 하나가 조용히 비는 것으로만 드러나므로, 이 대조가 유일한 심판이다.
- 스키마를 건드릴 때는 CloudKit 제약을 지킨다
  (유니크 제약 없음, 모든 속성 기본값, 모든 관계 옵셔널 — [ADR-0001](docs/adr/0001-swiftdata-cloudkit.md)).

## 아이폰에 올리기

사용자는 맥이 없다. `.github/workflows/testflight.yml` 을 수동 실행하면 macOS 러너가
빌드·서명·업로드까지 하고 TestFlight로 설치한다. 최초 1회 준비 절차는
[docs/06-testflight.md](docs/06-testflight.md) 에 있고, 저장소 시크릿 4개가 필요하다.

**iCloud 컨테이너(`iCloud.com.helpnara.slowrich`)를 먼저 만들어야 한다.**
앱이 iCloud 자격을 요구하도록 설정돼 있어서, 없으면 아카이브가 서명에서 막힌다.
**팀에 기기가 하나는 등록돼 있어야 한다** — 자동 서명이 아카이브를 개발용
프로파일로 굽는데, 개발용은 기기 없이 발급되지 않는다.

**CloudKit 스키마는 저절로 생기지 않는다.** 저장 계층은 Development 환경에서만
레코드 타입을 자동 생성하고, TestFlight 빌드는 Production 을 쓴다 —
엔타이틀먼트로 이걸 바꿀 수 없다. 맥으로 개발용 빌드를 한 번도 안 돌렸다면
Development 가 비어 있어 배포할 것이 없다. 앱은 로컬로 정상 동작하지만
동기화만 조용히 안 붙는다.

**맥 없이 올렸다 (2026-09-07).** 애플의 `CKTool JS` 는 Node 에서 돌아서
리눅스 러너로 충분하다. `Actions → CloudKit 스키마` 워크플로가 스키마 파일을
Development 에 밀어 넣고, Production 승격만 웹 콘솔의 Deploy 버튼을 사람이
누른다. 앱에서 `더보기 → 동기화 → 마지막 내보내기: 성공` 으로 확인했다.

**시스템 레코드 타입도 같은 규칙이다 (2026-09-09).** `CKShare` 는
`cloudkit.share` 라는 시스템 타입으로 저장되는데, CloudKit 은 그것도
**Development 에서 앱이 처음 공유를 시도할 때** 자동으로 만든다. 맥 없이
TestFlight 만 쓰는 이 저장소에서는 그 일이 영영 안 일어나서, 공유가
`Cannot create new type cloudkit.share in production schema` 로 막혔다.
그래서 `generate-ckdb.py` 가 `cloudkit.share` 를 함께 뽑는다. 이름에 점이
있어 **따옴표로 감싸야** 서버 파서가 받는다.

**모델을 고치면 스키마를 다시 올려야 한다.** 안 그러면 새 필드가 iCloud 에
안 올라가는데 화면에서는 티가 안 난다. CI 가 `.xcdatamodeld` 와
`Tools/cloudkit/slowrich.ckdb` 를 대조해 어긋나면 빌드를 막는다. 절차는
[docs/06-testflight.md](docs/06-testflight.md) 에 있다.
App Store 출시 절차는 [docs/07-app-store.md](docs/07-app-store.md) 에 있다.

## 기억해 둘 것

- **1.0 은 우리 가족, 2.0 은 모두에게.** 1.0 은 가족 넷이 TestFlight 로 쓰고,
  안정화되면 2.0 으로 App Store 에 무료 공개하는 것이 사용자의 결정이다.
  **세션을 시작할 때 [로드맵의 "1.0 안정화 판단 기준"](docs/05-roadmap.md#10-안정화-판단-기준--이걸-다-채우면-claude-가-20-착수를-상기시킨다)
  표를 보고, 채워진 항목이 늘었으면 표에 날짜를 적고, 여덟 개가 다 차면
  사용자에게 2.0 착수를 상기시킨다.** Claude 는 세션을 넘어 기억하지 못하므로
  그 표가 기억이다.
- **기능 동결 (2026-09-10 빌드 60 부터).** 쓰면서 나오는 이슈는
  [로드맵의 "동결 중 누적 이슈"](docs/05-roadmap.md#동결-중-누적-이슈-2026-09-10-빌드-60-부터)
  표에 쌓는다. **빌드(CI·TestFlight)는 사용자가 "착수하자" 라고 할 때만** 돌린다 —
  하루에 빌드 열두 개를 찍은 뒤 정한 규칙이다. 표에 5~10개가 모이면 착수 여부를
  묻는다. 자료가 사라지거나 어긋나는 문제만 예외로 바로 고친다.
- **iPad 확장**: iPhone 버전이 어느 정도 완성되면 iPad로 넓히는 것이 사용자의 계획이다.
  착수 조건과 준비 사항은 [로드맵 M7](docs/05-roadmap.md#m7--ipad-확장-iphone-버전이-안정된-뒤).
  M1~M5 화면을 만들 때 고정 폭 레이아웃에 못 박지 않는다.
- **앱 이름은 `느린 부자의 기록`** 이다. 빌드용 식별자는 `SlowRich`,
  번들 ID는 `com.helpnara.slowrich`.
  화면 상단의 `우리 가족 노후자금 준비` 는 앱 이름이 아니라 **계획 제목**이며
  사용자가 바꿀 수 있는 값이다 (`Plan.title`). 둘을 섞지 않는다.
