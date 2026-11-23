"""`Core/CaptureBatch.swift` 의 **여러 장 묶기 · 이어 붙이기**를 옮긴 것 (226번). 둘을 **같이** 고친다.

캡처 여러 장(계좌마다 한 장일 수도, 여러 장일 수도, 순서가 섞였을 수도)을 받아:
1. 장마다 읽는다(parser.parse) — 머리(계좌 줄 · 총액)가 있는 장과 없는 장을 가린다
2. **같은 계좌 머리는 하나로** — 계좌 표시(번호)가 같거나, 표시가 없으면 총액이 같은 머리 장(머리가 붙어 다니는 앱)
3. **머리 없는 장은 증거로 배정** — 겹친 줄(100) · 검산이 닫힘(50) / 이미 닫혔는데 새 종목(−50) ·
   종목 짝(10 × 짝) / 다른 계좌를 가리킴(−100) · 고른 순서로 바로 뒤(1). 0 이하면 앞 묶음(고른 순서) 또는 따로
4. **묶음마다 글자 줄을 이어 붙여 한 번에 읽는다** — 겹친 줄로 세로 간격을 재고, 장마다 같은 자리에 되풀이되는
   줄(상태 막대 · 탭 막대 · 붙어 다니는 머리)은 버린다. 표 머리줄이 첫 장에만 있어도 둘째 장의 열을 안다
Line = dict(text, x, top, width, height)
"""
import re
from parser import parse, is_balanced, expected_sum, normalized, match, bottom

SAME_X = 0.01      # 같은 줄로 볼 가로 어긋남
SAME_Y = 0.006     # 장마다 같은 자리(되풀이되는 줄)로 볼 세로 어긋남
SHIFT = 0.004      # 겹침 간격 표 묶음 폭


def key(text):
    return re.sub(r"\s", "", text)


def account_key(line):
    """계좌 줄 → 비교용 표시. 숫자 8개 이상(번호)이면 그 숫자, 아니면 빈칸을 걷은 글자 (Swift `accountKey`)."""
    if not line or not line.strip(): return ""
    best = ""
    for run in re.findall(r"[\d-]+", line):
        digits = re.sub(r"\D", "", run)
        if len(digits) >= 8 and len(digits) > len(best): best = digits
    return best or re.sub(r"\s", "", line).lower()


# MARK: - 두 장 사이

def repeated(a, b):
    """두 장에서 **같은 자리에 같은 글자** — 상태 막대 · 탭 막대 · 붙어 다니는 머리. (a 의 번호들, b 의 번호들)"""
    ra, rb = set(), set()
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            if key(x["text"]) == key(y["text"]) and abs(x["x"] - y["x"]) < SAME_X and abs(x["top"] - y["top"]) < SAME_Y:
                ra.add(i); rb.add(j)
    return ra, rb


def shift(a, b, ra=None, rb=None):
    """b 가 a 의 아래로 이어진 장이면 b 의 줄을 a 좌표로 옮길 세로 간격(> 0), 아니면 None.

    a 의 아래쪽과 b 의 위쪽에 **같은 글자 · 같은 가로 자리 · 같은 글씨 크기**의 줄이 있으면 그 간격들이 한 값으로 모인다.
    되풀이되는 이름표(`평가금액`)는 여러 간격에 흩어지므로 **서로 다른 글자 수**로 센다 — 둘 이상이거나,
    두 장에서 한 번씩만 나오는 세 글자 이상의 줄 하나면 겹침이다.
    """
    if ra is None: ra, rb = repeated(a, b)
    count_a, count_b = {}, {}
    for x in a: count_a[key(x["text"])] = count_a.get(key(x["text"]), 0) + 1
    for y in b: count_b[key(y["text"])] = count_b.get(key(y["text"]), 0) + 1
    votes = []
    for i, x in enumerate(a):
        k = key(x["text"])
        if i in ra or len(k) < 2: continue
        for j, y in enumerate(b):
            if j in rb or key(y["text"]) != k: continue
            if abs(x["x"] - y["x"]) >= SAME_X or abs(x["height"] - y["height"]) >= SAME_Y: continue
            d = x["top"] - y["top"]
            if d > 0.02: votes.append((d, k))
    best, best_score = None, 0
    for d, _ in votes:
        near = {k for e, k in votes if abs(e - d) < SHIFT}
        unique = [k for k in near if count_a.get(k) == 1 and count_b.get(k) == 1 and len(k) >= 3]
        score = len(near) if len(near) >= 2 else (1 if unique else 0)
        if score > best_score or (score == best_score and best is not None and d < best):
            best, best_score = d, score
    if not best_score: return None
    # 모인 간격들의 가운데 값
    near = sorted(e for e, _ in votes if abs(e - best) < SHIFT)
    d = near[len(near) // 2]
    # **겹친 띠 전체가 맞아야 겹침이다** — 다른 계좌에 같은 ETF 가 있으면 그 이름 한 줄은 맞는다(226번 시험).
    # 앞 장에서 b 의 내용이 시작되는 자리부터 앞 장 내용 끝까지의 줄 가운데 절반 넘게 b 에 같은 자리 · 같은 글자로 있어야 한다
    b_top = min((y["top"] for j, y in enumerate(b) if j not in rb), default=0.0) + d
    a_end = min([x["top"] for i, x in enumerate(a) if i in ra and x["top"] > 0.5], default=1.0)
    band = [x for i, x in enumerate(a) if i not in ra and x["top"] >= b_top - 1e-9 and bottom(x) <= a_end + 1e-9]
    if not band: return None
    hits = sum(1 for x in band if any(key(y["text"]) == key(x["text"]) and abs(y["x"] - x["x"]) < SAME_X
                                      and abs(y["top"] + d - x["top"]) < SHIFT for y in b))
    return d if hits * 2 > len(band) else None


def covered(line, others):
    """같은 줄(세로 가운데가 가깝고) 가로로 겹치는 줄이 있나 — 앞 장이 이미 읽은 자리."""
    return any(abs((o["top"] + o["height"] / 2) - (line["top"] + line["height"] / 2)) < max(o["height"], line["height"]) * 0.6
               and o["x"] < line["x"] + line["width"] and line["x"] < o["x"] + o["width"] for o in others)


EDGE = 0.06   # 앞 장 아래 끝에서 이만큼 — 경계에 걸려 앞 장이 못 읽은 줄이 있을 수 있는 띠


def stitch(pages, starts=None):
    """묶음 안의 장들(위에서 아래 차례)을 한 좌표계의 줄 목록으로.

    - 둘째 장부터: 앞 장과 같은 자리의 줄(되풀이)은 버린다. 머리가 있던 장이면 그 머리(`starts`)도 버린다
    - 겹치면 그 간격으로 옮기고, 앞 장이 이미 보인 자리(앞 장 아래 되풀이 줄 위까지)는 버린다
    - 안 겹치면 앞 장의 내용 바로 아래에 잇는다
    - 앞 장 아래쪽의 되풀이 줄(탭 막대)은 이어진 문서 한가운데 남지 않게 뺀다
    """
    out = [dict(l) for l in pages[0]]
    prev, prev_off = pages[0], 0.0
    prev_out_ids = list(range(len(out)))     # out 안에서 앞 장 줄의 자리
    for n, page in enumerate(pages[1:], start=1):
        ra, rb = repeated(prev, page)
        bottom_chrome = min([prev[i]["top"] for i in ra if prev[i]["top"] > 0.5], default=1.0)
        top_chrome = max([bottom(page[j]) for j in rb if page[j]["top"] < 0.5], default=0.0)
        head = (starts or {}).get(n)
        if head is not None: top_chrome = max(top_chrome, head)
        # 앞 장의 아래 되풀이 줄을 빼낸다
        drop = {prev_out_ids[i] for i in ra if prev[i]["top"] > 0.5}
        d = shift(prev, page, ra, rb)
        if d is not None:
            off = prev_off + d
            cutoff = prev_off + bottom_chrome
            # 앞 장이 보인 자리는 버린다. 다만 앞 장 아래 끝 띠에서 앞 장에 없던 줄(경계에 걸려 못 읽은 줄)은 남긴다
            seen = [dict(prev[i], top=prev[i]["top"] + prev_off) for i in range(len(prev)) if i not in ra]
            def wanted(l):
                g = dict(l, top=l["top"] + off)
                if g["top"] >= cutoff - 1e-9: return True
                return g["top"] >= cutoff - EDGE and not covered(g, seen)
            keep = [j for j, l in enumerate(page) if j not in rb and l["top"] > top_chrome - 1e-9 and wanted(l)]
        else:
            off = prev_off + bottom_chrome - top_chrome
            keep = [j for j, l in enumerate(page) if j not in rb and l["top"] >= top_chrome - 1e-9]
        out = [l for k, l in enumerate(out) if k not in drop]
        # 빼낸 뒤의 자리 다시 세기는 앞 장만 쓰므로, 새 장의 자리를 새로 적는다
        base = len(out)
        moved = {}
        for j in keep:
            l = dict(page[j]); l["top"] += off
            moved[j] = len(out); out.append(l)
        # 다음 장과 견줄 '앞 장'은 이 장 그대로(제 좌표) — 빼낸 줄의 자리를 찾을 수 있게 out 자리를 적어 둔다
        prev_out_ids = [moved.get(j, -1) for j in range(len(page))]
        prev, prev_off = page, off
    return out



# MARK: - 계좌 (Swift 와 같은 점수)

def pair(items, holdings):
    """읽은 종목 → 계좌 종목 번호(없으면 None). 기억한 증권사 이름 먼저, 그다음 이름 맞추기. 한 종목은 한 번만."""
    out = [None] * len(items); taken = set()
    for i, it in enumerate(items):
        for h in holdings:
            if h["id"] not in taken and h.get("capture") and normalized(h["capture"]) == normalized(it["name"]):
                out[i] = h["id"]; taken.add(h["id"]); break
    for i, it in enumerate(items):
        if out[i] is not None: continue
        free = [h for h in holdings if h["id"] not in taken]
        found = match(it["name"], [h["name"] for h in free])
        if found: out[i] = free[found[0]]["id"]; taken.add(out[i])
    return out


def suggest(result, accounts):
    """기억한 표시가 같은 계좌 하나 → (짝 수)가 가장 큰 하나(짝 > 0). 이 시험은 글자 점수를 빼고 짝만 본다."""
    k = account_key(result["account"])
    if k:
        same = [a for a in accounts if a.get("key") == k]
        if len(same) == 1: return same[0]["id"]
    scored = [(sum(1 for p in pair(result["items"], a["holdings"]) if p is not None), a["id"]) for a in accounts]
    if not scored: return None
    best = max(s for s, _ in scored)
    winners = [i for s, i in scored if s == best]
    return winners[0] if best > 0 and len(winners) == 1 else None


# MARK: - 묶기

def merged(results):
    """여러 장을 한 결과로 — 계좌 줄 · 총액 · 현금은 처음 나온 것, 종목은 이름이 같으면 금액이 있는 것 하나(겹쳐 찍힌 줄)."""
    items, seen = [], {}
    for r in results:
        for it in r["items"]:
            k = normalized(it["name"])
            if k in seen:
                if items[seen[k]]["value"] is None and it["value"] is not None: items[seen[k]] = it
                continue
            seen[k] = len(items); items.append(it)
    first = lambda f: next((r[f] for r in results if r.get(f) is not None), None)
    return dict(account=first("account"), total=first("total"), items=items, cash=first("cash"))


def closes(result):
    """검산이 닫혔나 — 총액이 있고 합(+현금)이 맞는가."""
    return bool(is_balanced(result))


def group(pages, accounts=()):
    """pages: 장마다 글자 줄 [[Line]] (고른 차례). → [dict(pages=[번호…], result=…)]"""
    accounts = list(accounts)
    results = [parse(p) for p in pages]
    is_head = [r["account"] is not None or r["total"] is not None for r in results]
    groups = []   # dict(pages=[…], key=…)

    # 2) 머리 장 — 같은 계좌면 하나로
    for i, r in enumerate(results):
        if not is_head[i]: continue
        k = account_key(r["account"])
        for g in groups:
            gr = merged([results[p] for p in g["pages"]])
            if (k and k == g["key"]) or (not k and not g["key"] and r["total"] is not None and r["total"] == gr["total"]):
                g["pages"].append(i); break
        else:
            groups.append(dict(pages=[i], key=k))

    # 3) 머리 없는 장 — 증거 점수로. 센 증거(겹침 · 검산)로 먼저 정하고, 나머지를 다시 본다
    pending = [i for i in range(len(pages)) if not is_head[i]]

    def score(u, g):
        s = 0
        if any(shift(pages[p], pages[u]) is not None or shift(pages[u], pages[p]) is not None for p in g["pages"]):
            s += 100
        before = merged([results[p] for p in g["pages"]])
        names = {normalized(it["name"]) for it in before["items"]}
        fresh = [it for it in results[u]["items"] if normalized(it["name"]) not in names]
        if before["total"] is not None and fresh:
            after = merged([results[p] for p in g["pages"]] + [results[u]])
            if closes(after) and not closes(before): s += 50
            elif closes(before): s -= 50
        account = suggest(before, accounts) if accounts else None
        mine = suggest(results[u], accounts) if accounts else None
        if account is not None:
            holdings = next(a["holdings"] for a in accounts if a["id"] == account)
            s += 10 * sum(1 for p in pair(results[u]["items"], holdings) if p is not None)
            if mine is not None and mine != account: s -= 100
        if u - 1 in g["pages"]: s += 1
        return s

    for strong in (True, False):
        changed = True
        while changed:
            changed = False
            for u in list(pending):
                scored = [(score(u, g), n) for n, g in enumerate(groups)]
                best = max(scored, default=(0, None))
                if best[0] >= (50 if strong else 1):
                    ties = [n for s, n in scored if s == best[0]]
                    if len(ties) == 1:
                        groups[best[1]]["pages"].append(u); pending.remove(u); changed = True
            if not strong: break
    # 남은 장 — 서로 겹치는 것끼리, 아니면 하나씩
    for u in pending:
        for g in groups:
            if g.get("loose") and any(shift(pages[p], pages[u]) is not None or shift(pages[u], pages[p]) is not None for p in g["pages"]):
                g["pages"].append(u); break
        else:
            groups.append(dict(pages=[u], key="", loose=True))

    # 4) 묶음마다 이어 붙여 다시 읽기
    out = []
    for g in groups:
        members = sorted(g["pages"])
        if len(members) == 1:
            out.append(dict(pages=members, result=results[members[0]])); continue
        ordered = arrange(members, pages, results, is_head)
        starts = {n: results[p]["start"] for n, p in enumerate(ordered)
                  if n > 0 and is_head[p] and results[p]["account"] is not None and results[p]["total"] is not None}
        stitched = parse(stitch([pages[p] for p in ordered], starts))
        fallback = merged([results[p] for p in ordered])
        for f in ("account", "total", "cash"):
            if stitched[f] is None: stitched[f] = fallback[f]
        # 이어 읽기가 검산을 못 맞추고 장마다 합친 것은 맞으면 그것을
        result = fallback if (closes(fallback) and not closes(stitched)) else stitched
        out.append(dict(pages=members, result=result))
    out.sort(key=lambda g: g["pages"][0])
    return out


def arrange(members, pages, results, is_head):
    """묶음 안의 차례 — 머리 장이 맨 위, 그다음은 '앞 장 아래로 겹쳐 이어지는' 장을 따라간다. 못 찾으면 고른 차례."""
    heads = [p for p in members if is_head[p]]
    chain = [heads[0] if heads else members[0]]
    rest = [p for p in members if p != chain[0]]
    while rest:
        last = chain[-1]
        # 바로 아래 장 = 겹치는 장 가운데 **가장 조금 내려간** 것(마지막 장이 끝에 맞춰 찍혀 둘 앞 장과도 겹칠 수 있다)
        follows = [(shift(pages[last], pages[p]), p) for p in rest]
        follows = [(d, p) for d, p in follows if d is not None]
        nxt = min(follows)[1] if follows else rest[0]
        chain.append(nxt); rest.remove(nxt)
    return chain


# MARK: - 검산 차이를 말로

def gap_hint(result, page_count):
    """검산이 안 맞을 때 무엇일 법한가 — ('unread', n) · ('missing', 원) · ('extra', 원) · ('drift', 원) · None."""
    if result["total"] is None: return None
    unread = sum(1 for it in result["items"] if it["value"] is None)
    if unread: return ("unread", unread)
    gap = result["total"] - expected_sum(result)
    if abs(gap) <= len(result["items"]): return None
    # 장 사이에 시세가 움직였을 만한 작은 차이 — 총액의 0.3% 안, 여러 장일 때
    if page_count > 1 and abs(gap) <= result["total"] * 0.003: return ("drift", abs(gap))
    return ("missing", gap) if gap > 0 else ("extra", -gap)
