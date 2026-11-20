"""증권사 보유 종목 화면을 닮은 **가상** 캡처를 만든다 (docs/25 — J3 OCR 시뮬레이션).

실제 증권사 디자인 · 이름 · 로고를 흉내 내지 않는다. 종목명 · 금액은 모두 지어낸 것이다.
배치는 흔한 네 가지(목록형 · 카드형 · 표형 · 펀드형) + 다크 모드. 1206×2622 (iPhone @3x).
정답은 truth.json 에 남긴다. 사용: python3 make_shots.py  → shots/*.html, truth.json
"""
import json, random, os
random.seed(20261120)
HERE = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(HERE, "shots"), exist_ok=True)

ETF = ["ARIA 미국S&P500", "VEGA 미국나스닥100", "ORBIT 200", "KAPPA 미국배당다우존스", "ARIA 차이나전기차SOLACTIVE",
       "VEGA 2차전지산업", "ORBIT 미국30년국채액티브(H)", "KAPPA 골드선물(H)", "ARIA 코스닥150", "VEGA 미국테크TOP10",
       "ORBIT 단기채권액티브", "KAPPA 반도체TOP10", "ARIA 미국S&P500TR", "VEGA 인도니프티50"]
STOCK = ["가나전자", "다라화학", "마바바이오로직스", "사아금융지주", "자차중공업", "카타에너지솔루션", "파하모빌리티",
         "가온소프트", "누리엔터", "다올제약", "로이반도체", "미르건설", "새솔통신", "온빛식품"]
FUND = ["하늘자산 TDF 2045 증권투자신탁(주식혼합-재간접형) C-Pe", "누리자산 글로벌인컴 증권자투자신탁[채권혼합] C-P2e",
        "바다자산 미국성장주 증권자투자신탁(주식) 종류C-Pe", "하늘자산 TDF 2050 증권투자신탁(주식혼합-재간접형) C-Pe",
        "누리자산 코리아배당 증권투자신탁(주식) C-Pe", "바다자산 단기채 증권투자신탁(채권) Ce"]

def amount():
    # 자릿수가 고루 섞이게: 30만 ~ 1.5억, 헷갈리기 쉬운 숫자(1 7 · 0 8 · 5 6)가 자주 나오게 그대로 둔다
    return random.choice([random.randint(300_000, 3_000_000), random.randint(3_000_000, 30_000_000),
                          random.randint(30_000_000, 150_000_000)])

def won(v): return f"{v:,}"

def holdings(names, k):
    rows = []
    for n in random.sample(names, k):
        val = amount()
        cost = int(val / (1 + random.uniform(-0.25, 0.35)))
        rows.append({"name": n, "value": val, "cost": cost, "pl": val - cost,
                     "rate": (val - cost) / cost * 100, "qty": random.randint(1, 2400)})
    return rows

CSS = """@font-face{font-family:P;src:url('../../promo/fonts/Pretendard-Medium.woff2');font-weight:500}
@font-face{font-family:P;src:url('../../promo/fonts/Pretendard-Bold.woff2');font-weight:700}
*{box-sizing:border-box;margin:0;padding:0} body{width:402px;height:874px;overflow:hidden;font-family:P,sans-serif;
background:var(--bg);color:var(--ink)} :root{--bg:#f4f5f7;--card:#fff;--ink:#16181d;--mute:#7b818c;--up:#e0353b;--down:#2f6fe4;--rule:#eceef1}
.dark{--bg:#111215;--card:#1c1e23;--ink:#eef0f3;--mute:#8b919c;--rule:#2a2d33}
.status{height:54px;display:flex;align-items:center;justify-content:space-between;padding:0 30px;font-weight:700;font-size:16px}
.top{padding:6px 20px 14px} .acct{font-size:13px;color:var(--mute)} .total{font-size:28px;font-weight:700;margin-top:4px}
.sub{font-size:13px;color:var(--mute);margin-top:4px} .tabs{display:flex;gap:18px;padding:0 20px 10px;font-size:15px;color:var(--mute)}
.tabs b{color:var(--ink)} .up{color:var(--up)} .down{color:var(--down)}
.nm{white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
"""
truth = []

def page(file, body, dark=False):
    html = f"<!doctype html><meta charset=utf-8><style>{CSS}</style><body class='{'dark' if dark else ''}'>" \
           f"<div class=status><span>9:41</span><span>●●● ▮</span></div>{body}</body>"
    open(os.path.join(HERE, "shots", file + ".html"), "w").write(html)

def header(acct, rows, label="총 평가금액"):
    tot = sum(r["value"] for r in rows)
    pl = sum(r["pl"] for r in rows)
    c = "up" if pl >= 0 else "down"
    return tot, (f"<div class=top><div class=acct>{acct}</div><div class=total>{won(tot)}원</div>"
                 f"<div class=sub>{label} · 평가손익 <span class={c}>{'+' if pl>=0 else ''}{won(pl)}</span></div></div>"
                 f"<div class=tabs><b>잔고</b><span>체결</span><span>손익</span></div>")

def sign(r): return ("up" if r["pl"] >= 0 else "down"), ("+" if r["pl"] >= 0 else "")

# A. 목록형 — 이름 | 평가금액(크게), 아래 수량 · 수익률 · 평가손익(작게)
def layout_a(file, rows, acct, dark=False):
    tot, h = header(acct, rows)
    items = ""
    for r in rows:
        c, s = sign(r)
        items += (f"<div style='display:flex;justify-content:space-between;padding:13px 20px;border-bottom:1px solid var(--rule);background:var(--card)'>"
                  f"<div style='min-width:0;max-width:56%'><div class='nm' style='font-size:16px;font-weight:700'>{r['name']}</div>"
                  f"<div style='font-size:12.5px;color:var(--mute);margin-top:4px'>{r['qty']:,}주 · 매입 {won(r['cost'])}</div></div>"
                  f"<div style='text-align:right'><div style='font-size:16px;font-weight:700'>{won(r['value'])}원</div>"
                  f"<div class={c} style='font-size:12.5px;margin-top:4px'>{s}{won(r['pl'])} ({s}{r['rate']:.2f}%)</div></div></div>")
    page(file, h + items, dark)
    truth.append({"file": file, "layout": "A", "account_total": tot, "rows": rows})

# B. 카드형 — 이름 위, 아래에 라벨 붙은 줄들 (평가금액 · 매입금액 · 수익률)
def layout_b(file, rows, acct):
    tot, h = header(acct, rows)
    items = ""
    for r in rows:
        c, s = sign(r)
        items += (f"<div style='margin:0 14px 10px;padding:14px 16px;border-radius:14px;background:var(--card)'>"
                  f"<div class=nm style='font-size:15.5px;font-weight:700;margin-bottom:8px'>{r['name']}</div>"
                  + "".join(f"<div style='display:flex;justify-content:space-between;font-size:13.5px;margin-top:3px'><span style='color:var(--mute)'>{k}</span><span {a}>{v}</span></div>"
                            for k, v, a in [("평가금액", won(r['value']) + "원", "style='font-weight:700'"),
                                            ("매입금액", won(r['cost']) + "원", ""),
                                            ("수익률", f"{s}{r['rate']:.2f}%", f"class={c}")]) + "</div>")
    page(file, h + items)
    truth.append({"file": file, "layout": "B", "account_total": tot, "rows": rows})

# C. 표형 — 머리줄(종목명 · 평가금액 · 수익률), 작은 글씨, '원' 없음
def layout_c(file, rows, acct):
    tot, h = header(acct, rows)
    items = ("<div style='display:flex;padding:8px 16px;font-size:12px;color:var(--mute);border-bottom:1px solid var(--rule)'>"
             "<span style='flex:1'>종목명</span><span style='width:110px;text-align:right'>평가금액</span><span style='width:70px;text-align:right'>수익률</span></div>")
    for r in rows:
        c, s = sign(r)
        items += (f"<div style='display:flex;align-items:center;padding:10px 16px;font-size:13.5px;border-bottom:1px solid var(--rule);background:var(--card)'>"
                  f"<span class=nm style='flex:1;min-width:0'>{r['name']}</span><span style='width:110px;text-align:right;font-weight:700'>{won(r['value'])}</span>"
                  f"<span class={c} style='width:70px;text-align:right'>{s}{r['rate']:.2f}%</span></div>")
    page(file, h + items)
    truth.append({"file": file, "layout": "C", "account_total": tot, "rows": rows})

# D. 펀드형 — 긴 이름 두 줄, 평가금액과 원금
def layout_d(file, rows, acct):
    tot, h = header(acct, rows, "총 평가금액(세전)")
    items = ""
    for r in rows:
        c, s = sign(r)
        items += (f"<div style='margin:0 14px 10px;padding:14px 16px;border-radius:14px;background:var(--card)'>"
                  f"<div style='font-size:15px;font-weight:700;line-height:1.35'>{r['name']}</div>"
                  f"<div style='display:flex;justify-content:space-between;align-items:baseline;margin-top:8px'><span style='font-size:13px;color:var(--mute)'>평가금액</span>"
                  f"<span style='font-size:18px;font-weight:700'>{won(r['value'])}원</span></div>"
                  f"<div style='display:flex;justify-content:space-between;font-size:13px;margin-top:3px;color:var(--mute)'><span>투자원금 {won(r['cost'])}원</span>"
                  f"<span class={c}>{s}{r['rate']:.2f}%</span></div></div>")
    page(file, h + items)
    truth.append({"file": file, "layout": "D", "account_total": tot, "rows": rows})

layout_a("a1", holdings(ETF, 9), "종합매매 · 아빠 · 123-45-****")
layout_a("a2", holdings(STOCK, 9), "종합매매 · 엄마 · 234-56-****")
layout_a("a3-dark", holdings(ETF + STOCK, 9), "ISA · 아빠 · 345-67-****", dark=True)
layout_b("b1", holdings(ETF, 5), "연금저축 · 엄마 · 456-78-****")
layout_b("b2", holdings(STOCK, 5), "종합 · 아들 · 567-89-****")
layout_c("c1", holdings(ETF + STOCK, 13), "종합 · 딸 · 678-90-****")
layout_c("c2", holdings(ETF + STOCK, 13), "IRP · 아빠 · 789-01-****")
layout_d("d1", holdings(FUND, 4), "연금저축펀드 · 아빠 · 890-12-****")
layout_d("d2", holdings(FUND, 4), "IRP · 엄마 · 901-23-****")
json.dump(truth, open(os.path.join(HERE, "truth.json"), "w"), ensure_ascii=False, indent=1)
print(sum(len(t["rows"]) for t in truth), "holdings in", len(truth), "screens")
