# 홍보 모션그래픽 (2026-10-10)

블로그 · SNS 에 올릴 **기능 중심 소개 영상**. 1080×1920 세로(릴스 · 쇼츠 · 네이버 블로그 동영상), 42초, 소리 없음.

| 파일 | 무엇 |
|---|---|
| `promo.html` | 영상 자체. 브라우저로 열면 바로 재생된다. 모든 움직임이 `render(t)` 하나에서 나온다 |
| `render.mjs` | `promo.html` 을 1/30초씩 찍어 `out/slowrich-promo.mp4` 로 굽는다 |
| `fonts/` | Pretendard (SIL OFL 1.1 — `Pretendard-LICENSE.txt`) |
| `out/slowrich-promo.mp4` | 구운 결과 |

```bash
node Tools/promo/render.mjs                    # 영상 굽기 (원격 세션에서 몇 분)
node Tools/promo/render.mjs --stills 3.5,11.5  # 그 초의 한 장만 PNG 로 (확인용)
```

**장면 순서** — 물음("노후 준비, 잘 가고 있나요?") → 앱 아이콘 · 이름 → ① 주간 점검 ② 궤적 ③ 만약에 ④ 자산 진단
⑤ 가족 공유 → 일부러 안 만든 것(서버 · 광고 · 자동 연동) → App Store 안내. 시간표는 `promo.html` 의 `T`.

**앱 화면은 `screenshots/` 를 그대로 읽는다** — CI 가 체험 자료(가상의 가족)로 찍은 것이라 실제 금액이 아니다.
앱 화면이 바뀐 뒤 다시 구우면 새 화면이 들어간다. 아이콘은 `App/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.

**올릴 때** — 음악은 넣지 않았다. 인스타그램 · 유튜브 쇼츠는 앱 안에서 저작권 없는 음악을 고를 수 있다.
마지막 장면에 "입력한 가정에 따른 계산이며 미래 수익을 보장하지 않습니다 · 화면은 가상의 체험 자료" 한 줄이 있다 — 지우지 않는다.
