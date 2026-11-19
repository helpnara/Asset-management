# 24. iOS 27 SDK 전환 검토 (2026-11-19)

> 11-19 빌드 142 업로드 뒤 애플 메일 **ITMS-90725** — *"This app was built with the iOS 26.5 SDK. Starting April 2027,
> iOS and iPadOS apps must be built with the iOS 27 SDK or later, included in Xcode 27 or later."*
> 같은 날 사용자: *"iOS 27 SDK 전환 검토해줘."*

## 무엇이 걸려 있나

| | |
|---|---|
| 마감 | **2027년 4월** 부터 App Store Connect 업로드 전부(TestFlight 포함)가 iOS 27 SDK 빌드여야 한다. 날짜는 아직 안 나왔다 |
| 안 하면 | 4월부터 **TestFlight 도 App Store 도 새 빌드를 못 올린다.** 이미 공개된 판이 내려가지는 않는다. 가족이 쓰는 TestFlight 빌드는 90일이면 만료되므로(빌드 145 → 2027-02-16 무렵) 그 뒤 새 빌드가 막히면 부모 폰 앱이 안 열린다 |
| 최소 지원 OS | 같은 공지에서 **iOS 15 이상 대상**. 이 앱은 **iOS 17.0** 이라 그대로 된다 |

## 지금 러너 (11-19 `macOS 탐침` 2번 실행으로 확인)

| | |
|---|---|
| 이미지 | `macos-26` · `ImageVersion=20261102.0473.1` · macOS 26.7.2 |
| Xcode | **26.0.1 ~ 26.6 만** (기본 26.6 / 17F113). **Xcode 27 은 이 이미지에 없다** |
| iOS SDK | 26.5 (시뮬레이터 런타임 iOS 26.2 · 26.4 · 26.5) |

→ 워크플로의 Xcode 고르는 단계만 고쳐서는 안 된다. **`runs-on` 을 Xcode 27 이 든 이미지로 바꿔야** 한다.
GitHub 은 10-15 에 Xcode 27 러너 이미지를 정식으로 냈다(changelog). 라벨은 2차 자료에 `xcode-27` 로 나오지만 **우리 저장소에서 아직 확인하지 않았다** — 아래 1단계가 그 확인이다.

## 손댈 곳

| 곳 | 지금 | 바꿀 것 |
|---|---|---|
| `.github/workflows/ios.yml` (2 잡) · `testflight.yml` · `appstore-screenshots.yml` · `preview.yml` · `probe.yml` | `runs-on: macos-26` | Xcode 27 이미지 라벨 |
| `testflight.yml` `Xcode 26 이상 선택` | 26 미만이면 멈춤 | **27 미만이면 멈춤** — 4월 뒤 409 를 업로드 전에 잡는다 |
| `ios.yml` 등 `최신 Xcode 선택` | 26 이상이면 그대로 | 27 이상이면 그대로, 설치 목록은 늘 찍기 |
| 시뮬레이터 고르기 | 이름을 박지 않고 가장 새 iPhone 을 고른다 | 그대로 — 새 기기 이름(아이폰 18 등)도 받는다 |
| `docs/06-testflight.md` 문제 해결 표 | `iOS 26 SDK` 줄 | `iOS 27 SDK` 줄 더하기 |
| 앱 코드 · 모델 | — | **미리 고칠 것은 없다.** 컴파일러가 말해 줘야 안다(아래 위험) |

## 위험 — CI 가 처음 돌 때 볼 것

1. **컴파일러가 바뀐다.** Xcode 27 의 Swift 는 새 판이라 동시성 · 폐기 API 경고가 새로 날 수 있다. 언어 모드는 `SWIFT_VERSION 6.0` 그대로 두면 문법은 같다. 오류가 나면 그 자리만 고친다 — `@preconcurrency` 로 끄지 않는다(CLAUDE.md).
2. **화면이 바뀔 수 있다.** 새 SDK 로 구우면 iOS 가 그 판의 기본 모양(단추 · 탭 바 · 시트 · 목록)을 입힌다 — 26 SDK 로 옮길 때 Liquid Glass 가 그렇게 들어왔다. 고칠 것이 있는지 **CI 스크린샷 전부(라이트 · 다크 · 큰 글자 · 아이패드)** 를 1.0.16 것과 견준다([23](23-design-direction.md) 원칙 9).
3. **시뮬레이터 기기 · 해상도가 바뀔 수 있다.** 스크린샷 파일 이름은 그대로지만 크기가 달라질 수 있다. 스토어 스크린샷(`appstore-screenshots.yml`)은 칸 크기를 맞추므로 따로 확인한다.
4. **macOS 27 러너의 도구** — `brew install xcodegen` · Node(CloudKit 스키마는 리눅스라 상관없음) · `simctl` 이 그대로 도는지.
5. 저장 계층(Core Data · CloudKit)과 스키마는 SDK 와 상관없다 — CI 의 모델 대조 · CloudKit 런타임 검사 · 마이그레이션 시험이 그대로 지켜 준다.

## 진행 (11-19 사용자: *"1단계 부터 순차적으로 해보자."*)

**1단계 — 탐침 (끝).** `probe.yml` 에 `runner` 칸을 더해(`145c69c`) 두 라벨로 돌렸다.

| 라벨 | 결과 |
|---|---|
| `macos-27` | **없는 라벨** — 러너를 못 받고 대기, 취소 |
| **`xcode-27`** | **돈다** — macOS 27.0.1 (arm64) · 이미지 `20261104.0337.1` · Xcode **27.0 · 27.1(기본, 27A9275) · 27.2** · **iOS SDK 27.1** · Swift **6.4** · 시뮬레이터 런타임 iOS 27.0 · 27.2 (iPhone 17 · 17e · Air · 18 Pro · 18 Pro Max, iPad Pro 13/11 (M5) · Air (M4) · mini · iPad (A16)) · brew · node · python3 있음 |

기본 Xcode 27.1 이 시뮬레이터 런타임을 갖춘 판이라 워크플로의 "이미 27 이상이면 그대로" 규칙이 그대로 맞다. 시뮬레이터 고르기는 가장 새 런타임의 가장 높은 번호 iPhone → **iPhone 18 Pro** 를 고를 것이다(`iPhone Duo` 는 번호가 없어 빠진다). 스크린샷 크기가 바뀔 수 있다.

**2단계 — 워크플로 전환.** `ios.yml`(2 잡) · `testflight.yml` · `appstore-screenshots.yml` · `preview.yml` · `probe.yml`(기본값)의 `runs-on` 을 `xcode-27` 로, Xcode 고르기의 기준을 26 → **27**, TestFlight 안전장치는 **27 미만이면 멈춤**. 앱 코드는 손대지 않고 CI 한 번으로 컴파일러 · 화면을 본다.

**2단계 결과 (CI 338, 11-19 18:32).** `xcode-27` 러너에서 **Core 테스트 · 앱 컴파일이 고칠 것 없이 통과**(Swift 6.4, `SWIFT_VERSION 6.0` 그대로). 11-19 사용자: *"CI 끝나면 TestFlight까지 진행해줘"* → 이 빌드는 다음 판으로 내므로 `MARKETING_VERSION` **1.0.17** (1.0.16 은 심사 중이라 그대로 둔다).

**CI 339 (두 번).** 컴파일 · Core 테스트 · 앱 테스트 · Core Data 모델 · CloudKit 런타임 검사 · 마이그레이션 시험 **모두 초록**. 앱 테스트는 4분 → 5~13분으로 느려졌다(러너). 컴파일 경고는 **Xcode 26 빌드(142)와 같은 13개** — 27 이 새로 낸 경고는 없다.
스크린샷은 iPhone 은 다 찍혔는데 `14-account-targets` · `15-family-allocation` 만 **흰 화면**(첫 번째는 세 번째 시도에 찍힘, 두 번째는 세 번 다 실패 → CI 빨강). 첫 번째 시도는 iPad 를 띄운 뒤 원인 모를 취소. 두 화면은 CI 만 쓰는 갈고리로 열리는데, `navigationDestination(isPresented:)` 를 **처음부터 `true`** 로 둔 유일한 두 곳이다(다른 화면은 경로로 연다). 첫 화면이 그려지기 전에 밀어 넣은 것이 iOS 27 에서 엇갈린 것으로 보고, 목록이 뜬 뒤 0.4초에 여는 것으로 바꿨다 — 사람이 누르는 순서와 같다. 그래도 비면 화면 자체를 본다.

**4단계 — TestFlight 146 (1.0.17), 11-19 19:51 업로드.** 로그: `Xcode 27.1` · **`iOS SDK: 27.1`** · App Store 검증 통과 · 업로드 성공. (ITMS-90725 메일이 다시 오는지 본다 — 안 와야 한다.)

## 순서 (제안)

| 단계 | 무엇 | 빌드? |
|---|---|---|
| 1 | `probe.yml` 에 러너를 고르는 칸(`runner`, 기본 `macos-26`)을 더하고 `[skip ci]` 로 올린 뒤, **Xcode 27 라벨로 탐침** — Xcode · SDK · 시뮬레이터 런타임 · macOS 판 확인 | 아니다 (1~3분) |
| 2 | 위 표대로 워크플로를 바꿔 **CI 한 번** — 컴파일 · 테스트 · 스크린샷 | CI |
| 3 | 오류 · 화면 차이를 고친다 | CI |
| 4 | **TestFlight 한 번** — 업로드 메일에 ITMS-90725 가 안 오는지, 가족 폰에서 평소처럼 도는지(체크리스트) | TestFlight |
| 5 | 다음 App Store 판(1.0.17)으로 낸다 — 기능이 없으면 "최신 iOS 에 맞춰 다듬었습니다" 정도 | — |

**언제** — 기능 빌드와 섞지 않는다. 1.0.16 이 공개된 뒤, **12월 안**(12-01 착수 여쭙기 알림에 묶여 있다). 늦어도 2027-01 에는 끝낸다 — 3월에 하다 막히면 4월 마감과 2월 TestFlight 만료가 겹친다.
빌드는 사용자가 "착수하자" 라고 할 때만 돌린다. 1단계 탐침은 앱 빌드가 아니라 러너 확인이다.

## 출처

- Apple 공지(9-09)를 옮긴 글: [Xcode 27 requirement — DEV Community](https://dev.to/extensionbooster/xcode-27-requirement-what-breaks-before-april-2027-1kh1) · [Mac Observer](https://macobserver.com/news/xcode-27-rc-six-platforms-mismatched-build-numbers) · [iOS 15 최소 대상](https://www.macobserver.com/news/app-store-ios-13-minimum-target/)
- GitHub: [Xcode 27 runner image generally available (2026-10-15)](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/) · [actions/runner-images](https://github.com/actions/runner-images)
- 러너 확인: Actions → `macOS 탐침` 2번 실행 (11-19, run 44495129924)
