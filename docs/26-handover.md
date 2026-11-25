# 26. 이관 — 다른 계정에서 이어서 관리하기

> **2026-11-25 작성** (사용자: *"현재 앱을 다른 계정에서 계속 사후 관리 및 기능 개선을 할 수 있도록 이관 MD 파일을 만들어줘."*)
> 새 계정의 Claude 는 **이 문서 → [CLAUDE.md](../CLAUDE.md) → [08 피드백 "지금 상태"](08-feedback.md) → [로드맵 "출시 일정"](05-roadmap.md#출시-일정--claude-가-묻지-않고-계속-고친다-2026-09-22-사용자-요청)** 순서로 읽고 시작한다.
> 상태가 바뀌면 이 문서의 §1 을 그 자리에서 고친다 — 원본 기록은 08 · 05 · 15 다.

## 0. 한 줄로

`느린 부자`(iOS · SwiftUI · Core Data + CloudKit 가족 공유)는 **App Store 에 공개돼 있고**, 가족은 TestFlight 로 새 빌드를 먼저 받는다.
코드 · 설계 · 결정 · 할 일은 **전부 이 저장소에 있다** — 계정이 바뀌어도 잃는 것은 Claude 세션의 대화와 예약 알림뿐이다(§3).

## 1. 지금 상태 (2026-11-25)

| | 상태 | 원본 |
|---|---|---|
| App Store | **1.0.22 = 빌드 168 — 11-24 심사 제출 → 승인 · 공개** (자동 출시). 1.0.21(빌드 165)은 심사 취소 | [15](15-app-store-submission-sheet.md) 맨 위 |
| TestFlight | 마지막 빌드 **168** (11-24 22:08) — **2027-02-22 만료**. 그 전에 새 빌드가 하나 있어야 가족 폰 앱이 계속 열린다 | [05](05-roadmap.md) 출시 일정 `TestFlight 빌드 만료` |
| 데이터 모델 | **3판**(`Account.captureKey` · `Holding.captureName`). CloudKit Production 반영 끝(11-21) — 할 일 없음 | [18](18-stage5-foundation.md) · `Tools/coredata/migration-baselines.txt` 맨 위 `31d84f1` |
| 열린 확인 | **아이 폰 확인** — `더보기` 맨 아래 `버전` 이 `1.0.22 (168)` · `현황판` 맨 위 가족 총자산이 부모 폰과 같음(1.0.20 확인 기록이 없어 함께) | [08](08-feedback.md) 맨 아래 |
| 다음 피드백 번호 | **233** (캡처 예외는 계속 모은다) · 다음 판 **1.0.23** · `project.yml` 의 `MARKETING_VERSION` 은 아직 `1.0.22` — 다음 착수 때 올린다 | [08](08-feedback.md) |
| 작업 브랜치 | `claude/iphone-asset-management-design-7aafjc` (기본 브랜치가 아니다 — 모든 작업 · CI · 배포가 이 브랜치) | |
| CI | 마지막 CI 371 전부 초록(11-24) | GitHub Actions `iOS 빌드 · 테스트 · 스크린샷` |

## 2. 새 계정에서 처음 한 번 할 일

| ☐ | 무엇 | 어떻게 |
|---|---|---|
| ☐ | **GitHub 연결** | 새 계정의 claude.ai → 설정 → 커넥터(Connectors) 에서 GitHub 를 연결한다. 저장소 `helpnara/Asset-management` 에 **Claude GitHub 앱**이 이미 설치돼 있으니, 같은 GitHub 사용자(`helpnara`)로 연결하면 그대로 쓸 수 있다. **다른 GitHub 사용자로 연결하면** 저장소 주인이 `Settings → Collaborators` 에서 그 사용자를 **Write** 로 초대해야 푸시 · 워크플로 실행이 된다 |
| ☐ | **Claude Code 웹 세션 열기** | claude.ai/code 에서 저장소 `helpnara/Asset-management` 를 고르고 세션을 연다. 기본 네트워크 설정으로 충분하다(시세 · 환율을 안 가져오는 앱이라 밖으로 나갈 곳이 없다. `download.swift.org` 가 막혀 있는 것은 정상 — 컴파일은 CI 가 한다) |
| ☐ | **첫 메시지** | 아래 상자를 그대로 붙여 넣는다 |
| ☐ | **예약 알림 다시 걸기** | §4 의 셋 — 첫 세션에서 Claude 에게 "§4 예약 알림을 걸어줘" 라고 하면 된다 |
| ☐ | (확인) 빌드가 도는지 | 첫 착수 때 `testflight.yml` 을 돌려 보면 끝. 시크릿은 저장소에 붙어 있어 계정과 상관없다(§5) |

```
이 저장소는 iOS 앱 '느린 부자'다. 다른 Claude 계정에서 넘겨받아 이어서 관리한다.
git checkout claude/iphone-asset-management-design-7aafjc 후
docs/26-handover.md → CLAUDE.md → docs/08-feedback.md "지금 상태" → docs/05-roadmap.md "출시 일정" 순서로 읽고,
지금 App Store · TestFlight 상태와 열린 확인 항목, 다가오는 일정을 한글로 짧게 정리해 줘.
빌드는 내가 "착수하자" 라고 할 때만 돌린다.
```

## 3. 옮겨지는 것 · 안 옮겨지는 것

| 무엇 | 옮겨지나 | 비고 |
|---|---|---|
| 코드 · 설계 문서 · ADR · 피드백 기록(08) · 로드맵(05) · 제출 시트(15) | ✅ 저장소에 있다 | **이 문서들이 Claude 의 기억이다** — 세션을 넘어 기억하지 못하므로 결정은 늘 여기에 적는다 |
| GitHub Actions 워크플로 · 저장소 시크릿 5개 | ✅ 저장소에 붙어 있다 | §5 |
| Apple Developer · App Store Connect · CloudKit · iCloud 컨테이너 | ✅ 그대로 (Claude 계정과 무관) | 사람이 브라우저에서 다루는 것 |
| GitHub Pages (지원 · 처리방침 URL) | ✅ | `pages.yml` |
| 이 세션의 대화 내용 | ❌ | 필요한 것은 모두 08 · 15 · 25 에 적어 두었다 |
| **예약 알림**(12-01 · 12-21 · 01-11) | ❌ — 새 계정에서 다시 건다 | §4 |
| 캡처 시험용으로 받은 **실제 인식 글**(`읽은 글자 복사`) | ❌ — **일부러 안 옮긴다** | 실제 금액 · 계좌가 들어 있어 세션 임시 폴더에만 두었다. 같은 화면을 다시 봐야 하면 사용자에게 다시 받는다 |
| 유튜브 쇼츠 주간 보고 예약 | — 이 앱과 별개 | 다른 저장소(`People_mgmt`)의 일 |

## 4. 다시 걸 예약 알림

새 계정의 첫 세션에서 Claude 에게 걸게 한다(한국 시간). 내용은 그때의 문서를 읽고 판단하도록 적는다.

| 언제 (KST) | 이름 | 알림이 할 일 |
|---|---|---|
| **2026-12-01 09:00** | 다음 버전 · TestFlight 새 빌드 착수 여쭙기 | 08 "지금 상태" · 05 출시 일정 · 동결 표 · 15 맨 위를 읽고 ① 아이 폰 확인 여부 ② 마지막 TestFlight 빌드 만료(168 이면 2027-02-22) 전에 새 빌드가 필요한지 ③ 그사이 쌓인 항목(233~ · 동결 표 · [17](17-after-launch.md) F 후보)을 다음 판 후보로 짧게. 빌드는 사용자가 "착수하자" 라고 해야만 |
| **2026-12-21 09:00** | 에디터 추천 신청 알림 | [11](11-promote-request.md) 초안을 지금 판(08 · 15 맨 위)에 맞게 고치고, App Store Connect 프로모션 텍스트(심사 없음)를 연초 문구로 바꾸자고 제안. [17](17-after-launch.md) E 참고 |
| **2027-01-11 09:00** | 2.0 기능 고르기 알림 | [17](17-after-launch.md) F 후보 · 동결 표 · 08 에 쌓인 불편을 묶어 고르기 목록(기준: R7 · 같은 역할이 이미 있는지 먼저). [10](10-store-strategy.md) 3개월 목표 숫자를 사용자에게 물어 함께 본다 |

옛 계정의 알림은 옛 세션으로 날아가므로, 옛 계정을 더 쓰지 않으면 그대로 둬도 해가 없다(중복이 싫으면 옛 계정에서 지운다).

## 5. 계정 · 비밀값 지도 (값은 적지 않는다)

| 무엇 | 어디 | 비고 |
|---|---|---|
| `APPLE_TEAM_ID` · `APP_STORE_CONNECT_ISSUER_ID` · `APP_STORE_CONNECT_KEY_ID` · `APP_STORE_CONNECT_KEY_P8` | GitHub 저장소 `Settings → Secrets and variables → Actions` | `testflight.yml` · `appstore-screenshots.yml` 이 쓴다. 만드는 법 [06](06-testflight.md) |
| `CKTOOL_MGMT_TOKEN` | 같은 자리 | `cloudkit-schema.yml` (CloudKit 스키마를 Development 에 밀어 넣기). 09-29 갱신 |
| 번들 ID `com.helpnara.slowrich` · iCloud 컨테이너 `iCloud.com.helpnara.slowrich` | Apple Developer | **바꾸지 않는다** — 바꾸면 iCloud 자료 · TestFlight 설치본이 남남이 된다 |
| Apple Developer Program | 갱신 **2027-09-05** | 끊기면 App Store 에서 내려간다 |
| 서명 인증서 | Apple Developer → Certificates | 자동 서명이 빌드마다 개발용 인증서를 만들어 **한도가 찬다** — `maximum number of certificates` 로 TestFlight 가 실패하면 사용자에게 오래된 Apple Development 인증서 Revoke 를 부탁한다([06](06-testflight.md) "인증서가 꽉 찼습니다", 11-21 · 11-24 두 번) |
| CloudKit Production 승격 | CloudKit Console 웹의 **Deploy** 단추 | 사람만 누를 수 있다. 모델을 바꾼 판을 낼 때만 |

## 6. 일하는 방식 (원본은 CLAUDE.md — 여기는 요점)

- **말은 한글, 시각은 한국 시간.** 결정이 필요하면 선택지로 묻는다.
- **원격 세션은 리눅스라 컴파일을 못 한다** — 푸시하면 CI(macOS 러너)가 컴파일러다. 수치 기댓값은 파이썬 등으로 독립 계산해서 적는다.
- **빌드(CI 를 도는 푸시 · TestFlight)는 사용자가 "착수하자" · "빌드 …" 라고 할 때만.** 문서만 고친 커밋은 `[skip ci]`.
- **체크리스트는 코드에서 확인한 것만**, 화면에 보이는 이름 그대로의 전체 경로와 보이는 조건까지(CLAUDE.md 최상단 원칙).
- **실제 금액 · 기관명 · 계좌를 커밋하지 않는다**(저장소는 public). 사용자 화면 사진 · 인식 글의 숫자도 실제 금액이다 — 문서 · 시험에는 지어낸 숫자로.
- **외부 네트워크 요청을 더하지 않는다**(ADR-0005). 캡처 인식도 기기 안 Vision 만 — 앱 설명에 약속한 것이다.
- 커밋에 모델 이름을 적지 않는다.

### 늘 도는 흐름

| 단계 | 하는 일 | 적는 곳 |
|---|---|---|
| 1. 피드백 | 사용자가 쓰다가 찾은 것을 새 번호(233~)로. 기능을 더하기 전에 같은 역할이 이미 있는지 `grep` | [08](08-feedback.md) "있던 것 / 한 것" 표 · [05](05-roadmap.md) 동결 표 |
| 2. 착수 | 고치고 → 푸시 → CI 초록 확인(`actions_list` · `get_job_logs`) → `testflight.yml` 을 작업 브랜치에서 `workflow_dispatch` → 빌드 번호 = 그 실행의 run number | 08 해당 번호 아래 "빌드 N — 시각 TestFlight" + 체크리스트 |
| 3. 사용자 확인 | "빌드 N 체크리스트 확인 완료" → 그 번호를 닫는다 | 08 · 05 |
| 4. 심사 준비 | [15](15-app-store-submission-sheet.md) 맨 위에 새 버전 절(버전 번호 · 새로운 기능 글 · 빌드 번호 · 출시 방식). `Tools/coredata/migration-baselines.txt` 맨 위에 그 빌드의 커밋을 더한다 | 15 · baselines |
| 5. 제출 · 승인 | 사용자가 알려 주면 08 "지금 상태" · 05 출시 일정 · 15 를 고친다. 공개되면 아이 폰 확인(버전 · 금액 같음) | 08 · 05 · 15 |

- 심사를 **취소**하고 새 빌드로 다시 낼 때는 옛 버전 페이지의 버전 번호만 고쳐 쓰고, 새로운 기능 글은 **마지막 공개판 다음**으로 쓴다(1.0.18 → 1.0.19, 1.0.21 → 1.0.22 선례).
- **모델(칸)을 바꾸면** `.xcdatamodeld` 새 판 · `@NSManaged` · `Tools/cloudkit/slowrich.ckdb` 셋을 함께 고치고, `CloudKit 스키마` 워크플로로 Development 에 올린 뒤 사람이 Production 에 Deploy 한다(CLAUDE.md · [18](18-stage5-foundation.md)).

### 캡처로 채우기 — 인식 예외가 들어올 때

1. 사용자가 `더보기 → 실험 → 캡처 읽기 시험` 에서 캡처를 고르고, 장 카드의 `읽은 글자 복사` 로 복사한 글을 보낸다 → **세션 임시 폴더에만** 저장.
2. `cd Tools/ocr-sim && python3 from_paste.py <파일>` 로 지금 규칙의 결과를 본다(스크립트는 모두 `Tools/ocr-sim` 안에서 돌린다).
3. `Tools/ocr-sim/parser.py` · `batch.py` 를 먼저 고친다 — **`Core/Capture/CaptureParser.swift` · `CaptureBatch.swift` 를 줄 단위로 옮긴 것**이라 둘을 같이 고친다.
4. 회귀(같은 폴더에서): `python3 score.py ideal.jsonl`(105/105) · `python3 multipage.py`(15/15) · 앞서 받은 붙여 넣기들.
5. Swift 로 옮기고, 시험(`Packages/Core/Tests/CoreTests/CaptureParserTests.swift`)은 **지어낸 숫자로 같은 배치**를 본떠 기댓값을 파이썬으로 계산해 넣는다.
6. 설계 기록은 [25](25-ocr-entry.md), 항목은 08. 방향: 화면마다 규칙을 더하기보다 **검산(합 = 총액)이 답을 고르게**(232번).

## 7. 문서 지도

| 문서 | 무엇 |
|---|---|
| [CLAUDE.md](../CLAUDE.md) | 규칙 전부 — 세션이 시작될 때 저절로 읽힌다 |
| [01](01-product-spec.md) · [02](02-screens.md) · [03](03-data-model.md) · [04](04-architecture.md) · [adr/](adr/) | 제품 · 화면 · 모델 · 구조 · 되돌리기 비싼 결정 |
| [05 로드맵](05-roadmap.md) | **출시 일정 블록**(Claude 가 묻지 않고 고친다) · 동결 표 · 마일스톤 · 리스크 |
| [06 TestFlight](06-testflight.md) · [07 App Store](07-app-store.md) · [15 제출 시트](15-app-store-submission-sheet.md) | 맥 없이 올리기 · 출시 · 버전마다 제출 칸 |
| [08 피드백](08-feedback.md) | **"지금 상태" 줄** + 1~232번 항목과 체크리스트 |
| [09 가족 공유](09-family-sharing.md) · [18 5단계 기반](18-stage5-foundation.md) · [24 iOS 27 SDK](24-ios27-sdk.md) | CloudKit 공유 · 모델 판 쌓기 · SDK 전환 |
| [10](10-store-strategy.md) · [11](11-promote-request.md) · [17](17-after-launch.md) | 스토어 전략 · 에디터 추천 초안 · 출시 뒤 할 일(E 홍보 · F 2.0 후보) |
| [12 교훈](12-lessons-learned.md) · [20 새 앱 키트](20-new-app-kit.md) | 시행착오 — 같은 실수를 피하려면 먼저 |
| [14 매일 점검](14-daily-test-routine.md) | 한동안 안 누른 곳 목록 · 날짜 경계 확인 표 |
| [23 디자인 방향](23-design-direction.md) | "항상 고급스럽게" — 원칙 아홉 |
| [25 캡처 입력](25-ocr-entry.md) | 캡처로 채우기 설계와 인식 규칙의 이력 |
| `Tools/` | 아이콘 · CloudKit 스키마 · 모델 대조 · 캡처 시뮬레이터(`ocr-sim`) · 미리 보기 영상 · 홍보 |

## 8. 다가오는 일정

| 언제 | 무엇 |
|---|---|
| 1.0.22 공개 뒤 | 아이 폰 확인 (§1) |
| 12-01 | 다음 판 · 새 TestFlight 빌드 착수 여쭙기 (§4) |
| 12-21 | 에디터 추천 신청 · 프로모션 텍스트 연초 문구 (§4) |
| 2027-01-11 | 2.0 기능 고르기 (§4) |
| **2027-02-22 전** | TestFlight 빌드 168 만료 — 그 전에 새 빌드 |
| 2027-09-05 | Apple Developer Program 갱신 |
