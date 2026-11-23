"""여러 장 묶기 · 이어 붙이기 채점 (226번). 사용: python3 multipage.py

long.jsonl(긴 계좌를 스크롤하며 찍은 장들)과 ideal.jsonl(한 장짜리 계좌들)을 **섞어** 한 번에 고른 것처럼 넣고,
batch.group 이 계좌마다 하나로 묶어 모든 종목 · 금액 · 검산을 맞추는지 본다. 순서를 뒤섞은 경우도 본다.
"""
import json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from batch import group, gap_hint
from parser import is_balanced, match

def load(path, key):
    pages = {}
    for line in open(path):
        o = json.loads(line)
        if path.endswith("ideal.jsonl"):
            if o["fix"] != 1: continue
            o["top"] = 1 - (o["y"] + o["h"]); o["page"] = 0
        name = o["file"] if path.endswith("ideal.jsonl") else f'{o["file"]}#{o["page"]}'
        pages.setdefault(name, []).append(dict(text=o["text"], x=o["x"], top=o["top"], width=o["w"], height=o["h"]))
    return pages

pages = {**load("ideal.jsonl", "file"), **load("long.jsonl", "file")}
truth = {t["file"]: t for t in json.load(open("truth.json")) + json.load(open("long_truth.json"))}

def account_of(name): return name.split("#")[0]

def run(title, names, accounts=()):
    groups = group([pages[n] for n in names], accounts)
    want = {}
    for n in names: want.setdefault(account_of(n), []).append(n)
    ok = len(groups) == len(want)
    lines = []
    for g in groups:
        files = {account_of(names[p]) for p in g["pages"]}
        r = g["result"]
        if len(files) != 1:
            ok = False; lines.append(f"   ✗ 다른 계좌가 섞임 {sorted(files)}"); continue
        f = files.pop(); t = truth[f]
        rows = [x for x in t["rows"] if x.get("visible", True)]
        got = {}
        for it in r["items"]:
            m = match(it["name"], [x["name"] for x in rows])
            if m: got[rows[m[0]]["name"]] = it["value"]
        wrong = [x["name"] for x in rows if got.get(x["name"]) != x["value"]]
        balanced = is_balanced(r)
        good = not wrong and len(r["items"]) == len(rows) and balanced is not False
        ok &= good and sorted(g["pages"]) == [i for i, n in enumerate(names) if account_of(n) == f]
        hint = gap_hint(r, len(g["pages"]))
        lines.append(f"   {'✓' if good else '✗'} {f}: 장 {[p + 1 for p in g['pages']]} · 종목 {len(r['items'])}/{len(rows)}"
                     f" · 틀림 {len(wrong)} · 검산 {balanced} · 총액 {r['total']}" + (f" · {hint}" if hint else ""))
        if wrong: lines.append(f"      틀린 종목: {wrong[:4]}")
    print(f"{'✓' if ok else '✗'} {title} — 묶음 {len(groups)}/{len(want)}")
    print("\n".join(lines))
    return ok

def pg(f, mode, n): return [f"{f}#{mode}#{i}" for i in range(n)]
count = lambda f, mode: len([k for k in pages if k.startswith(f"{f}#{mode}#")])
cases = []
for f in ("m-list", "m-table", "m-sticky"):
    for mode in ("ov", "cut"):
        cases.append((f"{f} {mode} 혼자", pg(f, mode, count(f, mode))))
for mode in ("ov", "cut"):
    mix = ["a1"] + pg("m-list", mode, count("m-list", mode)) + ["b1"] + pg("m-table", mode, count("m-table", mode)) \
          + ["e1"] + pg("m-sticky", mode, count("m-sticky", mode)) + ["g3"]
    cases.append((f"섞어서 {mode} (고른 차례대로)", mix))
    random.seed(226)
    rev = ["a1"] + list(reversed(pg("m-list", mode, count("m-list", mode)))) + ["c1"] + pg("m-table", mode, count("m-table", mode))[::-1] + ["f1"]
    cases.append((f"섞어서 {mode} (긴 계좌의 장을 거꾸로)", rev))
    shuffled = mix[:]; random.shuffle(shuffled)
    cases.append((f"섞어서 {mode} (전부 뒤섞음)", shuffled))
results = [run(t, n) for t, n in cases]

# 앱 계좌를 알려 준 채로(종목 짝 증거까지) — 같은 결과여야 한다
accounts = [dict(id=f, key="", holdings=[dict(id=f"{f}/{x['name']}", name=x["name"]) for x in t["rows"]]) for f, t in truth.items()]
random.seed(7)
mix = ["a1"] + pg("m-list", "cut", 3) + ["b1"] + pg("m-table", "ov", count("m-table", "ov")) + ["g1"] + pg("m-sticky", "ov", 2)
random.shuffle(mix)
results.append(run("앱 계좌를 알려 주고 전부 뒤섞음", mix, accounts))

# 같은 장을 두 번 골랐다 — 하나로 읽혀야 한다
results.append(run("같은 장을 두 번 (m-list 둘째 장)", ["m-list#ov#0", "m-list#ov#1", "m-list#ov#1", "m-list#ov#2"]))

# 가운데 장이 빠졌다 — 검산이 안 맞고, 모자란 금액이 빠진 종목들의 합이어야 한다
def missing_page():
    names = ["m-list#cut#0", "m-list#cut#2"]
    g = group([pages[n] for n in names])
    if len(g) != 1: print("✗ 가운데 장 빠짐 — 묶음", len(g)); return False
    r = g[0]["result"]; hint = gap_hint(r, 2)
    rows = truth["m-list"]["rows"]
    read = {rows[m[0]]["name"] for it in r["items"] if (m := match(it["name"], [x["name"] for x in rows]))}
    lost = sum(x["value"] for x in rows if x["name"] not in read)
    ok = hint == ("missing", lost)
    print(f"{'✓' if ok else '✗'} 가운데 장 빠짐 — 알림 {hint} · 빠진 종목 합 {lost:,}")
    return ok
results.append(missing_page())
print(f"\n{sum(results)}/{len(results)} 통과")
