# 새 앱 시작 키트 — 환경 · 계정 · 설정 (2026-10-17)

`느린 부자` 를 **맥 없이** 만들어 App Store 까지 낸 환경을, 다음 앱(`느린 여백` · `느린 나이테` …)에서
그대로 다시 세우기 위한 **설정 목록**이다.

| 문서 | 무엇 |
|---|---|
| **이 문서 (20)** | 무엇을 준비하고, 무엇을 복사하고, 무엇을 바꾸나 — **설정 · 값 · 순서** |
| [12 배운 것](12-lessons-learned.md) | 왜 그렇게 하나 — 시행착오에서 나온 **규칙** · 시작 체크리스트(§9) |
| [06 TestFlight](06-testflight.md) · [07 App Store](07-app-store.md) · [15 제출 시트](15-app-store-submission-sheet.md) | 각 단계의 자세한 화면 순서 |

**새 저장소를 만들면 이 문서와 12 를 먼저 그 저장소 `docs/` 에 복사한다.** Claude 는 세션을 넘어 기억하지
못하므로, 새 저장소의 첫 세션은 이 두 문서가 기억이다.

> 이 문서에는 **비밀 값을 적지 않는다** — 팀 ID · 키 ID · 토큰 · `.p8` 은 이름과 어디서 얻는지만 적는다.
> 저장소가 public 이라 커밋하면 이력에 남는다.

---

## 0. 한눈에 — 개발 방식

```
사용자 (아이폰만, 맥 없음)
   │  말로 요청 · 화면 사진 · "착수하자" · 체크리스트 "1~7 확인 완료"
   ▼
Claude Code 원격 세션 (claude.ai/code — 리눅스 컨테이너)
   │  Swift 소스 · 설계 문서 · 파이썬 기댓값 대조 · 커밋 · 푸시
   ▼
GitHub (public 저장소)
   │  push → Actions macOS 러너 = 컴파일러 · 테스트 · 시뮬레이터 스크린샷 → screenshots/ 로 되돌려 커밋
   │  수동 실행 → TestFlight 업로드 · CloudKit 스키마 · 스토어 스크린샷 · 미리 보기 녹화
   ▼
App Store Connect → TestFlight(부모) · App Store(아이들 · 모두)
```

- **원격 세션은 iOS 앱을 빌드 · 실행 · 스크린샷할 수 없다.** Xcode · Swift 툴체인 없음, `download.swift.org`
  도 막혀 있다. SwiftUI · Core Data 는 리눅스 Swift 로도 안 된다 → **CI 가 컴파일러다** (12 §2).
- **할 수 있는 것.** 소스 작성, 문서, 파이썬으로 계산 기댓값 대조, Node(Playwright · ffmpeg)로 영상 · 이미지 만들기,
  GitHub MCP 로 Actions 실행 · 로그 읽기.

---

## 1. 계정 · 구독 — 한 번 만들면 앱마다 다시 쓴다

| 무엇 | 어디 | 비용 · 만료 | 메모 |
|---|---|---|---|
| Apple Developer Program | developer.apple.com/account | **연 $99**, 매년 갱신 (지금 팀은 2027-09-05) | 끊기면 App Store 에서 내려간다. 2단계 인증 필수. 승인 24~48시간 |
| App Store Connect | appstoreconnect.apple.com | 위에 포함 | 앱 레코드 · TestFlight · 심사 · 분석 |
| CloudKit Console | icloud.developer.apple.com | 위에 포함 | 스키마 Production 배포 버튼 · 관리 토큰 |
| GitHub | github.com | **public 저장소면 Actions 무제한 무료** | private 이면 macOS 러너가 분 한도에 걸려 한 달 빌드 대여섯 번이 끝이다 (12 · 05 로드맵) |
| Claude (claude.ai/code) | claude.ai | 구독 | 원격 세션 · 예약 작업(알림) · GitHub 연결 |
| 지원 메일 | 앱 안 `문의 · 피드백 메일` · 처리방침 | — | 앱마다 같은 주소를 써도 된다 |

### 앱마다 새로 만드는 것 vs 다시 쓰는 것

| 다시 쓴다 (팀 단위) | 앱마다 새로 |
|---|---|
| 팀 ID (`APPLE_TEAM_ID`) | 번들 ID · App ID (`com.helpnara.<앱>`) |
| App Store Connect API 키 (`.p8` · 키 ID · 발급자 ID) — 만료 없음 | iCloud 컨테이너 (`iCloud.com.helpnara.<앱>`) |
| CloudKit 관리 토큰 — **만료 있음**. 새 컨테이너에서 처음 `read` 로 닿는지 확인 | App Store Connect 앱 레코드 · 이름(App Store 전체에서 유일) |
| 등록된 기기(UDID) | GitHub 저장소 · **저장소 시크릿**(저장소마다 다시 넣는다) |
| TestFlight 내부 테스터(가족) — 팀 사용자로 이미 초대돼 있다 | 내부 테스팅 그룹에 새 앱 추가 |
| 배포 인증서 — 내보내기가 자동으로 쓴다 | 개인정보 처리방침 페이지 · 지원 URL |

---

## 2. 새 앱 세우기 — 순서

### 2-1. 이름 · 식별자 (코드 전에, 한 표로)

| 칸 | 느린 부자 | 새 앱 |
|---|---|---|
| 앱 이름 (홈 화면 · 스토어) | `느린 부자` | `느린 ○○` — **앱마다 다른 말은 한 단어만**, `~의 기록` 같은 꼬리 금지 |
| 빌드 식별자 · 스킴 | `SlowRich` | 영문 한 단어 |
| 번들 ID | `com.helpnara.slowrich` | **한 번 정하면 못 바꾼다** — 바꾸면 iCloud · TestFlight 가 남남 |
| iCloud 컨테이너 | `iCloud.com.helpnara.slowrich` | `iCloud.` + 번들 ID |
| 화면 제목 | `우리 가족 노후자금 준비` (사용자 값, `Plan.title`) | 앱 이름과 섞지 않는다 |
| 상표 검색 | KIPRIS 2026-09-24 | 이름 정할 때 한 번 |

### 2-2. Apple 쪽 (승인 뒤, 약 40분 — 자세한 화면은 [06](06-testflight.md) 2~9단계)

1. **iCloud 컨테이너를 먼저 만든다** (Identifiers → iCloud Containers). 없으면 아카이브가 서명에서 막힌다.
2. **App ID** 를 만들고 iCloud(CloudKit) · Push Notifications 를 켠 뒤, **등록한 뒤에** 컨테이너를 연결한다.
3. **App Store Connect 에 앱 등록** — 이름 · 기본 언어 한국어 · 번들 ID · SKU.
4. **기기가 팀에 하나는 등록돼 있는지** 본다 — 자동 서명이 개발용 프로파일을 굽는데 기기 없이는 안 나온다.
5. TestFlight → **내부 테스팅** 그룹 → 가족 추가 · `모든 빌드 자동 배포`. 외부 그룹은 빌드마다 베타 심사가 붙는다.
6. **아이(어린) 계정은 TestFlight 에 못 들어온다** — 가족 전원 시험이 필요하면 App Store 출시를 계획에 처음부터 넣는다.

### 2-3. GitHub 저장소

1. **public** 으로 만든다. 실제 금액 · 기관명 · 계좌 정보는 처음부터 커밋하지 않는다 (사용자 화면 사진의 숫자 포함).
2. **저장소 시크릿 5개** (`Settings → Secrets and variables → Actions`) — 이름 철자 그대로:

   | 시크릿 | 값 | 쓰는 워크플로 |
   |---|---|---|
   | `APP_STORE_CONNECT_KEY_P8` | `.p8` 파일 내용 전체 — **줄바꿈 그대로** | testflight · appstore 업로드 |
   | `APP_STORE_CONNECT_KEY_ID` | API 키 ID | 〃 |
   | `APP_STORE_CONNECT_ISSUER_ID` | 발급자 ID | 〃 |
   | `APPLE_TEAM_ID` | 팀 ID | testflight · cloudkit-schema |
   | `CKTOOL_MGMT_TOKEN` | CloudKit 관리 토큰 | cloudkit-schema 만 |

3. **Pages** — `Settings → Pages → Source: GitHub Actions`. 저장소를 private ↔ public 으로 바꾸면 이 설정이 지워진다.
4. Claude 쪽 — claude.ai 에서 GitHub 연결, 새 저장소를 세션 소스로 고른다. **기본 브랜치에 바로 커밋하지 않고**
   세션이 정한 `claude/…` 브랜치에서 일한다 (지금 저장소는 `claude/iphone-asset-management-design-7aafjc`).

### 2-4. 이 저장소에서 복사할 파일

| 복사 | 바꿀 곳 | 왜 있나 |
|---|---|---|
| `CLAUDE.md` | 앱 설명 · 규칙 중 앱 고유 것 · "기억해 둘 것" 을 비우고 시작 | 세션마다 읽는 기억. **원격 세션 제약 · 빌드 규율 · 체크리스트 규칙 · 비밀 금지**는 그대로 |
| `project.yml` | `name` · 번들 ID · `CFBundleDisplayName` · 스킴 이름 · `MARKETING_VERSION "1.0"` | XcodeGen 원본. `.xcodeproj` 는 커밋하지 않는다 |
| `App/<앱>.entitlements` · `.Release.entitlements` | 컨테이너 ID | `aps-environment` 가 Debug=development · Release=production 이라 둘로 나눈다 |
| `App/PrivacyInfo.xcprivacy` | 쓰는 API 에 맞게 | 개인정보 명세. `Tools/privacy/check-privacy-manifest.py` 가 키를 검사 |
| `Packages/Core/` 뼈대 | 계산 로직 | Foundation 만 — 어디서나 `swift test` (ADR-0002) |
| `.github/workflows/ios.yml` | 스킴 · 번들 ID · 스크린샷 목록 · 브랜치 | push 마다 빌드 · 테스트 · 스크린샷 |
| `.github/workflows/testflight.yml` | 스킴 · 번들 ID | 수동. 빌드 · 서명 · 업로드 |
| `.github/workflows/cloudkit-schema.yml` | `container` 기본값 | 수동. `read` · `validate` · `apply`(Development) |
| `.github/workflows/pages.yml` | `branches` | 처리방침 한 장만 배포 |
| `.github/workflows/appstore-screenshots.yml` · `preview.yml` | 화면 목록 · 대본 | 출시 전에 |
| `.github/workflows/probe.yml` | — | macOS 러너에서 셸 한 줄 돌려 보기 (러너 조사용) |
| `Tools/coredata/*` · `Tools/cloudkit/*` | 모델 경로 · 이름 | 모델 · `@NSManaged` · `.ckdb` 3중 대조, 런타임 검사, 마이그레이션 시험 |
| `Tools/site/build.py` · `docs/privacy-policy.md` | 앱 이름 · 수집 항목 | 지원 · 처리방침 URL |
| `Tools/store/compose.py` · `Tools/preview/*` · `Tools/promo/*` | 문구 · 장면 | 스토어 스크린샷 캡션 · 미리 보기 편집 · 홍보 영상 |
| `Tools/make-icon.py` + 서체 파일 | 아이콘 원본 | 결과물과 **만드는 법을 함께** 커밋 |
| `docs/` 틀 — `08-feedback` (번호 · 상태 이모지) · `05-roadmap` (출시 일정 블록 · 동결 표) · `adr/` · `14-daily-test-routine` · `15` 제출 시트 | 내용 비우고 틀만 | 세션을 넘는 기억 |

`slowrich` · `SlowRich` · 브랜치 이름이 박힌 곳은 `grep -rl "slowrich\|SlowRich\|7aafjc" .github Tools project.yml` 로 찾는다
(2026-10-17 기준 워크플로 6개 · `Tools/coredata` 5개 · `Tools/cloudkit` 2개 · `Tools/promo` 3개 · `project.yml`).

### 2-5. `project.yml` 에서 놓치기 쉬운 칸

| 칸 | 값 | 없으면 |
|---|---|---|
| `CFBundleShortVersionString` · `CFBundleVersion` | `$(MARKETING_VERSION)` · `$(CURRENT_PROJECT_VERSION)` | XcodeGen 이 `1.0` · `1` 을 박아 **빌드 번호가 실행 번호와 어긋난다** (빌드 1~24 사건) |
| `CFBundleDevelopmentRegion` · `CFBundleLocalizations` | `ko` · `[ko]` | 기기 언어가 영어면 날짜 · 시스템 UI 가 영어 |
| `ITSAppUsesNonExemptEncryption` | `false` | 업로드마다 수출 규정 질문 |
| `UIBackgroundModes` | `remote-notification` | CloudKit 변경 무음 푸시를 못 받음 |
| `CKSharingSupported` | `true` | 공유 초대 링크가 앱으로 안 온다 |
| `NSFaceIDUsageDescription` | 문구 | Face ID 가 오류 -6 으로 그냥 실패 |
| `NSPhotoLibraryAddUsageDescription` | 문구 | 공유 시트 `이미지 저장` 에서 앱이 죽는다 |
| `UISupportedInterfaceOrientations~ipad` | 네 방향 | iPad 멀티태스킹 불가 · App Store 검증 실패 |
| `TARGETED_DEVICE_FAMILY` | `"1,2"` | iPad 정식 설치 안 됨 |
| 테스트 스킴 `commandLineArguments` | `-localStoreOnly` · `-skipOnboarding` | CI 에 iCloud 자격이 없어 테스트가 CloudKit 에서 멈춘다 |
| UI 테스트 스킴 `debugEnabled` | `false` | CI 에 LLDB 가 없어 앱이 디버거를 기다리다 시간 초과 |
| `SWIFT_VERSION` | `"6.0"` | — 처음부터 엄격한 동시성으로 |

### 2-6. 앱 실행 인자 — 스크린샷 · 시험용 문

CI 가 시뮬레이터에서 화면마다 앱을 새로 띄워 찍는다. 그 문을 **첫 화면부터** 만들어 둔다.

| 인자 | 하는 일 |
|---|---|
| `-localStoreOnly` | iCloud 없이 기기 저장소로만 연다 (CI · 테스트) |
| `-skipOnboarding` | 환영 화면 건너뛰기 |
| `-seedSampleData` · `-seedLargeSample` | 체험 자료(가상의 가족) · 5년치 자료(화면 시간 재기) |
| `-startTab` · `-start<화면>` · `-scrollTo` | 그 화면을 열고 그 자리로 — 스크린샷 한 장 = 인자 한 벌 |
| `-simulateStoreFailure` | 저장소를 못 여는 화면 |

**스크린샷 심판 넷**을 처음부터: 빈 화면 재시도 · 크기 가드(홈 화면 찍힘) · **큰 글씨 한 장** · iPad 한 장 (12 §2).

---

## 3. 원격 세션에서 일하는 법

| 하고 싶은 것 | 방법 |
|---|---|
| CI 결과 보기 | GitHub MCP `actions_list`(`list_workflow_runs`) · `get_job_logs`. public 저장소는 `curl https://api.github.com/repos/<owner>/<repo>/actions/runs/<id>` 도 된다 |
| CI 끝날 때까지 기다리기 | CI 가 스크린샷을 커밋하면 브랜치 끝이 바뀐다 → 배경에서 `git ls-remote` 로 바뀔 때까지 30초 간격 확인. `sleep` 으로 앞을 막지 않는다 |
| 화면 확인 | `git pull` 뒤 `screenshots/*.png` 를 읽는다 |
| TestFlight 올리기 | MCP `actions_run_trigger` → `run_workflow`, `testflight.yml`, `ref` = 작업 브랜치, `inputs.notes` = 변경 사항 |
| 문서만 고칠 때 | 커밋 메시지에 `[skip ci]`. `ios.yml` 의 `paths-ignore` 도 docs · md 를 건너뛴다 |
| 되돌려 커밋하는 워크플로가 도는 중 | **푸시를 모은다** — 끝에 `fetch first` 로 거절된다. 실패하면 re-run 이 아니라 새로 dispatch |
| 날짜에 맞춰 상기 | Claude 예약 작업(알림) — 세션에 `send_later` · 정기 작업. 예: 11-02 확인, 12-01 새 빌드, 12-21 에디터 추천 |
| 영상 · 이미지 만들기 | 컨테이너의 Node + Playwright(크로미움 미리 설치) + ffmpeg. 가변 프레임 녹화는 처음부터 풀어 `fps=30,trim=` 으로 자른다 |

**빌드 규율** — 이슈는 08 에 번호로 쌓고, 사용자가 **"착수하자"** 할 때만 CI · TestFlight 를 돌린다. 빌드마다
코드로 확인한 체크리스트(화면에 보이는 이름 그대로의 경로 · 보이는 조건)를 함께 준다. 자료가 사라지거나 어긋나는 것만 예외.

---

## 4. CI 파이프라인 (`ios.yml`) — 이 순서로 세운다

1. **Core 테스트** (`swift test`) + 모델 · `.ckdb` · `@NSManaged` 3중 대조 + 개인정보 명세 키 검사 — 수 초 ~ 수 분
2. **최신 Xcode 선택** — App Store Connect 는 iOS 26 SDK(Xcode 26+) 빌드만 받는다. 러너 `runs-on: macos-26`
3. XcodeGen 설치 · 생성 → 시뮬레이터 고르기(아이폰 · 아이패드)
4. **빌드** → **앱 테스트**(인메모리 저장소) → `momc` 모델 컴파일 → **런타임 CloudKit 규칙 검사** → **마이그레이션 시험**
   (`Tools/coredata/migration-baselines.txt` 의 출시 판 커밋마다 그 판 저장소를 지금 모델로 연다 — 모델 폴더를 **통째로** 꺼낸다)
5. **화면별 스크린샷** → 아티팩트 업로드 → `screenshots/` 커밋(`[skip ci]`) — **아티팩트를 커밋보다 앞에**
6. 설정: `concurrency.cancel-in-progress: true` · `permissions: contents: write` · `paths-ignore` (docs · md · screenshots)

**출시한 판의 커밋은 `migration-baselines.txt` 맨 위에 더한다** — 다음 판이 그 사용자 저장소를 열 수 있는지 CI 가 본다.

---

## 5. 저장 · 동기화 (가족 공유 앱이면)

- **Core Data + `NSPersistentCloudKitContainer` + `CKShare`.** SwiftData 는 공유를 못 한다 (12 §1 — 가장 비싼 실수).
- **CloudKit 제약** — 유니크 제약 없음 · 모든 속성 기본값 · 모든 관계 옵셔널 (ADR-0001).
- **스키마는 저절로 Production 에 안 생긴다.** TestFlight 는 Production 을 쓴다:
  `Actions → CloudKit 스키마 → apply`(Development) → **CloudKit Console 에서 사람이 Deploy** → 앱 `더보기 → 동기화 → 마지막 내보내기: 성공`.
  `cloudkit.share` 시스템 타입도 `.ckdb` 에 넣는다(이름에 점 → **따옴표**).
- **모델을 고치면** 새 판(`<앱> 2.xcdatamodel`)을 쌓고 `.xccurrentversion` 을 돌린다. 옛 판은 지우지 않는다.

---

## 6. 스토어 자산 규격 (2026-10 실제로 받아 준 크기)

| 칸 | 크기 | 만드는 곳 |
|---|---|---|
| 아이폰 스크린샷 6.5" | 1284×2778 | `appstore-screenshots.yml` → `Tools/store/compose.py` → `screenshots/appstore/store/iphone-6.5/` |
| 아이폰 스크린샷 15.5 · 15.9cm (6.1 · 6.3") | **1206×2622** | 같은 스크립트 → `iphone-6.3/` |
| 아이패드 13" (33.0cm) | 2064×2752 | 같은 워크플로 → `ipad/` |
| 아이폰 미리 보기 영상 | 886×1920, 30fps, 30초 이하, 무음 트랙 | `preview.yml` 녹화 → `Tools/preview/edit.mjs` |
| 아이패드 미리 보기 영상 | 1200×1600 | `edit.mjs --device ipad` |
| 포스터 프레임 | **스크린샷 칸 크기**(1206×2622 · 2064×2752) | `Tools/preview/poster.mjs` |
| 앱 아이콘 | 1024×1024, 투명 없음 | `Tools/make-icon.py` |
| 홍보 영상(쇼츠 · 릴스) | 1080×1920 | `Tools/promo/render.mjs` |

- 스크린샷 · 영상은 **체험 자료로만** — 실제 금액이 찍히지 않게.
- 앱 이름을 바꾸면 스크린샷을 다시 찍는다(2.3 반려 위험). 미리 보기는 **새 버전을 낼 때만** 바꿀 수 있다.
- 처리방침 URL 은 **첫 빌드 전에** Pages 로 — `/docs` 전체가 아니라 방침 한 장만.

---

## 7. 버전 · 출시 규칙

| 규칙 | 내용 |
|---|---|
| 빌드 번호 | **GitHub 실행 번호** = TestFlight 빌드 번호. 손대지 않는다 |
| 버전 번호 | `project.yml` `MARKETING_VERSION`. **App Store 버전 페이지 번호 = 빌드의 버전**이어야 빌드를 고를 수 있다 |
| 같은 번호 두 번 | 공개된 판의 번호로는 새 빌드를 못 올린다 — 공개 뒤 고치면 번호를 올린다. 제출 전 페이지는 번호를 바꿀 수 있다 (1.0.7 → 1.0.8, 10-17) |
| TestFlight 만료 | 업로드 + **90일**. 가족이 TestFlight 판을 쓰면 그 전에 새 빌드 |
| 출시 방식 | **수동 출시** — 통과해도 `이 버전 출시` 를 누를 때까지 공개되지 않는다 |
| 제출 | [15 제출 시트](15-app-store-submission-sheet.md) 꼴로 화면 순서대로 ☐ |
| 업데이트 안내 | 가구 뿌리 레코드에 `latestBuild` — **첫 스키마에** 넣는다. App Store 를 연 뒤에는 TestFlight 판이 번호를 안 적는다 |

---

## 8. 만료 달력 — 새 앱을 만들면 같이 적는다

| 무엇 | 주기 | 만료되면 |
|---|---|---|
| Apple Developer Program | 1년 | 앱이 App Store 에서 내려간다 |
| CloudKit 관리 토큰 | 만들 때 고른 기간 (가장 길게) | `CloudKit 스키마` 워크플로만 막힌다. 앱 동기화는 영향 없음 |
| TestFlight 빌드 | 90일 | TestFlight 판 앱이 안 열린다 |
| 개발 인증서 | 러너가 매번 새로 발급 → **최대 개수에 걸린다** | 개발자 사이트에서 오래된 `Created by Xcode` 폐기 (배포용은 두기) |
| App Store Connect API 키 | 없음 | 폐기하면 TestFlight · 업로드가 막힌다 |

로드맵 "출시 일정" 블록에 이 표의 날짜를 적고, 다가오면 예약 작업으로 상기한다.

---

## 9. 첫날 Claude 에게 줄 말 (예시)

> 새 앱 `느린 ○○` 를 시작한다. `docs/20-new-app-kit.md` 와 `docs/12-lessons-learned.md` 를 먼저 읽고,
> 12 §9 첫날 체크리스트와 20 §2 순서대로 저장소 뼈대(CLAUDE.md · project.yml · Core 패키지 · ios.yml)를 세워 줘.
> 번들 ID 는 `com.helpnara.○○`, 컨테이너는 `iCloud.com.helpnara.○○`. Apple 쪽 준비(20 §2-2)는 내가 할 테니 순서를 체크리스트로 줘.
