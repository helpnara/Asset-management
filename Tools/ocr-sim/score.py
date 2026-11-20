"""OCR 결과(ocr.jsonl)에서 종목 · 평가금액을 뽑아 정답(truth.json)과 견준다 (docs/25 J3).

앱이 할 일을 그대로 흉내 낸다 — 화면 배치를 미리 알지 않는다:
  1) 글자 줄을 위에서 아래로 놓고, 숫자가 아닌 줄 가운데 이름표가 아닌 것을 종목 이름 후보로
  2) 이름 아래부터 다음 이름 전까지에서 평가금액을 고른다 — `평가금액` 이름표가 있으면 그 줄의 숫자,
     없으면 가장 큰 글씨의 숫자. 부호(+ −)가 붙은 손익 · % · 주 · 매입/원금 은 뺀다
  3) 앱에 등록된 종목 이름과 맞춘다 (잘린 이름 … 은 앞부분으로)
  4) 화면 맨 위 계좌 총액 = 읽은 금액의 합 인지 검산
사용: python3 score.py ocr.jsonl [fix]
"""
import json, re, sys, difflib
from collections import defaultdict

truth = {t["file"]: t for t in json.load(open("truth.json"))}
fix = int(sys.argv[2]) if len(sys.argv) > 2 else 1
obs = defaultdict(list)
for line in open(sys.argv[1]):
    o = json.loads(line)
    if o["fix"] != fix: continue
    o["top"] = 1 - (o["y"] + o["h"])          # 위에서부터
    obs[o["file"]].append(o)

NUM = re.compile(r"[+\-−]?\d{1,3}(?:,\d{3})+(?:원)?")
LABELS = {"평가금액", "매입금액", "수익률", "투자원금", "종목명", "잔고", "체결", "손익", "9:41"}

def amounts(text):
    """그 줄에서 평가금액 후보가 될 숫자들 (부호 · % · 주 · 매입 · 원금은 뺀다)."""
    if "%" in text and not re.search(r"\d,\d{3}원", text): pass
    out = []
    for m in NUM.finditer(text):
        s = m.group(0)
        before = text[:m.start()]
        after = text[m.end():m.end() + 2]
        if s[0] in "+-−": continue
        if after.startswith("주") or after.startswith("%"): continue
        if "매입" in before[-6:] or "원금" in before[-6:]: continue
        if "(" in after: continue                      # 손익(…%) 꼴
        out.append(int(s.replace(",", "").replace("원", "")))
    return out

def is_name(o):
    t = o["text"].strip()
    if t in LABELS or not re.search(r"[가-힣A-Za-z]", t): return False
    if NUM.search(t) and not re.search(r"[가-힣]{2,}.*\d{3,4}\b|TOP|\d{2}년", t) and len(re.sub(r"[\d,원+\-−().%\s주·매입]", "", t)) < 2:
        return False
    if re.search(r"\d,\d{3}", t): return False         # 숫자가 든 줄(매입 … · 투자원금 …)은 이름이 아니다
    if "·" in t and ("****" in t or "평가" in t): return False   # 계좌 줄 · 총액 설명
    if t.startswith("총 ") or "평가손익" in t: return False
    return True

def parse(file):
    rows = sorted(obs[file], key=lambda o: (round(o["top"], 3), o["x"]))
    # 계좌 총액 — 맨 위 120pt 안에서 가장 큰 글씨의 숫자
    head = [o for o in rows if o["top"] < 0.30 and amounts(o["text"])]
    total = max(head, key=lambda o: o["h"]) if head else None
    total_v = amounts(total["text"])[0] if total else None
    body = [o for o in rows if total is None or o["top"] > total["top"] + total["h"]]
    names = [o for o in body if is_name(o) and o["x"] < 0.5]
    # 두 줄로 꺾인 이름 붙이기 (바로 아래 · 같은 왼쪽 · 숫자 없음)
    merged = []
    for o in names:
        if merged:
            p = merged[-1]
            if abs(o["x"] - p["x"]) < 0.02 and 0 < o["top"] - (p["top"] + p["h"]) < p["h"] * 0.9 \
                    and not any(lb in o["text"] for lb in LABELS):
                p["text"] += " " + o["text"]; p["h"] = o["top"] + o["h"] - p["top"]; continue
        merged.append(dict(o))
    found = []
    for i, n in enumerate(merged):
        lo = n["top"] - n["h"] * 0.6
        hi = merged[i + 1]["top"] - merged[i + 1]["h"] * 0.6 if i + 1 < len(merged) else 1.0
        band = [o for o in body if lo <= o["top"] < hi and o is not n]
        cands = [(o, v) for o in band for v in amounts(o["text"]) if o["x"] > 0.25]
        label = [o for o in band if o["text"].strip() == "평가금액"]
        if label:
            L = label[0]
            cands.sort(key=lambda ov: abs((ov[0]["top"] + ov[0]["h"] / 2) - (L["top"] + L["h"] / 2)))
        else:
            cands.sort(key=lambda ov: -ov[0]["h"])
        found.append({"name": n["text"], "value": cands[0][1] if cands else None,
                      "conf": min([n["conf"]] + ([cands[0][0]["conf"]] if cands else [0]))})
    return total_v, found

def match(name, registered):
    """앱에 등록된 이름과 맞추기 — 잘린 이름(…)은 앞부분으로, 나머지는 가장 비슷한 것."""
    clean = re.sub(r"\s*(…|\.\.\.)$", "", name.replace("...", "…")).rstrip("…").strip()
    pre = [r for r in registered if r.replace(" ", "").startswith(clean.replace(" ", "")[:max(4, len(clean.replace(' ', '')) - 1)])]
    if len(pre) == 1: return pre[0], 1.0
    best = max(registered, key=lambda r: difflib.SequenceMatcher(None, clean, r).ratio())
    return best, difflib.SequenceMatcher(None, clean, best).ratio()

tot_ok = tot_n = good = bad_value = bad_name = missing = caught = 0
report = []
for f, t in truth.items():
    total_v, found = parse(f)
    reg = [r["name"] for r in t["rows"]]
    want = {r["name"]: r["value"] for r in t["rows"] if r["visible"]}
    got = {}
    for x in found:
        m, score = match(x["name"], reg)
        if score < 0.6: report.append(f"  {f}: 이름 못 맞춤 '{x['name']}' (가장 가까운 '{m}' {score:.2f})"); continue
        got[m] = x["value"]
    s = sum(v for v in got.values() if v)
    checksum = (total_v == s)
    tot_n += 1; tot_ok += total_v == t["account_total"]
    file_bad = 0
    for n, v in want.items():
        if n not in got: missing += 1; file_bad += 1; report.append(f"  {f}: 못 찾음 '{n}' {v:,}")
        elif got[n] != v: bad_value += 1; file_bad += 1; report.append(f"  {f}: 금액 틀림 '{n}' 정답 {v:,} 읽음 {got[n]}")
        else: good += 1
    if file_bad and not checksum: caught += file_bad
    report.append(f"{f} ({t['layout']}): {len(want) - file_bad}/{len(want)} 맞음 · 계좌 총액 {'맞게 읽음' if total_v == t['account_total'] else f'틀림 {total_v}'} · 검산 {'합 = 총액' if checksum else f'합 ≠ 총액 (합 {s:,})'}")
n = sum(len([r for r in t["rows"] if r["visible"]]) for t in truth.values())
print("\n".join(report))
print(f"\n언어 보정 {'켬' if fix else '끔'}: 종목 {n}개 중 정확 {good} · 금액 틀림 {bad_value} · 못 찾음 {missing} "
      f"→ 정확도 {good / n * 100:.1f}% · 틀린 것 중 검산이 잡은 것 {caught}/{bad_value + missing} · 계좌 총액 {tot_ok}/{tot_n}")
