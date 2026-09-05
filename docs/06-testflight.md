# 6. 아이폰에 올리기 — 맥 없이 TestFlight까지

브라우저만으로 끝납니다. 맥도 Xcode도 필요 없습니다.
**딱 한 번만 하면 되고, 그 뒤로는 버튼 하나로 새 빌드가 올라갑니다.**

## 흐름

```
Claude가 코드 작성 → 푸시
        ↓
GitHub Actions(macOS) 가 빌드 · 서명 · 업로드
        ↓
애플이 처리 (5~15분)
        ↓
아이폰의 TestFlight 앱에서 설치
```

## 준비 (최초 1회, 약 30분)

### 1단계 · Apple Developer Program 가입 — 연 $99

<https://developer.apple.com/programs/enroll/>

개인(Individual)으로 가입하면 됩니다. 법인은 서류가 더 필요합니다.
결제 후 승인까지 보통 24~48시간 걸립니다. **이것만이 유일한 필수 지출입니다.**

> 가입 전까지는 CI 스크린샷으로 화면을 확인하며 개발을 계속할 수 있습니다.
> 폰에 올릴 준비가 됐을 때 결제하시면 됩니다.

### 2단계 · 앱 등록

승인되면 <https://appstoreconnect.apple.com> → **App** → **+** → **신규 앱**

| 항목 | 값 |
|---|---|
| 플랫폼 | iOS |
| 이름 | 느린 부자의 기록 |
| 기본 언어 | 한국어 |
| 번들 ID | `com.helpnara.slowrich` — 목록에 없으면 아래 3단계 먼저 |
| SKU | `slowrich` (아무 값이나, 내부 식별용) |

번들 ID가 목록에 없으면 <https://developer.apple.com/account/resources/identifiers/list>
에서 **+** → App IDs → App → 설명 `SlowRich`, Bundle ID `com.helpnara.slowrich` 로 먼저 만듭니다.

### 3단계 · App Store Connect API 키 만들기

이 키로 GitHub이 애플 대신 서명하고 업로드합니다. **인증서를 직접 만들 필요가 없습니다.**

<https://appstoreconnect.apple.com/access/integrations/api> → **팀 키** 탭 → **+**

| 항목 | 값 |
|---|---|
| 이름 | `GitHub Actions` |
| 액세스 | **App Manager** |

만들면 `AuthKey_XXXXXXXXXX.p8` 파일을 **한 번만** 내려받을 수 있습니다. 다시 못 받으니 잘 보관하세요.
같은 화면에서 **키 ID**(10자)와 **발급자 ID**(UUID 형태)도 적어둡니다.

### 4단계 · 팀 ID 확인

<https://developer.apple.com/account> → **Membership details** → **Team ID** (10자)

### 5단계 · 저장소 시크릿 4개 등록

<https://github.com/helpnara/Asset-management/settings/secrets/actions> → **New repository secret**

| 이름 | 값 |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | 3단계의 키 ID (예: `A1B2C3D4E5`) |
| `APP_STORE_CONNECT_ISSUER_ID` | 3단계의 발급자 ID (UUID) |
| `APP_STORE_CONNECT_KEY_P8` | `.p8` 파일을 텍스트 편집기로 열어 **전체 내용 붙여넣기** (`-----BEGIN PRIVATE KEY-----` 줄 포함) |
| `APPLE_TEAM_ID` | 4단계의 팀 ID |

### 6단계 · 첫 배포

<https://github.com/helpnara/Asset-management/actions/workflows/testflight.yml>
→ **Run workflow** → 브랜치 선택 → 실행

10분쯤 걸립니다. 끝나면 App Store Connect의 **TestFlight** 탭에 빌드가 나타납니다.

### 7단계 · 아이폰에서 설치

1. App Store에서 **TestFlight** 앱 설치
2. Apple 계정으로 로그인 (개발자 계정과 같은 계정)
3. 빌드가 보이면 **설치**

같은 계정이면 테스터 초대 없이 바로 보입니다. 가족에게도 보내려면
TestFlight 탭 → 내부 테스터에 Apple 계정 이메일을 추가하면 됩니다.

## 그 뒤로는

코드가 바뀔 때마다 **Run workflow** 버튼 하나면 새 빌드가 올라갑니다.
빌드 번호는 GitHub 실행 번호를 쓰므로 자동으로 증가합니다.

TestFlight 빌드는 **90일** 뒤 만료됩니다. 그 전에 새로 올리면 됩니다.

## 처음 켤 때 확인할 것

| 확인 | 왜 |
|---|---|
| 알림 권한을 허용했는가 | 알림이 이 앱의 유일한 시작 계기다 ([ADR-0005](adr/0005-manual-entry.md)) |
| 더보기 → 주간 점검 알림에서 요일·시각이 맞는가 | 기본은 토요일 오전 9시 |
| 구성원 → 계좌 → 종목을 실제 값으로 넣었는가 | 시세를 가져오지 않으므로 직접 넣어야 한다 |
| 전세보증금 같은 항목을 `고정`으로 뒀는가 | 매주 물어보는 항목이 줄어든다 |

## 막힐 만한 곳

| 증상 | 원인과 해결 |
|---|---|
| `APP_STORE_CONNECT_KEY_P8 이 비어 있습니다` | 5단계 시크릿 누락. 이름 철자를 확인하세요 |
| `No profiles for 'com.helpnara.slowrich' were found` | 2단계 앱 등록이 안 됐거나 번들 ID가 다릅니다 |
| `Authentication credentials are missing or invalid` | API 키 액세스가 **App Manager** 인지 확인 |
| 업로드는 됐는데 TestFlight에 안 보임 | 애플 처리에 15분까지 걸립니다. 수출 규정 질문에 답해야 할 수도 있습니다 |
| 빌드 번호 중복 오류 | 이미 올린 번호입니다. 다시 실행하면 새 번호가 붙습니다 |

## 아직 안 하는 것

- **App Store 정식 출시** — 심사, 스크린샷, 개인정보 처리방침이 필요합니다.
  가족끼리 쓰는 동안은 TestFlight로 충분합니다.
- **iCloud 동기화** — 스키마는 준비돼 있지만([ADR-0001](adr/0001-swiftdata-cloudkit.md))
  켜지 않았습니다. 기기 하나에서 먼저 안정화한 뒤 켭니다.
