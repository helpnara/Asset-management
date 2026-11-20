"""OCR 결과(ocr.jsonl)에서 종목 · 평가금액을 뽑아 정답(truth.json)과 견준다 (docs/25 J3).

앱이 할 일을 그대로 흉내 낸다 — 화면 배치를 미리 알지 않는다:
  1) 글자 줄을 위에서 아래로 놓고, 숫자가 아닌 줄 가운데 이름표가 아닌 것을 종목 이름 후보로
  2) 이름 아래부터 다음 이름 전까지에서 평가금액을 고른다 — `평가금액` 이름표가 있으면 그 줄의 숫자,
     없으면 가장 큰 글씨의 숫자. 부호(+ −)가 붙은 손익 · % · 주 · 매입/원금 은 뺀다
  3) 앱에 등록된 종목 이름과 맞춘다 (잘린 이름 … 은 앞부분으로)
  4) 화면 맨 위 계좌 총액 = 읽은 금액의 합 인지 검산
사용: python3 score.py ocr.jsonl [fix]
"""
import json, re, sys, difflib, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from collections import defaultdict

truth = {t["file"]: t for t in json.load(open("truth.json"))}
fix = int(sys.argv[2]) if len(sys.argv) > 2 else 1
obs = defaultdict(list)
for line in open(sys.argv[1]):
    o = json.loads(line)
    if o["fix"] != fix: continue
    o["top"] = 1 - (o["y"] + o["h"])          # 위에서부터
    obs[o["file"]].append(o)

from parser import parse as parse_lines, is_balanced, match as match_lines

def parse(file):
    lines = [dict(text=o["text"], x=o["x"], top=o["top"], width=o["w"], height=o["h"]) for o in obs[file]]
    r = parse_lines(lines)
    return r, [{"name": i["name"], "value": i["value"]} for i in r["items"]]

def match(name, registered):
    found = match_lines(name, registered)
    return (registered[found[0]], found[1]) if found else (None, 0.0)

tot_ok = tot_n = good = bad_value = bad_name = missing = caught = 0
report = []
for f, t in truth.items():
    result, found = parse(f)
    total_v = result["total"]
    reg = [r["name"] for r in t["rows"]]
    want = {r["name"]: r["value"] for r in t["rows"] if r["visible"]}
    got = {}
    for x in found:
        m, score = match(x["name"], reg)
        if score < 0.6: report.append(f"  {f}: 이름 못 맞춤 '{x['name']}' (가장 가까운 '{m}' {score:.2f})"); continue
        got[m] = x["value"]
    s = sum(v for v in got.values() if v)
    checksum = bool(is_balanced(result))
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
