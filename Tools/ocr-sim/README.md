# OCR 시뮬레이션 (J3 — 증권사 화면 캡처로 주간 점검 채우기 검토)

[docs/25](../../docs/25-ocr-entry.md) 의 시뮬레이션 도구. 앱 코드가 아니다.

1. `python3 make_shots.py` — 증권사 보유 종목 화면을 닮은 **가상** 캡처 HTML 과 정답 `truth.json`.
   실제 증권사 디자인 · 이름을 흉내 내지 않는다. 종목명 · 금액은 모두 지어낸 것.
2. `node render.mjs` — `shots/*.png` (1206×2622, iPhone @3x).
3. macOS 러너에서 `swift Tools/ocr-sim/ocr.swift Tools/ocr-sim/shots/*.png` — Apple Vision(iPhone 과 같은 엔진)으로 읽는다.
   `Actions → macOS 탐침` 에 그 명령을 넣는다. 로그의 `OCR` 줄을 받아 `ocr.jsonl` 로.
4. `python3 score.py ocr.jsonl` — 종목 이름 · 평가금액을 짝짓고 정답과 견준다.
