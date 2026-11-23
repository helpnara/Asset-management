# OCR 시뮬레이션 (J3 — 증권사 화면 캡처로 주간 점검 채우기 검토)

[docs/25](../../docs/25-ocr-entry.md) 의 시뮬레이션 도구. 앱 코드가 아니다.

1. `python3 make_shots.py` — 증권사 보유 종목 화면을 닮은 **가상** 캡처 HTML 과 정답 `truth.json`.
   실제 증권사 디자인 · 이름을 흉내 내지 않는다. 종목명 · 금액은 모두 지어낸 것.
2. `node render.mjs` — `shots/*.png` (1206×2622, iPhone @3x).
3. macOS 러너에서 `swift Tools/ocr-sim/ocr.swift Tools/ocr-sim/shots/*.png` — Apple Vision(iPhone 과 같은 엔진)으로 읽는다.
   `Actions → macOS 탐침` 에 그 명령을 넣는다. 로그의 `OCR` 줄을 받아 `ocr.jsonl` 로.
4. `python3 score.py ocr.jsonl` — 종목 이름 · 평가금액을 짝짓고 정답과 견준다. 읽기 규칙은 `parser.py` — **앱의 `Core/CaptureParser.swift` 를 줄 단위로 옮긴 것이라 둘을 같이 고친다.**
5. `node ideal_lines.mjs` → `python3 score.py ideal.jsonl` — 글자를 완벽히 읽었다고 치고 규칙만 채점(가려진 글자는 뺀다). 배치 E(2단 표) · F(묶음 목록) · G(줄 셋 목록 — 총액 없음 / 현금 포함)는 11-20 실제 화면들을 본뜬 것 — 숫자 · 이름은 지어냈다.
6. `python3 from_paste.py 붙여넣은.txt` — 앱 시험 화면(`더보기 → 실험 → 캡처 읽기 시험`)의 **`읽은 글자 복사`** 로 받은 글을 그대로 읽어 규칙을 다시 돌린다. 숫자를 `#` 으로 가린 글은 `#` → `5`. **받은 글은 저장소에 넣지 않는다** — 배치만 본떠 `make_shots.py` 에 지어낸 숫자로 더한다.
7. **여러 장 묶기 · 이어 붙이기** (226번) — `python3 make_long.py` → `node long_lines.mjs` → `python3 multipage.py`.
   긴 계좌(목록 24종목 · 2단 표 12종목 · 머리가 붙어 다니는 목록 16종목)를 스크롤하며 찍은 장들(`ov` 한두 줄 겹치게 / `cut` 겹침 없이)을
   한 장짜리 계좌들과 **섞어** 넣고 — 고른 차례대로 · 긴 계좌의 장을 거꾸로 · 전부 뒤섞음 · 앱 계좌를 알려 주고 · 같은 장 두 번 ·
   가운데 장 빠짐 — 계좌마다 하나로 묶여 모든 종목 · 금액 · 검산이 맞는지 본다. 묶기 규칙은 `batch.py` —
   **앱의 `Core/CaptureBatch.swift` 를 옮긴 것이라 둘을 같이 고친다.**

