"""시험 화면 `읽은 글자 복사` 로 받은 글을 읽어 규칙(parser.py = Core/CaptureParser.swift)을 다시 돌린다 (11-21).

사용: python3 from_paste.py 붙여넣은.txt   (또는 표준 입력)
- 줄 모양: `위 왼쪽 너비 높이 | 글자` — `#` 으로 시작하는 줄(앱이 읽은 결과)은 견주기용으로 그대로 보여 준다.
- 숫자를 `#` 으로 가린 글이면 `#` 을 `5` 로 바꿔 돌린다 — 금액 값은 틀려도 **어느 줄을 무엇으로 골랐는지**(배치 규칙)는 그대로 본다.
- 받은 글은 실제 금액 · 이름이 들어 있을 수 있다 — **저장소에 넣지 않는다.** 배치만 본떠 make_shots.py 에 지어낸 숫자로 더한다.
"""
import re, sys
from parser import parse, is_balanced

text = open(sys.argv[1], encoding="utf-8").read() if len(sys.argv) > 1 else sys.stdin.read()
header, lines = [], []
for raw in text.splitlines():
    if raw.startswith("#"):
        header.append(raw); continue
    m = re.match(r"\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\|\s?(.*)$", raw)
    if m:
        top, x, w, h, t = m.groups()
        lines.append(dict(text=t.replace("#", "5"), x=float(x), top=float(top), width=float(w), height=float(h)))
print("\n".join(header))
r = parse(lines)
print(f"\n규칙으로 다시: 계좌 줄 {r['account']!r} · 총액 {r['total']} · 현금 {r.get('cash')} · 검산 {is_balanced(r)}")
for item in r["items"]:
    print(f"  {item['name']} = {item['value']}")
