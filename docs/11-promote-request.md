# 11. 에디터 추천 신청서 초안 — App Store 프로모션 요청

출시 2주 전에 <https://developer.apple.com/contact/app-store/promote/> 에서 낸다
(docs/10 §5). 양식은 영어가 안전하다. 아래 영어를 붙여 넣고, 한국어는 뜻을
맞추기 위한 것이다. 실제 금액 · 가족 이름은 어디에도 없다.

## 기본 정보

| 항목 | 값 |
|---|---|
| App name | 느린 부자의 기록 (Slow Rich Journal) |
| Bundle ID | com.helpnara.slowrich |
| Platform | iPhone · iPad |
| Price | Free, no ads, no in-app purchases |
| Category | Finance (secondary: Productivity) |
| Release date | 2026년 10월 셋째 주 (심사 통과 뒤 수동 출시) |
| Storefront | Korea (한국어) |
| Contact | kyunglagkwon@gmail.com |

## 한 문단 소개 (English)

```
Slow Rich Journal turns retirement planning into a weekly habit. Every Saturday,
the family writes down their asset balances by hand — the app deliberately does
not fetch quotes or connect to banks — and those numbers are drawn as a single
trajectory against the plan line, all the way past retirement to age 100.
Up to four family members share one plan through CloudKit sharing: each sees
their own line and the household total on the same screen. There is no server,
no analytics, no advertising; data lives only on the device and in the user's
own iCloud. Built-in diagnostics (the 4% rule, real-estate share, country
allocation, tax-advantaged account order) watch the plan and say plainly when
something needs action — with the reasoning behind each rule one tap away.
```

## 왜 추천할 만한가 (English, 항목별)

```
• A different answer to "finance app": no bank linking by design. Writing the
  number yourself is the habit; the app makes that three-minute ritual pleasant
  and shows what it adds up to over 23 years.
• Family-first: CloudKit sharing with per-member edit permissions, so a spouse
  or grown child edits only their own accounts. Streaks are counted per person.
• Privacy as architecture, not a policy: zero outbound network calls. The App
  Privacy label is "Data Not Collected" — and it is literally true.
• Native throughout: SwiftUI, Swift Charts, Core Data + NSPersistentCloudKitContainer,
  Dynamic Type (up to xxxLarge), light and dark, iPhone and iPad, local
  notifications only.
• Honest math: deterministic projection plus a 1,000-path Monte Carlo band,
  computed in integer minor units (no floating-point money), with tests.
• A printable one-page plan (PDF) — the family's retirement plan on the fridge.
```

## 한국어 (뜻 맞추기용)

느린 부자의 기록은 노후 준비를 매주의 습관으로 만드는 앱입니다. 매주 토요일
가족이 자산을 직접 적습니다 — 시세도 은행 연동도 일부러 하지 않습니다 — 그
숫자가 계획선과 함께 은퇴를 지나 100세까지 하나의 궤적으로 그려집니다.
가족 넷이 CloudKit 공유로 한 계획을 봅니다. 서버 · 분석 · 광고가 없고 자료는
기기와 본인 iCloud 에만 있습니다. 4% 규칙 · 부동산 비중 · 국가 배분 ·
세제혜택 계좌 순서를 앱이 지켜보고, 할 일이 있으면 이유와 함께 말합니다.

## 첨부

- 스크린샷 5장 (`screenshots/appstore/store/iphone/`, `…/ipad/`) —
  `Actions → App Store 스크린샷` 워크플로가 만든다 (docs/07 4단계).
- 앱 아이콘 1024 (`Tools/icon/` 산출물).
- 미리보기 영상 15초는 선택 — 있으면 좋다.

## 낼 때 주의

- "featured" 를 부탁하는 글이 아니라 **무엇이 다른가** 를 적는 글이다. 위
  항목별 글이 그것이다.
- 출시일이 정해진 뒤에 낸다. 심사 통과 → 출시일 확정 → 신청.
- 답이 없는 것이 보통이다. 실리면 그날 다운로드가 열 배 뛴다 — 그 날
  문의 메일에 답할 시간을 비워 둔다.
