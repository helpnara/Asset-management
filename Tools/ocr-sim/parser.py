"""`Core/CaptureParser.swift` 를 줄 단위로 옮긴 것 (docs/25 J3). 둘을 **같이** 고친다.

리눅스에는 Swift 가 없어 앱 규칙을 여기서 먼저 채점하고, 같은 규칙을 Swift 로 옮긴다.
Line = dict(text, x, top, width, height) — 그림 크기에 대한 비율, 위에서부터.
"""
import re

LABELS = {"평가금액", "평가액", "평가금", "매입금액", "매입가", "매입단가", "수익률", "손익률", "투자원금", "종목명", "잔고",
          "체결", "손익", "평가손익", "보유", "보유수량", "주문", "주문가능", "현재가", "평균단가", "평단가", "수량", "매도가능"}
VALUE_LABELS = {"평가금액", "평가액", "평가금"}
TOTAL_LABELS = {"평가금액", "평가액", "평가금", "총평가금액", "총평가액", "총평가", "평가금액합계", "평가합계"}
NOT_VALUE_PREFIXES = ["매입", "원금", "손익", "평균", "단가", "현재가", "매수", "평단", "담보", "환율", "예수금"]
NUMBER = re.compile(r"[+\-−]?\d{1,3}(?:,\d{3})+(?:원)?")
ACCOUNT = re.compile(r"\d{2,}-\d{2,}")


def label(text):
    return re.sub(r"\(%\)|\(원\)|%|\s", "", text)


def amount_spans(text):
    """평가금액 후보가 될 금액과 그 글자 자리 [(값, 시작, 끝)]."""
    out = []
    for m in NUMBER.finditer(text):
        token = m.group(0)
        if token[0] in "+-−": continue
        after = text[m.end():m.end() + 2]
        if after[:1] in ("주", "%", "(") or re.match(r"\.\d", after): continue   # 수량 · 비율 · 손익(…%) · 소수(환율)
        before = text[max(0, m.start() - 6):m.start()]
        if any(p in before for p in NOT_VALUE_PREFIXES): continue
        out.append((int(re.sub(r"\D", "", token)), m.start(), m.end()))
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
                 width=line["width"] * (e - s) / n, height=line["height"]) for v, s, e in amount_spans(line["text"])]


def is_name(line):
    t = line["text"].strip()
    if line["x"] >= 0.5 or label(t) in LABELS: return False
    if not re.search(r"[^\W\d_]", t): return False
    if re.search(r"\d,\d{3}", t): return False                       # 매입 … · 투자원금 … · 수량 줄
    if "****" in t or t.startswith("총 ") or "평가손익" in t or ACCOUNT.search(t): return False
    if re.search(r"\d", t) and not re.sub(r"[\d\s.,+\-−%()$주원좌개]", "", t): return False   # 0.123456주 · 652원
    return True


def parse(lines):
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
    if column:
        for u in toks:
            if u["top"] >= column["top"] or label(u["text"]) not in TOTAL_LABELS: continue
            right = [a for a in placed if same_row(a, u) and a["x"] >= u["x"] + u["width"] - 0.01]
            if right:
                total = min(right, key=lambda a: a["x"])["value"]; break
    if total is None:
        limit = column["top"] if column else 0.30
        head = [l for l in rows if l["top"] < min(0.30, limit) and amounts(l["text"])]
        if head:
            total_line = max(head, key=lambda l: l["height"])
            total = amounts(total_line["text"])[0]
    start = column["start"] if column else (bottom(total_line) if total_line else -1)
    edge = column["top"] if column else (total_line["top"] if total_line else 0.30)
    account = next((l["text"] for l in rows if l["top"] < edge and ("*" in l["text"] or ACCOUNT.search(l["text"]))), None)
    if account is None and total_line:
        account = next((l["text"] for l in reversed(rows) if l["top"] < total_line["top"] and is_name(l)), None)
    body = [l for l in rows if l["top"] > start]

    # 2) 이름 — 두 줄로 꺾인 것은 붙이고, 같은 줄에 겹친 것(아이콘 안 글자)은 큰 글씨 하나만
    names = []
    for l in body:
        if not is_name(l): continue
        if names:
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
        hi = names[i + 1]["top"] - names[i + 1]["height"] * 0.6 if i + 1 < len(names) else 1.0
        if column:
            def in_column(a):
                nearest = min(column["block"], key=lambda u: abs(cx(u) - cx(a)))
                return abs(cx(nearest) - column["x"]) < column["tolerance"]
            cands = sorted([a for a in placed if lo <= a["top"] < hi and in_column(a)], key=lambda a: a["top"])
            if not cands: continue
            value = cands[column["rank"]]["value"] if len(cands) > column["rank"] else None
        else:
            band = [l for l in body if lo <= l["top"] < hi and l is not n]
            cands = [(l, v) for l in band if l["x"] > 0.25 for v in amounts(l["text"])]
            if not cands: continue
            mark = next((l for l in band if label(l["text"]) in VALUE_LABELS), None)
            if mark:
                cands.sort(key=lambda lv: abs(cy(lv[0]) - cy(mark)))
            else:
                cands.sort(key=lambda lv: (-lv[0]["height"], -lv[1]))
            value = cands[0][1]
        items.append(dict(name=n["text"], value=value))
    return dict(account=account, total=total, items=items)


def is_balanced(result):
    """검산 — 합 = 총액. 해외 종목은 원화 환산 반올림으로 몇 원 다를 수 있어 종목 수만큼(원) 봐준다."""
    if result["total"] is None: return None
    if any(i["value"] is None for i in result["items"]) or not result["items"]: return False
    return abs(result["total"] - sum(i["value"] for i in result["items"])) <= len(result["items"])
