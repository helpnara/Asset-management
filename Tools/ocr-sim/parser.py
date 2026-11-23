"""`Core/CaptureParser.swift` 를 줄 단위로 옮긴 것 (docs/25 J3). 둘을 **같이** 고친다.

리눅스에는 Swift 가 없어 앱 규칙을 여기서 먼저 채점하고, 같은 규칙을 Swift 로 옮긴다.
Line = dict(text, x, top, width, height) — 그림 크기에 대한 비율, 위에서부터.
"""
import re

LABELS = {"평가금액", "평가액", "평가금", "매입금액", "매입가", "매입단가", "수익률", "손익률", "투자원금", "종목명", "잔고",
          "체결", "손익", "평가손익", "보유", "보유수량", "주문", "주문가능", "현재가", "평균단가", "평단가", "수량", "매도가능"}
VALUE_LABELS = {"평가금액", "평가액", "평가금"}
TOTAL_LABELS = {"평가금액", "평가액", "평가금", "총평가금액", "총평가액", "총평가", "평가금액합계", "평가합계"}
# 계좌 총액 이름표 — `자산 43,491 원` 처럼 총액 옆에 붙는 말. 종목 이름이 아니다 (228번)
ASSET_WORDS = {"자산", "총자산", "순자산", "추정자산", "예탁자산", "총예탁자산", "추정예탁자산", "평가자산", "총평가자산"}
LABELS |= ASSET_WORDS
TOTAL_LABELS |= ASSET_WORDS
NOT_VALUE_PREFIXES = ["매입", "원금", "손익", "평균", "단가", "현재가", "매수", "평단", "담보", "환율", "예수금", "출금", "가능금액"]
CASH_WORDS = ["출금가능", "예수금", "주문가능현금"]
# 총액에서 빠진 비용 — 화면 총액이 '팔면 받을 돈'(수수료 · 세금을 뺀 값)일 때 (227번)
FEE_WORDS = ["수수료", "제세금", "매도비용", "예상비용", "제비용"]
SIGNS = "+-−‐‑‒–—―﹣－"   # 텍스트 인식이 마이너스를 여러 줄표로 읽는다 (11-21 `–7,4xx,xxx` 가 부호 없는 금액이 됨)
NUMBER = re.compile(r"[" + re.escape(SIGNS) + r"]?\d{1,3}(?:,\d{3})+(?:원)?")
ACCOUNT = re.compile(r"\d{2,}-\d{2,}")


def plain(text):
    """빈칸만 걷는다 — 괄호 안도 남긴다(`현금잔고(예수금)` 의 예수금, 228번)."""
    return re.sub(r"\s", "", text)


def money_word(text):
    """현금 · 비용 줄인가 — 종목이 아니라 총액이 품거나 뺀 돈."""
    return any(w in plain(text) for w in CASH_WORDS + FEE_WORDS)


def loose_amount(text, signed=False):
    """쉼표 없는 작은 금액까지(`491원`) — 현금 · 비용 칸에서만. 수량 · 비율 · 손익 괄호 · 소수는 뺀다."""
    t = digits_fixed(text)
    for m in re.finditer(r"(?<![\d,.])([" + re.escape(SIGNS) + r"]?)(\d{1,3}(?:,\d{3})*)(?![\d,.%(]|\s?%|\s?주)", t):
        if m.group(1) and not signed: continue
        return int(m.group(2).replace(",", ""))
    return None


def label(text):
    """이름표 비교용 — 괄호 안(`(%)` · `(장마감)`) · % · 빈칸을 걷는다."""
    return re.sub(r"\([^)]*\)|%|\s", "", text)


def digits_fixed(text):
    """숫자 사이에 낀 닮은 글자를 숫자로 — 텍스트 인식이 굵은 1 을 l · I 로, 0 을 O 로 읽을 때. 길이는 그대로."""
    text = re.sub(r"(?<=[\d,])[lI|](?=[\d,원]|$)", "1", text)
    text = re.sub(r"(?<=[\d,])[Oo](?=[\d,원]|$)", "0", text)
    text = re.sub(r"(?<=\d)B(?=[\d,원]|$)", "8", text)
    # 쉼표 뒤 빈칸 — `250, 001원` 을 `250,001 원` 으로(빈칸을 뒤로 옮겨 길이는 그대로). 11-21 SPYM 을 놓친 일
    return re.sub(r"(\d),\s(\d{3})(?!\d)", r"\1,\2 ", text)


def amount_spans(text):
    """평가금액 후보가 될 금액과 그 글자 자리 [(값, 시작, 끝)]."""
    out = []
    text = digits_fixed(text)
    for m in NUMBER.finditer(text):
        token = m.group(0)
        if token[0] in SIGNS: continue
        value, end = int(re.sub(r"\D", "", token)), m.end()
        # 금액 바로 뒤에 숫자가 붙어 있다 — 쉼표 하나를 빠뜨리고 읽은 것(`10,8xx0xx`, 11-21 딸 계좌 총액).
        # 정확히 세 자리면 빠진 쉼표로 보고 붙이고, 아니면 망가진 숫자라 고르지 않는다(앞부분만 고르면 틀린 값이 된다).
        if not token.endswith("원") and re.match(r"\d", text[end:end + 1]):
            tail = re.match(r"\d{3}(?!\d)", text[end:])
            if not tail: continue
            value, end = value * 1000 + int(tail.group(0)), end + 3
        after = text[end:end + 2]
        if re.match(r"\s?\(", text[end:end + 3]): continue          # `금액 (12.4%)` — 손익과 비율
        if after[:1] in ("주", "%", "(") or re.match(r"\.\d", after): continue   # 수량 · 비율 · 손익(…%) · 소수(환율)
        if after[:1] == ",": continue                                    # 쉼표 뒤가 끊긴 숫자 — 덜 읽은 것은 고르지 않는다
        before = text[max(0, m.start() - 6):m.start()]
        if any(p in before for p in NOT_VALUE_PREFIXES): continue
        out.append((value, m.start(), end))
    return out


def amounts(text):
    return [v for v, _, _ in amount_spans(text)]


def bottom(l): return l["top"] + l["height"]
def cy(l): return l["top"] + l["height"] / 2
def cx(l): return l["x"] + l["width"] / 2
def same_row(a, b): return abs(cy(a) - cy(b)) < max(a["height"], b["height"]) * 0.6


def tokens(line):
    """줄을 빈칸으로 나눈 낱말 — 자리는 글자 수 비율로 어림한다(텍스트 인식이 칸을 붙여 읽을 때)."""
    n = max(1, len(line["text"]))
    return [dict(text=m.group(0), x=line["x"] + line["width"] * m.start() / n, top=line["top"],
                 width=line["width"] * (m.end() - m.start()) / n, height=line["height"])
            for m in re.finditer(r"\S+", line["text"])]


def placed_amounts(line):
    n = max(1, len(line["text"]))
    return [dict(value=v, x=line["x"] + line["width"] * s / n, top=line["top"],
                 width=line["width"] * (e - s) / n, height=line["height"], line=line, end=e)
            for v, s, e in amount_spans(line["text"])]


TAIL = re.compile(r"[ ,.]\d{3}(?![\d,.주%(])")


def with_tail(value, line, end, right_edge, rows):
    """**총액의 끝 세 자리가 떨어져 읽혔을 때 붙인다** (11-21 빌드 152 — `10,833,023` 을 `10,833` 으로).
    텍스트 인식이 마지막 쉼표를 빈칸 · 점으로 읽거나(`10,833 023`), 끝 묶음을 따로 읽었을 때(`10,833` | `023`).
    총액에만 쓴다 — 표의 한 줄에서는 이웃 칸의 세 자리 숫자를 잘못 붙일 수 있다."""
    text = digits_fixed(line["text"])
    m = TAIL.match(text, end)
    if m: return value * 1000 + int(m.group(0)[1:])
    for l in rows:
        if l is line or not same_row(l, line): continue
        if right_edge - 0.005 <= l["x"] <= right_edge + 0.04 and re.fullmatch(r"[,.]?\d{3}(원)?", l["text"].strip()):
            return value * 1000 + int(re.sub(r"\D", "", l["text"]))
    return value


def line_values(line, rows):
    """**목록형 종목 줄의 금액** — 끝 세 자리가 떨어져 읽혔으면 붙인다 (QQQM 이 `31,574` 로 읽힌 일, 11-21).
    `31,574 138원`(마지막 쉼표를 빈칸으로) · `31,574,` | `138원`(끝 묶음을 따로). 표의 열 고르기(머리줄)에는 쓰지 않는다 —
    표에서는 이웃 칸의 숫자가 같은 줄에 붙어 읽힐 수 있다. 목록형은 금액 칸이 줄 끝에 홀로 있다."""
    text = line["text"]; n = max(1, len(text))
    out = [with_tail(v, line, e, line["x"] + line["width"] * e / n, rows) for v, _, e in amount_spans(text)]
    if not out:
        m = re.fullmatch(r"(\d{1,3}(?:,\d{3})+)[,.]", digits_fixed(text).strip())
        if m:
            value = int(m.group(1).replace(",", ""))
            joined = with_tail(value, line, len(text), line["x"] + line["width"], rows)
            if joined != value: out.append(joined)
    return out


def is_name(line):
    t = line["text"].strip()
    if line["x"] >= 0.5 or label(t) in LABELS: return False
    if not re.search(r"[^\W\d_]", t): return False
    if re.search(r"\d,\d{3}", t): return False                       # 매입 … · 투자원금 … · 수량 줄
    if "****" in t or t.startswith("총 ") or "평가손익" in t or ACCOUNT.search(t): return False
    if money_word(t): return False   # 현금 · 비용 줄은 종목이 아니다 (227번 · 228번 괄호 안까지)
    if re.fullmatch(r"[가-힣ㄱ-ㆎ]", t): return False                  # 한 글자 한글 · 낱자 — 가려진 글자 · 아이콘 조각(`트` · `ㅧ`)
    if re.search(r"\d", t) and not re.sub(r"[\d\s.,+\-−%()$주원좌개]", "", t): return False   # 0.123456주 · 652원
    # 숫자 + 글자 한 자 — 단위를 잘못 읽어도(3.123456수) 이름이 아니다. 소수거나 세 자리 이상일 때만(3M 같은 이름은 남긴다)
    if re.fullmatch(r"[+\-−]?\d[\d,.]*\s*[^\d\s]?", t) and ("." in t or len(re.findall(r"\d", t)) >= 3): return False
    return True


def parse(lines, find_total=True):
    rows = sorted(lines, key=lambda l: (l["top"], l["x"]))
    toks = sorted([t for l in rows for t in tokens(l)], key=lambda t: (t["top"], t["x"]))
    placed = [a for l in rows for a in placed_amounts(l)]

    # 0) 표 머리줄 — `평가금액` 과 같은 줄이 모두 이름표(셋 이상)
    def label_row(t): return all(label(u["text"]) in LABELS for u in toks if same_row(u, t))
    header = next((t for t in toks if label(t["text"]) in VALUE_LABELS
                   and sum(1 for u in toks if same_row(u, t)) >= 3 and label_row(t)), None)
    column = None
    if header:
        block = [u for u in toks if header["top"] - header["height"] * 0.5 <= u["top"] <= header["top"] + header["height"] * 3
                 and label(u["text"]) in LABELS and label_row(u)]
        tolerance = max(header["width"] * 0.5, 0.03)
        stacked = sorted([u for u in block if abs(cx(u) - cx(header)) < tolerance], key=lambda u: u["top"])
        rank = sum(1 for u in stacked if u["top"] < header["top"] - header["height"] * 0.3)
        column = dict(block=block, centers=[cx(u) for u in block], x=cx(header), tolerance=tolerance, rank=rank,
                      start=max(bottom(u) for u in block), top=header["top"] - header["height"] * 0.5)

    # 1) 계좌 총액 — 표가 있으면 머리줄 위 `평가금액` 같은 이름표 오른쪽의 금액, 없으면 위쪽 30% 의 가장 큰 글씨
    total, total_line = None, None
    if column and find_total:
        for u in toks:
            if u["top"] >= column["top"] or label(u["text"]) not in TOTAL_LABELS: continue
            right = [a for a in placed if same_row(a, u) and a["x"] >= u["x"] + u["width"] - 0.01]
            if right:
                a = min(right, key=lambda a: a["x"])
                total = with_tail(a["value"], a["line"], a["end"], a["x"] + a["width"], rows); break
    if total is None and find_total:
        # 총액 자리 — 위쪽 30%, 또는 **첫 종목 줄 위까지**(그게 더 아래면). 토스처럼 맨 위에 계좌 탭 · 원화 · 달러 카드가
        # 있으면 총액이 37% 쯤에 온다(11-21). 첫 종목 줄 = 같은 줄 오른쪽에 금액이 있는 이름 줄.
        item_tops = [l["top"] for l in rows if is_name(l)
                     and any(m is not l and same_row(m, l) and m["x"] > 0.5 and amounts(m["text"]) for m in rows)]
        reach = max(0.30, min(item_tops)) if item_tops else 0.30
        limit = column["top"] if column else reach
        head = [l for l in rows if l["top"] < min(reach, limit) and amounts(l["text"])
                and not any(m is not l and same_row(m, l) and is_name(m) for m in rows)]   # 첫 종목의 금액은 총액이 아니다
        if head:
            total_line = max(head, key=lambda l: l["height"])
            value, _, end = amount_spans(total_line["text"])[0]
            right = total_line["x"] + total_line["width"] * end / max(1, len(total_line["text"]))
            total = with_tail(value, total_line, end, right, rows)
    start = column["start"] if column else (bottom(total_line) if total_line else -1)
    edge = column["top"] if column else (total_line["top"] if total_line else 0.30)
    account = next((l["text"] for l in rows if l["top"] < edge and ("*" in l["text"] or ACCOUNT.search(l["text"]))), None)
    if account is None and total_line:
        account = next((l["text"] for l in reversed(rows) if l["top"] < total_line["top"] and is_name(l)), None)
    body = [l for l in rows if l["top"] > start]
    # 현금(출금가능 · 예수금) — 그 이름표 줄이나 같은 줄 오른쪽의 금액. 화면 총액이 현금을 품을 때 검산에 쓴다
    def unsigned(text):
        return next((int(re.sub(r"\D", "", m.group(0))) for m in NUMBER.finditer(digits_fixed(text)) if m.group(0)[0] not in SIGNS), None)
    cash = None
    for l in rows:
        if not any(w in plain(l["text"]) for w in CASH_WORDS): continue
        cash = unsigned(l["text"])
        if cash is None:
            right = sorted([m for m in rows if m is not l and same_row(m, l) and m["x"] > l["x"] and unsigned(m["text"]) is not None],
                           key=lambda m: m["x"])
            cash = unsigned(right[0]["text"]) if right else None
        if cash is not None: break
    # 비용(수수료 · 제세금 · 예상매도비용) — 현금과 같은 자리에서, 부호(−)가 붙어 있어도 크기만
    def any_amount(text):
        return next((int(re.sub(r"\D", "", m.group(0))) for m in NUMBER.finditer(digits_fixed(text))), None)
    fee = None
    for l in rows:
        if not any(w in plain(l["text"]) for w in FEE_WORDS): continue
        fee = any_amount(l["text"])
        if fee is None:
            right = sorted([m for m in rows if m is not l and same_row(m, l) and m["x"] > l["x"] and any_amount(m["text"]) is not None],
                           key=lambda m: m["x"])
            fee = any_amount(right[0]["text"]) if right else None
        if fee is not None: break

    # 2) 이름 — 두 줄로 꺾인 것은 붙이고, 같은 줄에 겹친 것(아이콘 안 글자)은 큰 글씨 하나만
    # 현금 · 비용 이름표만 있는 줄(`현금잔고(예수금)` — 금액은 아래 줄)도 자리를 잡아 둔다: 앞 종목의 금액 칸이 거기서 끝나고,
    # 그 아래 금액은 현금 · 비용으로 읽는다(228번). 금액이 같은 줄에 있는 현금 줄은 위에서 이미 읽었다
    def money_label(l):
        return l["x"] < 0.5 and money_word(l["text"]) and not re.search(r"\d,\d{3}", l["text"])
    names = []
    for l in body:
        if money_label(l):
            names.append(dict(l, kind="fee" if any(w in plain(l["text"]) for w in FEE_WORDS) else "cash")); continue
        if not is_name(l): continue
        if names and not names[-1].get("kind"):
            p = names[-1]
            gap = l["top"] - bottom(p)
            if abs(l["x"] - p["x"]) < 0.02 and 0 < gap < p["height"] * 0.9:
                names[-1] = dict(text=p["text"] + " " + l["text"], x=p["x"], top=p["top"],
                                 width=max(p["width"], l["width"]), height=bottom(l) - p["top"]); continue
            if same_row(l, p):
                if l["height"] > p["height"]: names[-1] = dict(l)
                continue
        names.append(dict(l))

    # 3) 이름마다 평가금액. 금액이 하나도 없는 이름(메뉴 · 탭 · 묶음 머리)은 종목이 아니다
    items = []
    for i, n in enumerate(names):
        lo = n["top"] - n["height"] * 0.6
        # 마지막 이름은 끝까지 — 이어 붙인 여러 장(226번)은 1 을 넘는다
        hi = names[i + 1]["top"] - names[i + 1]["height"] * 0.6 if i + 1 < len(names) else float("inf")
        if n.get("kind"):
            band = sorted([l for l in body if lo <= l["top"] < hi and l is not n and l["x"] > 0.25], key=lambda l: (l["top"], l["x"]))
            value = next((v for l in band if (v := loose_amount(l["text"], signed=n["kind"] == "fee")) is not None), None)
            if n["kind"] == "cash" and cash is None: cash = value
            if n["kind"] == "fee" and fee is None: fee = value
            continue
        if column:
            def in_column(a):
                nearest = min(column["block"], key=lambda u: abs(cx(u) - cx(a)))
                return abs(cx(nearest) - column["x"]) < column["tolerance"]
            cands = sorted([a for a in placed if lo <= a["top"] < hi and in_column(a)], key=lambda a: a["top"])
            if not cands: continue
            value = cands[column["rank"]]["value"] if len(cands) > column["rank"] else None
        else:
            band = [l for l in body if lo <= l["top"] < hi and l is not n]
            def other_label_left(l):
                return any(same_row(m, l) and m["x"] < l["x"] and label(m["text"]) in LABELS - VALUE_LABELS for m in rows)
            cands = [(l, v) for l in band if l["x"] > 0.25 and not other_label_left(l) for v in line_values(l, rows)]
            if not cands: continue
            mark = next((l for l in band if label(l["text"]) in VALUE_LABELS), None)
            if mark:
                cands.sort(key=lambda lv: abs(cy(lv[0]) - cy(mark)))
            else:
                cands.sort(key=lambda lv: (-lv[0]["height"], -lv[1]))
            value = cands[0][1]
        items.append(dict(name=n["text"], value=value))
    # 총액이 가장 큰 종목보다 작을 수는 없다 — 잘못 읽은 총액으로 검산하지 않는다(총액 없음으로)
    # 머리 없는 장(아래로 넘겨 찍은 장)에서 종목 금액을 총액으로 잡은 것이다 — 그 줄을 머리로 삼아 계좌 줄 · 본문 시작까지
    # 틀렸으니(위쪽 종목이 빠지고 종목 이름이 계좌 줄이 된다, 226번) **총액 없이 처음부터 다시 읽는다**
    values = [i["value"] for i in items if i["value"] is not None]
    if total is not None and values and total < max(values):
        return parse(lines, find_total=False)
    # start = 본문이 시작되는 자리(머리 아래 끝) — 여러 장을 이을 때 둘째 장부터의 머리를 버리는 데 쓴다(226번)
    return dict(account=account, total=total, items=items, cash=cash, fee=fee, start=start)


def is_balanced(result):
    """검산 — 합 = 총액. 해외 종목은 원화 환산 반올림으로 몇 원 다를 수 있어 종목 수만큼(원) 봐준다."""
    if result["total"] is None: return None
    if any(i["value"] is None for i in result["items"]) or not result["items"]: return False
    return abs(result["total"] - expected_sum(result)) <= len(result["items"])


def applied(result):
    """총액이 품은 것 — (현금, 비용). 화면에 적힌 현금 · 비용을 더하고 빼서 총액과 맞는 조합이 있으면 그것 (227번)."""
    s = sum(i["value"] or 0 for i in result["items"])
    cash, fee, total = result.get("cash"), result.get("fee"), result["total"]
    if total is None: return None, None
    combos = ([(cash, None)] if cash is not None else []) + ([(None, fee)] if fee is not None else []) \
        + ([(cash, fee)] if cash is not None and fee is not None else [])
    for c, f in combos:
        if abs(total - (s + (c or 0) - (f or 0))) <= len(result["items"]): return c, f
    return None, None


def expected_sum(result):
    """총액과 견줄 합 — 화면 총액이 현금(출금가능 · 예수금)을 품었거나 비용(수수료 · 세금)을 뺐으면 그것까지."""
    s = sum(i["value"] or 0 for i in result["items"])
    c, f = applied(result)
    return s + (c or 0) - (f or 0)


# 이름 맞추기 — Swift `match(_:among:)` 와 같다

def normalized(name):
    return re.sub(r"\s", "", name.replace("...", "…").replace("…", "")).lower()


def similarity(a, b):
    if not a and not b: return 1.0
    if not a or not b: return 0.0
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] != b[j - 1]))
        prev = cur
    return 1 - prev[len(b)] / max(len(a), len(b))


def match(read, candidates):
    """잘린 이름(…)은 앞부분이 맞는 하나 → 앱 이름이 읽은 긴 이름 속에 든 것(가장 긴 것) → 가장 비슷한 것(0.6 이상)."""
    clean = normalized(read)
    if not clean: return None
    prefix = clean[:max(4, len(clean) - 1)]
    prefixed = [i for i, c in enumerate(candidates) if normalized(c).startswith(prefix)]
    if len(prefixed) == 1: return prefixed[0], 1.0
    inside = [i for i, c in enumerate(candidates) if len(normalized(c)) >= 4 and normalized(c) in clean]
    if inside: return max(inside, key=lambda i: len(normalized(candidates[i]))), 0.9
    scored = [(i, similarity(clean, normalized(c))) for i, c in enumerate(candidates)]
    if not scored: return None
    best = max(scored, key=lambda t: t[1])
    return best if best[1] >= 0.6 else None
