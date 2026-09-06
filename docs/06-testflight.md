# 6. 아이폰에 올리기 — 맥 없이 TestFlight까지

**맥이 없어도 됩니다.** GitHub Actions의 macOS 러너가 빌드·서명·업로드를 대신하고,
사용자는 아이폰의 TestFlight 앱으로 설치합니다.

이 문서는 **Apple Developer Program 승인이 난 뒤**의 절차입니다.
전부 브라우저에서 합니다. 한 번만 하면 그다음부터는 버튼 하나입니다.

## 흐름

```
GitHub에서 workflow 실행
   ↓
macOS 러너: xcodegen → 테스트 → archive → 서명 → .ipa
   ↓
App Store Connect 업로드 (처리 5~15분)
   ↓
아이폰 TestFlight 앱에서 설치
```

## 승인을 기다리는 동안 할 수 있는 것

가입비를 냈어도 **승인 전에는 2~7단계를 할 수 없습니다.** 개발자 포털의
Identifiers·App Store Connect 자체가 열리지 않습니다. 그동안 준비할 것:

| 할 일 | 왜 |
|---|---|
| Apple ID 2단계 인증 확인 | 없으면 승인돼도 포털에 못 들어갑니다 |
| 앱 이름 후보 2~3개 준비 | App Store 전체에서 유일해야 합니다. `느린 부자의 기록` 이 이미 쓰이고 있으면 뒤에 말을 붙여야 합니다 |
| 승인 메일 확인 | 보통 24~48시간. 길면 일주일. 서류를 더 요구하는 메일이 올 수도 있으니 스팸함도 보세요 |
| 진행 상황 확인 | <https://developer.apple.com/account> 에 들어가서 `Certificates, Identifiers & Profiles` 가 보이면 승인된 것입니다 |

승인 메일 제목은 보통 *"Welcome to the Apple Developer Program"* 입니다.

## 준비 (최초 1회, 약 40분)

순서대로 하세요. **2·3단계를 건너뛰면 첫 빌드가 서명에서 막힙니다.**

---

### 1단계 · Apple Developer Program 가입 — 연 $99

<https://developer.apple.com/programs/enroll/>

- 개인 자격이면 이름·주소·전화번호와 카드만 있으면 됩니다
- 승인까지 보통 하루이틀, 길면 일주일
- **Apple ID에 2단계 인증이 켜져 있어야 합니다**

> 무료로는 안 되나요? 무료 계정으로는 맥의 Xcode에서 케이블로 연결해 7일짜리
> 빌드만 넣을 수 있습니다. 맥이 없으면 그 경로 자체가 없습니다.

---

### 2단계 · iCloud 컨테이너 먼저 만들기 ⚠️

**App ID 보다 이걸 먼저 만듭니다.** App ID 는 만든 뒤 편집 화면으로 다시 들어가야
컨테이너를 연결할 수 있는데(3단계), 그때 고를 컨테이너가 이미 있어야 합니다.
없으면 거기서 또 나갔다 와야 합니다.

이 앱은 iCloud 자격을 **요구하도록** 설정돼 있습니다
(`App/SlowRich.entitlements`). 컨테이너가 없으면 프로비저닝 프로파일에 그 자격을
넣을 수 없어서 **아카이브 단계에서 실패합니다.**

<https://developer.apple.com/account/resources/identifiers/list/cloudContainer>

오른쪽 위 **+** → **iCloud Containers** → Continue

| 항목 | 값 |
|---|---|
| Description | `SlowRich` |
| Identifier | `iCloud.com.helpnara.slowrich` |

**Continue → Register**

> 식별자는 코드에 박혀 있습니다 (`Persistence.cloudKitContainerID`).
> 오타가 나면 앱은 빌드되지만 **동기화가 조용히 안 됩니다.** 한 글자씩 확인하세요.

---

### 3단계 · App ID 만들기 + 컨테이너 연결

<https://developer.apple.com/account/resources/identifiers/list>

**+** → **App IDs** → **App** → Continue

| 항목 | 값 |
|---|---|
| Description | `SlowRich` |
| Bundle ID | **Explicit** 을 고르고 `com.helpnara.slowrich` |

`Explicit` 과 `Wildcard` 중 **반드시 Explicit** 입니다.
Wildcard 로는 iCloud 와 푸시를 쓸 수 없습니다.

같은 화면 아래 **Capabilities** 목록에서 두 개를 체크합니다.

- ☑ **iCloud**
- ☑ **Push Notifications**

**Continue → Register**

#### ⚠️ 컨테이너 연결은 등록한 **뒤에** 한다

**만드는 화면에서는 iCloud 컨테이너를 고를 수 없습니다.** 체크박스만 있고
`Configure` 버튼이 없는 것이 정상입니다. 등록을 마쳐야 나타납니다.

1. `Identifiers` 목록으로 돌아가 방금 만든 `SlowRich` 를 클릭 (편집 화면)
2. **iCloud** 줄의 **Configure**(또는 **Edit**) 클릭
3. 2단계에서 만든 `iCloud.com.helpnara.slowrich` 체크 → **Continue**
4. **Save** — 기존 프로파일에 영향을 준다는 경고가 뜨면 **Confirm**

편집 화면의 iCloud 줄에 컨테이너가 표시되면 연결된 것입니다.
아무것도 안 보이면 저장이 안 된 것이니 다시 하세요.

> 2단계(컨테이너 생성)를 먼저 해 두는 이유가 여기입니다. 안 해 뒀으면
> Configure 를 눌러도 고를 것이 없어 또 나갔다 와야 합니다.

### 4단계 · App Store Connect에 앱 등록

<https://appstoreconnect.apple.com> → **앱** → **+** → **신규 앱**

| 항목 | 값 |
|---|---|
| 플랫폼 | iOS |
| 이름 | `느린 부자의 기록` |
| 기본 언어 | 한국어 |
| 번들 ID | 목록에서 `com.helpnara.slowrich` 선택 |
| SKU | `slowrich` (아무 값이나, 내부 식별용) |
| 사용자 액세스 | 전체 액세스 |

> 이름은 App Store 전체에서 유일해야 합니다. 이미 쓰이고 있으면
> `느린 부자의 기록 - 가계 자산` 처럼 뒤를 붙이세요. 앱 아이콘 아래 표시되는
> 이름은 `CFBundleDisplayName`(= `느린 부자의 기록`)이라 여기 이름과 달라도 됩니다.

---

### 5단계 · App Store Connect API 키 만들기

이 키로 GitHub이 애플 대신 서명하고 업로드합니다.
**인증서(.p12)나 프로비저닝 프로파일을 직접 만들 필요가 없습니다.**

<https://appstoreconnect.apple.com/access/integrations/api> → **팀 키** 탭 → **+**

| 항목 | 값 |
|---|---|
| 이름 | `GitHub Actions` |
| 액세스 | **App Manager** |

**생성**을 누르면 `AuthKey_XXXXXXXXXX.p8` 파일을 **딱 한 번** 받을 수 있습니다.
다시 못 받으니 잘 보관하세요.

같은 화면에서 두 값을 적어 둡니다:

- **키 ID** — 키 목록의 `Key ID` 열 (10자리, 예: `A1B2C3D4E5`)
- **발급자 ID** — 화면 위쪽 `Issuer ID` (UUID 형식)

---

### 6단계 · 팀 ID 확인

<https://developer.apple.com/account> → 오른쪽 위 **Membership details**

`Team ID` — 10자리 문자열입니다.

---

### 7단계 · GitHub 저장소 시크릿 4개 등록

<https://github.com/helpnara/Asset-management/settings/secrets/actions>

**New repository secret** 을 네 번 누릅니다. **이름 철자가 정확해야 합니다.**

| 시크릿 이름 | 값 |
|---|---|
| `APP_STORE_CONNECT_KEY_P8` | `.p8` 파일을 **텍스트 편집기로 열어** 내용 전체를 붙여넣기 (`-----BEGIN PRIVATE KEY-----` 줄부터 `-----END PRIVATE KEY-----` 줄까지) |
| `APP_STORE_CONNECT_KEY_ID` | 5단계의 키 ID |
| `APP_STORE_CONNECT_ISSUER_ID` | 5단계의 발급자 ID |
| `APPLE_TEAM_ID` | 6단계의 팀 ID |

> `.p8` 은 줄바꿈까지 그대로 넣어야 합니다. 한 줄로 붙으면 서명이 실패합니다.

---

### 8단계 · 첫 배포

<https://github.com/helpnara/Asset-management/actions/workflows/testflight.yml>

**Run workflow** → 브랜치 `claude/iphone-asset-management-design-7aafjc` 선택 →
`테스터에게 보여줄 변경 사항` 에 아무거나 적고 → **Run workflow**

10~15분 걸립니다. 초록불이 뜨면 업로드까지 끝난 것입니다.

---

### 9단계 · 수출 규정 · 테스터 등록

App Store Connect → 앱 → **TestFlight** 탭

1. 빌드가 `처리 중` 에서 `테스트 준비 완료` 로 바뀔 때까지 5~15분 기다립니다
2. 수출 규정 질문은 **이미 답해 뒀습니다** (`ITSAppUsesNonExemptEncryption: false`).
   그래도 물어보면 "아니오"입니다 — 이 앱은 암호화를 직접 쓰지 않습니다
3. **내부 테스팅** → **+** → 본인 Apple ID 추가

---

### 10단계 · 아이폰에서 설치

1. App Store에서 **TestFlight** 앱을 받습니다
2. 초대 메일의 링크를 아이폰에서 엽니다
3. TestFlight 안에서 `느린 부자의 기록` → **설치**

---

## 처음 켤 때 확인할 것

| 확인 | 왜 |
|---|---|
| 첫 화면에서 **[토요일 알림 받기]** 를 눌렀는가 | 알림이 이 앱의 유일한 시작 계기다 ([ADR-0005](adr/0005-manual-entry.md)). 여기서 거절하면 토요일에 아무 일도 일어나지 않는다 |
| **더보기 → 동기화**가 `iCloud 동기화` · `연결됨` 인가 | ⚠️ 여기가 `이 기기에만 저장` 이면 백업이 안 되고 있다. 앱을 지우면 기록이 사라진다 |
| 더보기 → 주간 점검 알림에서 요일·시각이 맞는가 | 기본은 토요일 오전 9시 |
| 구성원 → 계좌 → 종목을 실제 값으로 넣었는가 | 시세를 가져오지 않으므로 직접 넣어야 한다 |
| 전세보증금 같은 항목을 `고정`으로 뒀는가 | 매주 물어보는 항목이 줄어든다 |
| 해외 종목을 **원화로 환산해서** 적었는가 | 이 앱의 모든 금액은 원화다. 달러로 적으면 합계가 1,400배 틀린다 |
| 계획 탭에 은퇴 후 월 생활비를 넣었는가 | 넣어야 인출 구간과 자산 고갈 시점이 그려진다 |

## CloudKit 스키마 배포 (첫 실행 뒤 한 번)

앱이 처음 실행되면 CloudKit **Development** 환경에 스키마가 자동으로 올라갑니다.
TestFlight·App Store 빌드는 **Production** 환경을 쓰므로 한 번 배포해 줘야 합니다.

<https://icloud.developer.apple.com> → 컨테이너 `iCloud.com.helpnara.slowrich` 선택
→ **Schema** → **Deploy Schema Changes** → Development → Production → **Deploy**

> 이 단계를 건너뛰면 TestFlight 빌드에서 동기화가 조용히 안 됩니다.
> **더보기 → 동기화**가 `연결됨` 인데도 다른 기기에 안 넘어오면 여기를 의심하세요.
>
> 모델을 바꿀 때마다(필드 추가 등) 다시 배포해야 합니다.

## 그 뒤로는

코드가 바뀔 때마다 **Run workflow** 버튼 하나면 새 빌드가 올라갑니다.
빌드 번호는 GitHub 실행 번호를 쓰므로 자동으로 증가합니다.

TestFlight 빌드는 **90일** 뒤 만료됩니다. 그 전에 새로 올리면 됩니다.

## 막힐 만한 곳

| 증상 | 원인과 해결 |
|---|---|
| `APP_STORE_CONNECT_KEY_P8 이 비어 있습니다` | 7단계 시크릿 누락. 이름 철자를 확인하세요 |
| `No profiles for 'com.helpnara.slowrich' were found` | 3단계 App ID 등록이 안 됐거나 번들 ID가 다릅니다 |
| `doesn't include the com.apple.developer.icloud-container-identifiers entitlement` | **2단계**를 안 했거나, 3단계에서 App ID 를 **등록한 뒤 편집 화면으로 다시 들어가 Configure 로 연결**하지 않았습니다 |
| App ID 만드는 화면에 `Configure` 버튼이 없다 | 정상입니다. 등록을 마치고 목록에서 그 App ID 를 다시 열면 나타납니다 |
| `Provisioning profile doesn't include the aps-environment entitlement` | 3단계에서 **Push Notifications** 를 체크하지 않았습니다 |
| `Your team has no devices from which to generate a provisioning profile` | 아카이브가 **개발용**으로 서명되고 있었습니다. 개발용 프로파일은 등록된 기기가 있어야 만들어집니다. `project.yml` 의 Release 설정이 `Apple Distribution` 인지 확인하세요 — 기기를 등록해서 우회할 문제가 아닙니다 |
| `No profiles for 'com.helpnara.slowrich' were found` (위 오류와 함께) | 같은 원인입니다. 워크플로의 `서명 설정 확인` 단계 출력에서 `CODE_SIGN_IDENTITY` 가 `Apple Distribution` 으로 나오는지 보세요 |
| `Authentication credentials are missing or invalid` | API 키 액세스가 **App Manager** 인지 확인 |
| `Missing required icon file` | 앱 아이콘 누락. `App/Assets.xcassets/AppIcon.appiconset` 에 1024×1024 PNG(알파 없음)가 있어야 합니다 |
| 업로드는 됐는데 TestFlight에 안 보임 | 애플 처리에 15분까지 걸립니다 |
| 빌드 번호 중복 오류 | 이미 올린 번호입니다. 다시 실행하면 새 번호가 붙습니다 |
| 앱은 켜지는데 더보기에 `이 기기에만 저장` | iCloud 자격이 빠진 빌드입니다. 앱이 죽지 않고 로컬로 열린 것이므로 기록은 남아 있습니다. 2·3단계를 마치고 새 빌드를 올리면 그대로 이어집니다 |
| 동기화가 `연결됨` 인데 다른 기기에 안 옴 | CloudKit 스키마를 Production 에 배포하지 않았습니다 (위 섹션) |

## 다음 단계

가족끼리 쓰는 동안은 TestFlight로 충분합니다.
누구나 다운로드할 수 있게 하려면 → [7. App Store 출시](07-app-store.md)
