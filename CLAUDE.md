# 우리 가족 노후자금 준비 — 개발 안내

가족 자산을 **매주 토요일 직접 입력**하고, 그 숫자가 계획선 위인지 아래인지를
은퇴 시점까지의 궤적으로 확인하는 iOS 앱.

설계가 코드보다 앞서 있습니다. 무엇을 만들지 헷갈리면 `docs/`를 먼저 읽으세요.
특히 `docs/adr/`의 결정은 되돌리기 비싼 것들이라 임의로 뒤집지 마세요.

## ⚠️ 이 저장소를 원격(Linux) 세션에서 다룰 때

**Claude Code 웹/원격 세션은 Linux 컨테이너라 iOS 앱을 빌드·실행·스크린샷할 수 없습니다.**
Xcode도 Swift 툴체인도 없고, 네트워크 정책상 `download.swift.org`도 막혀 있습니다.
SwiftUI·SwiftData는 애초에 Apple 플랫폼 전용이라 Linux Swift로도 컴파일되지 않습니다.

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
xcodegen generate            # Assetly.xcodeproj 생성
cd Packages/Core && swift test && cd -   # 계산 로직 테스트 (수 초)
open Assetly.xcodeproj       # ⌘R 로 실행
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
xcodebuild -scheme Assetly -destination 'platform=iOS Simulator,name=iPhone 16' build

# 4) 시뮬레이터에서 실행하고 스크린샷
xcrun simctl boot 'iPhone 16'
xcrun simctl install booted <경로>/Assetly.app
xcrun simctl launch booted com.helpnara.assetly
xcrun simctl io booted screenshot shot.png
```

## 구조

```
docs/            설계 문서. 코드보다 이게 먼저다
App/             앱 타깃 (SwiftUI). macOS에서만 빌드된다
Packages/Core/   순수 Swift. Foundation 외 의존 없음 → 어디서나 테스트된다 (ADR-0002)
project.yml      XcodeGen 명세. .xcodeproj는 여기서 생성한다
```

## 규칙

- **금액에 `Double`을 쓰지 않는다.** `Money`(통화 최소 단위 정수), `Quantity`(스케일 10⁸),
  `Ratio`(basis point)만 쓴다. 이유는 [ADR-0003](docs/adr/0003-money-representation.md).
- **반올림은 `Decimals` 한 곳에서만** 일어난다. 기본은 은행가 반올림.
- **숫자는 전부 고정폭 tabular, 우측 정렬.** `Font.figure(_:weight:)` 사용.
- **`Core`는 SwiftUI·SwiftData를 import하지 않는다.** 이 경계가 깨지면 테스트가 느려지고
  원격 세션에서 검증할 수 있는 범위가 사라진다.
- **외부 네트워크 요청을 추가하지 않는다.** 시세·환율을 가져오지 않는 것은 의도된 설계다
  ([ADR-0005](docs/adr/0005-manual-entry.md)).
- **실제 금액·기관명·계좌 정보를 커밋하지 않는다.** 테스트 픽스처와 문서의 숫자는 예시다.
- SwiftData 스키마를 건드릴 때는 CloudKit 제약을 지킨다
  (유니크 제약 없음, 모든 속성 기본값, 모든 관계 옵셔널 — [ADR-0001](docs/adr/0001-swiftdata-cloudkit.md)).

## 기억해 둘 것

- **iPad 확장**: iPhone 버전이 어느 정도 완성되면 iPad로 넓히는 것이 사용자의 계획이다.
  착수 조건과 준비 사항은 [로드맵 M7](docs/05-roadmap.md#m7--ipad-확장-iphone-버전이-안정된-뒤).
  M1~M5 화면을 만들 때 고정 폭 레이아웃에 못 박지 않는다.
- **앱 이름은 아직 미정**이다. `Assetly`는 빌드용 식별자로 쓰는 임시 코드명이고,
  표시 이름은 `노후자금 현황판`이다. 정해지면 `project.yml`과 번들 ID를 함께 바꾼다.
