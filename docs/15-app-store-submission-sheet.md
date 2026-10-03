# 15. App Store 제출 시트 — 처음 채운다고 생각하고 위에서부터

> **2026-10-03 제출 완료** (사용자) — 빌드 119, 수동 출시. 이 시트대로 채웠다. 다음 버전을 낼 때도 이 순서를 쓴다
> (그때는 4-3 설명 · 4-5 빌드 · "이 버전의 새로운 기능" 만 바뀐다).

2026-10-03 사용자 결정으로 지금 낸다(안정화 기준 8). 이 문서는 **App Store Connect 화면
순서대로** 칸마다 넣을 값을 모은 것이다. 이미 채운 칸도 **다시 대조**한다 — 9월에 넣은 것 중
스크린샷 · 설명문 · 심사 메모는 10-03 에 바뀌었다. 배경과 이유는 [07 App Store 출시](07-app-store.md).

- 굵은 상자(```) 안의 글은 **그대로 복사해서 붙여 넣는다.**
- 각 줄의 ☐ 를 화면에서 확인하면서 지워 나간다.

## 0. 먼저 준비할 것

| ☐ | 무엇 | 어디서 |
|---|---|---|
| ☐ | 빌드 **119** 가 TestFlight 에 "완료" 로 떠 있다 (처리 중이면 10~30분 기다린다) | App Store Connect → 느린 부자 → TestFlight |
| ☐ | 빌드 118 · 119 체크리스트를 통과했다 — **11~13(119) 10-03 확인 완료**, 1~10(동시 점검 · 이번 주 맞추기)은 엄마 폰과 함께 | Claude 가 드린 체크리스트 |
| ☐ | **새 스크린샷 10장**을 받아 둔다 — 아이폰 6.5" 5장 · 아이패드 13" 5장. **10-03 새로 찍어 저장소에 올라가 있다** (머리글 `느린 부자` 확인) | 아래 4-1 |
| ☐ | 심사팀이 연락할 **전화번호** (+82 로 시작) | 본인 |
| ☐ | 처리방침 · 지원 주소가 브라우저에서 열린다 | 아래 3 · 4-4 |

## 1. 앱 정보 — `App Store` 탭 → 왼쪽 `일반` → `앱 정보`

| ☐ | 칸 | 값 | 비고 |
|---|---|---|---|
| ☐ | 이름 | `느린 부자` | 30자 이내 |
| ☐ | 부제 | `노후 준비 · 은퇴 계획 · 가족 자산 궤적` | 24자 (30자 이내) |
| ☐ | 기본 언어 | 한국어 | |
| ☐ | 카테고리 1차 | **금융** | |
| ☐ | 카테고리 2차 | **생산성** | |
| ☐ | 콘텐츠 권한 | "제3자 콘텐츠를 포함하지 않음" | 남의 글 · 그림 · 시세가 없다 |
| ☐ | 번들 ID · SKU | 손대지 않는다 | `com.helpnara.slowrich` |

### 1-1. 연령 등급 — 같은 화면 `연령 등급` → `편집`

모든 질문에 **없음 / 아니요** → 결과가 **4+** 인지 본다.

| 질문 무리 | 답 | 이유 (심사에서 물으면) |
|---|---|---|
| 폭력 · 성적 · 공포 · 욕설 · 약물 · 음주 | 없음 | 전부 없다 |
| 도박 · 모의 도박 | **아니요** | 투자 시뮬레이션은 계산이지 도박이 아니다 |
| 무제한 웹 접근 | 아니요 | 웹뷰가 없다 |
| 사용자 생성 콘텐츠 · 메시지 · 채팅 | 아니요 | 가족 공유는 초대한 사람끼리 기록을 함께 보는 것뿐, 공개도 메시지도 없다 |
| 광고 | 아니요 | 없다 |
| 의료 · 건강 | 아니요 | 없다 |
| 보호자 통제 · 연령 확인 | 아니요 | 필요 없는 앱이다 |

## 2. 가격 및 배포 — 왼쪽 `가격 및 배포`

| ☐ | 칸 | 값 |
|---|---|---|
| ☐ | 가격 | **무료** (0원 등급) |
| ☐ | 판매 국가 | **대한민국 하나** — 화면이 한국어뿐이고 금액이 원화뿐이다 |
| ☐ | 사전 주문 | 안 함 |
| ☐ | Mac · Vision Pro 에서 iPhone 앱 제공 | **끈다** — 시험하지 않았다 |

## 3. 앱이 수집하는 개인정보 — 왼쪽 `앱이 수집하는 개인정보`

09-11 에 넣었다. 그대로인지 본다.

| ☐ | 칸 | 값 |
|---|---|---|
| ☐ | 개인정보 처리방침 URL | `https://helpnara.github.io/Asset-management/privacy-policy/` |
| ☐ | 데이터 수집 | **"이 앱에서 데이터를 수집하지 않음"** |

근거: 서버 · 외부 통신 · 분석 · 광고가 없고, 자료는 기기와 사용자 본인의 iCloud 에만 있다
(본인 iCloud 는 애플 기준으로 "개발자가 수집" 이 아니다). 방침 최종 수정일 2026-09-27.

## 4. 1.0 버전 페이지 — 왼쪽 `iOS 앱` → `1.0 제출 준비 중`

### 4-1. 스크린샷 — **열 장 모두 새것으로 바꾼다**

옛 것(09-12)은 1번 머리글에 옛 이름 `느린 부자의 기록` 이 찍혀 있다. 지우고 새로 올린다.

| ☐ | 칸 | 파일 (순서대로) |
|---|---|---|
| ☐ | **iPhone 6.5" 디스플레이** (1284×2778) | `screenshots/appstore/store/iphone-6.5/` 의 `1-trajectory` → `2-review` → `3-family` → `4-diagnostics` → `5-no-server` |
| ☐ | iPad 13" 디스플레이 | `screenshots/appstore/store/ipad/` 의 같은 다섯 |

받는 법: GitHub 저장소 → `screenshots/appstore/store/iphone` 폴더 → 파일 → **Download raw file**.
**10-03 사용자 확인 — 이 앱의 App Store Connect 화면은 아이폰 칸이 6.5" 크기를 받는다.** 6.9"(1320×2868)
파일은 "크기가 맞지 않는다" 로 거절됐다. 같은 날 같은 워크플로가 찍은 `iphone-6.5/`(1284×2778)를 쓴다 —
화면 내용은 6.9" 와 같다. 앱 미리보기 영상은 안 넣는다.

### 4-2. 프로모션 텍스트 (170자 · 심사 없이 언제든 고칠 수 있다)

```
노후 준비를 습관으로. 매주 토요일 자산을 직접 적으면 그 숫자가 은퇴 계획선 위인지 아래인지 하나의 궤적으로 보입니다. 자동 연동 없음, 서버 없음, 광고 없음 — 손으로 적는 3분이 계획을 몸에 새깁니다.
```

### 4-3. 설명 (4000자 · 1,413자) — **10-03 판으로 다시 붙여 넣는다**

```
느린 부자는 노후 준비를 습관으로 만드는 앱입니다.
자동으로 잔고를 가져오지 않습니다. 매주 토요일, 직접 적습니다.
그 숫자가 은퇴 계획선 위인지 아래인지를 하나의 궤적으로 보여 줍니다.
혼자서도, 가족이 함께도 씁니다.

■ 매주 토요일, 3분
정한 요일과 시각에 알림이 옵니다. 종목별로 이번 주 평가액을 적어 넣으면
지난주 대비 증감이 바로 보입니다. 알림에서 총액만 먼저 적고 넘어갈 수도 있습니다.

■ 은퇴까지 이어지는 하나의 선
적어 넣은 기록(실선)과 계획에 따른 예측(점선)을 같은 축 위에 그립니다.
계획선 위에 있는지 아래에 있는지 한눈에 보입니다.
얼마를 넣어서 얼마가 자랐는지, 넣은 돈과 자란 돈을 나눠 보여 줍니다.

■ 은퇴 이후까지
은퇴 후 생활비와 연금(국민연금·퇴직연금·개인연금)을 넣으면 인출 구간까지
이어 그립니다. 자산이 언제 바닥나는지, 혹은 바닥나지 않는지 보여 줍니다.
국민연금은 가입 기간과 평균 소득으로 대략의 수령액을 추정해 채울 수 있습니다.

■ 만약에
월 적립액·은퇴 연도·기대수익률·은퇴 후 수익률·물가·변동성을 손잡이로 돌려 봅니다. 몬테카를로
1,000경로로 신뢰구간과 목표 도달 확률을 냅니다. 마음에 든 조합은 저장해 둡니다.

■ 자산 진단
· 은퇴 필요 자금 (4% 규칙)
· 부동산 비중 상한
· 국가 배분 (목표는 직접 정합니다)
· 세제혜택 계좌 채우는 순서
· 선저축 비율 (소득 대비 월 투자)
· 목표 비중 유지
· 월세 적정성
기준은 전부 사용자가 바꿉니다. 기본값은 널리 쓰이는 수치일 뿐 정답이 아닙니다.

■ 가족이 함께
iCloud 가족 공유로 한 가구의 기록을 함께 봅니다. 관리자가 사람마다
고칠 수 있는 구성원을 정해 주면, 각자 자기 몫을 적습니다.

■ 돌아보기
월간 · 연간 회고, 챙길 것(기한 알림), 운용 원칙, 변경 이력을 남깁니다.
매일 목표 · 실적 · 감사를 한 줄씩 적는 일기도 있습니다. 일기는 나만 봅니다.
계획 전체를 종이 한 장(1페이지 PDF)으로 뽑아 가족과 나눌 수 있습니다.

■ 시세를 가져오지 않습니다
의도된 설계입니다. 손으로 적는 그 수고가 계획 대비 실적을 체감하게 합니다.
자동으로 갱신되면 지난주와 이번주 사이의 증감에 내가 하지 않은 변화가 섞입니다.
모든 금액은 원화로 적습니다 — 해외 종목도 원화로 환산해서 넣습니다.

■ 자료는 내 것입니다
서버가 없습니다. 외부로 나가는 통신이 하나도 없습니다. 분석 도구도, 광고도
없습니다. 자료는 기기와 본인의 iCloud에만 있습니다. 개발자도 볼 수 없습니다.
Face ID 잠금과 금액 가리기, CSV 내보내기와 전체 백업을 지원합니다.

■ 투자 권유가 아닙니다
모든 계산은 사용자가 입력한 가정에 따른 것이며 미래 수익을 보장하지 않습니다.
금액은 모두 세전 기준입니다. 이 앱은 금융 상품을 추천하거나 중개하지 않습니다.
```

### 4-4. 키워드 · URL

| ☐ | 칸 | 값 |
|---|---|---|
| ☐ | 키워드 | 아래 상자 (쉼표로 구분, 공백 없이) |
| ☐ | 지원 URL | `https://helpnara.github.io/Asset-management/` |
| ☐ | 마케팅 URL | 비워 둔다 (선택) |

```
노후준비,은퇴계획,은퇴자금,가족자산,순자산,자산배분,연금,국민연금,파이어,재무계획,자산관리
```

### 4-5. 버전 정보

| ☐ | 칸 | 값 |
|---|---|---|
| ☐ | 버전 | `1.0` (앱의 `MARKETING_VERSION` 과 같다) |
| ☐ | 저작권 | `2026 권경락` (© 는 애플이 붙인다) |
| ☐ | 빌드 | **+** → **119** |
| ☐ | 이 버전의 새로운 기능 | 첫 버전이라 칸이 없다 |

### 4-6. App 심사 정보

| ☐ | 칸 | 값 |
|---|---|---|
| ☐ | 로그인 필요 | **체크 해제** (계정이 없다) |
| ☐ | 연락처 이름 | 권경락 |
| ☐ | 전화번호 | (본인) |
| ☐ | 이메일 | `kyunglagkwon@gmail.com` (처리방침의 문의 메일과 같다) |
| ☐ | 메모 | 아래 상자 — 영어, 한국어를 못 읽는 심사자에게 `체험 자료로 둘러보기` 버튼을 짚어 준다 |
| ☐ | 첨부 파일 | 없음 |

```
HOW TO SEE THE APP FULLY POPULATED (30 seconds)

The UI is Korean only. On first launch, at the BOTTOM of the welcome screen,
tap the text button with a sparkles icon: "체험 자료로 둘러보기"
(= "Explore with sample data"). This loads a fictional family of four with
12 weeks of records, so every screen — dashboard, trajectory chart, asset
diagnostics, simulation — is filled immediately. The sample data lives in
memory only and is discarded when you choose "내 자료로 시작" (start with my
own data); it never touches the user's real storage.

The five tabs across the bottom are:
현황판 (Dashboard) · 자산 (Assets) · 계획 (Plan) · 시뮬레이션 (Simulation) ·
더보기 (More).

NO ACCOUNT, NO NETWORK

There is no account, no login, and no backend. The app makes no network
requests at all: it does not fetch quotes, exchange rates, or any other data.
Every figure is typed in by the user, in Korean won.

iCloud is OPTIONAL and is NOT needed to review the app. All data is stored
locally. If the device happens to be signed in to iCloud, the app also syncs
to the user's own CloudKit private database, and an optional family-sharing
feature (더보기 (More) tab → the "가족" (Family) section) lets a household share
one record set via CKShare with people the owner invites. Nothing is ever
public, and there is no messaging. Both are conveniences; with no iCloud
account the app works fully.

NOT FINANCIAL ADVICE

The app does not offer, recommend, rate, or broker any financial product, and
it has no in-app purchases or ads. Every projection is arithmetic applied to
assumptions the user entered. The projection screens (dashboard trajectory,
simulation, one-page report) carry a Korean disclaimer meaning "this is a
calculation based on the assumptions you entered and does not guarantee
future returns." The diagnostics screen states in Korean that its rules are
common rules of thumb, not investment advice, that the app does not track
tax law, and that all amounts shown are pre-tax.

Optional permissions: notifications (a Saturday check-in reminder) and Face ID
(an optional app lock). Declining either blocks nothing.
```

### 4-7. 버전 출시

| ☐ | 칸 | 값 |
|---|---|---|
| ☐ | 버전 출시 | **이 버전을 수동으로 출시** — 통과해도 버튼을 누를 때까지 공개되지 않는다 |

## 5. 제출

| ☐ | 단계 |
|---|---|
| ☐ | 1.0 페이지 오른쪽 위 **심사에 추가** |
| ☐ | 빠진 칸이 있으면 빨간 표시가 뜬다 — 이 문서의 해당 절로 돌아가 채운다 |
| ☐ | 수출 규정을 물으면 "아니요" — 앱에 `ITSAppUsesNonExemptEncryption: false` 가 있어 보통 안 묻는다 |
| ☐ | **심사를 위해 제출** → 상태가 `심사 대기 중` 으로 바뀐다 |

## 6. 제출 뒤

| 상황 | 할 일 |
|---|---|
| 보통 24~48시간 뒤 메일 | `심사 통과` → 상태 `개발자 출시 대기` |
| 공개하고 싶을 때 | 1.0 페이지 **이 버전 출시** → 몇 시간 안에 App Store 에 나온다 |
| 반려 메일 | 메일과 App Store Connect 의 **해결 센터** 글을 그대로 Claude 에게 붙여 준다. 대부분 메모 · 메타데이터로 답하거나 빌드를 다시 올리면 된다 |
| 공개된 뒤 아이들 폰 | App Store 에서 `느린 부자` 를 받는다(아이 계정은 **구입 요청**으로 부모 승인이 필요할 수 있다) → 관리자 폰 `더보기 → 가족` 에서 초대 → `편집 권한` 에서 고칠 구성원을 정한다 |
| 부모 폰 | TestFlight 를 그대로 쓴다. 같은 iCloud 저장소라 같은 자료를 본다 |
