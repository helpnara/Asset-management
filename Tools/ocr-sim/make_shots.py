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

# E. 2단 표형 (11-20 실제 화면의 배치를 본뜸 — 이름 · 숫자 · 계좌는 지어낸 것)
#    위에 메뉴 · 탭 · 계좌 줄 · 단추 줄, 이름표 | 값 의 요약표(매입금액 · 평가손익 / 평가금액 · 수익률),
#    머리줄 두 단(종목명 · 평가손익 · 평가금액 · 현재가 / 주문가능 · 보유수량 · 수익률(%) · 매입금액 · 평균단가),
#    종목마다 두 단 — 한 칸에 평가금액 위 · 매입금액 아래. 이익은 부호 없이 빨강. 맨 아래 메뉴 줄.
#    merged=True 면 오른쪽 세 칸을 한 덩어리 글자로 — 텍스트 인식이 칸을 붙여 읽을 때
def layout_e(file, rows, acct, merged=False, dark=False):
    tot = sum(r["value"] for r in rows); cost = sum(r["cost"] for r in rows); pl = tot - cost
    def signed(v): return won(v) if v >= 0 else "-" + won(-v)
    def tone(v): return "up" if v >= 0 else "down"
    cell = "padding:12px 10px;border-bottom:1px solid var(--rule);font-size:15px"
    h = ("<div style='display:flex;align-items:center;padding:6px 18px;font-size:23px;font-weight:700'><span>‹</span><span style='margin-left:14px'>내자산</span></div>"
         "<div style='display:flex;justify-content:space-around;font-size:19px;padding:12px 0;border-bottom:1px solid var(--rule)'>"
         "<span style='color:var(--mute)'>자산</span><b>국내주식</b><span style='color:var(--mute)'>해외주식</span></div>"
         f"<div style='padding:16px 20px;font-size:15px;background:var(--rule)'>{acct}</div>"
         "<div style='display:flex;gap:5px;padding:12px 12px;font-size:14px;align-items:center'><span style='margin-right:auto'>전체</span>"
         + "".join(f"<span style='border:1px solid #bbb;padding:6px 8px'>{b}</span>" for b in ["담보", "체결", "평가", "일지", "예수금"]) + "</div>"
         "<div style='display:grid;grid-template-columns:20% 30% 21% 29%;background:var(--card)'>"
         f"<span style='{cell};color:var(--mute)'>매입금액</span><span style='{cell};text-align:right'>{won(cost)}</span>"
         f"<span style='{cell};color:var(--mute)'>평가손익</span><span class={tone(pl)} style='{cell};text-align:right'>{signed(pl)}</span>"
         f"<span style='{cell};color:var(--mute)'>평가금액</span><span style='{cell};text-align:right'>{won(tot)}</span>"
         f"<span style='{cell};color:var(--mute)'>수익률(%)</span><span class={tone(pl)} style='{cell};text-align:right'>{pl / cost * 100:.2f}</span></div>"
         "<div style='display:flex;gap:10px;padding:14px 14px;font-size:15px;align-items:center'><span style='margin-right:auto'>매매비용</span>"
         "<span>통합</span><span>합산</span><span style='color:var(--mute)'>개별</span></div>")
    def two(a, b, style=""):
        return (f"<div style='display:grid;grid-template-columns:39% 61%;padding:8px 6px;font-size:13.5px;color:var(--mute);background:var(--rule)'>"
                f"<div><div style='text-align:center'>{a[0]}</div><div style='display:flex;justify-content:space-around;margin-top:8px'><span>{a[1]}</span><span>{a[2]}</span></div></div>"
                + (f"<div><div style='text-align-last:justify;padding:0 4px'>{b[0][0]} {b[0][1]} {b[0][2]}</div><div style='text-align-last:justify;margin-top:8px;padding:0 4px'>{b[1][0]} {b[1][1]} {b[1][2]}</div></div>"
                   if merged else
                   f"<div style='display:grid;grid-template-columns:1fr 1fr 1fr;text-align:center'>{''.join(f'<span>{x}</span>' for x in b[0])}"
                   f"{''.join(f'<span style=margin-top:8px>{x}</span>' for x in b[1])}</div>")
                + "</div>")
    head = two(("종목명", "주문가능", "보유수량"), (("평가손익", "평가금액", "현재가"), ("수익률(%)", "매입금액", "평균단가")))
    items = ""
    for r in rows:
        price = max(1000, round(r["value"] / r["qty"] / 10) * 10); avg = round(r["cost"] / r["qty"])
        top = (signed(r["pl"]), won(r["value"]), won(price)); bot = (f"{r['rate']:.2f}" if r["pl"] < 0 else f"{r['rate']:.2f}", won(r["cost"]), won(avg))
        right = (f"<div style='text-align-last:justify;padding:0 4px'>{' '.join(top)}</div><div style='text-align-last:justify;margin-top:8px;padding:0 4px'>{' '.join(bot)}</div>"
                 if merged else
                 f"<div style='display:grid;grid-template-columns:1fr 1fr 1fr;text-align:right;gap:0 6px'>"
                 f"<span class={tone(r['pl'])}>{top[0]}</span><span>{top[1]}</span><span class=down>{top[2]}</span>"
                 f"<span class={tone(r['pl'])} style=margin-top:8px>{bot[0]}</span><span style=margin-top:8px>{bot[1]}</span><span style=margin-top:8px>{bot[2]}</span></div>")
        items += (f"<div style='display:grid;grid-template-columns:39% 61%;padding:16px 6px;font-size:16px;border-bottom:1px solid var(--rule);background:var(--card)'>"
                  f"<div><div class=nm style='font-size:17px;padding-left:8px'>{r['name']}</div><div style='display:flex;justify-content:space-around;margin-top:10px'><span>{r['qty']:,}</span><span>{r['qty']:,}</span></div></div>"
                  f"<div>{right}</div></div>")
    nav = ("<div style='position:fixed;left:0;right:0;bottom:22px;display:flex;justify-content:space-around;font-size:13px;text-align:center;padding:10px 0;border-top:1px solid var(--rule);background:var(--card)'>"
           "<span>☰<br>메뉴</span><span>홈</span><b>국내주식<br>잔고</b><span>배당<br>플래너</span><span>이체<br>오픈뱅킹</span><span>관심<br>종목</span></div>")
    page(file, h + head + items + nav, dark)
    truth.append({"file": file, "layout": "E", "account_total": tot, "rows": rows})

# F. 묶음 목록형 (11-20 두 번째 실제 화면의 배치를 본뜸 — 이름 · 숫자는 지어낸 것)
#    맨 위 환율 줄(소수 1,352.70), 원화 · 달러 카드, 계좌 이름 아래 큰 총액, 묶음 머리(이름 −3.2%),
#    종목마다 왼쪽 아이콘(아이콘 안 작은 글자), 이름 아래 소수 수량(0.123456주), 오른쪽 평가금(크게) · 손익(작게),
#    해외 종목 원화 환산이라 총액이 합과 몇 원 다르다(반올림). 아래에 다른 구역 · 탭 막대
def layout_f(file, groups, title, rounding=2, dark=True):
    rows = [r for g in groups for r in g[1]]
    tot = sum(r["value"] for r in rows) + rounding; pl = sum(r["pl"] for r in rows)
    def signed(v): return ("+" if v >= 0 else "-") + won(abs(v))
    h = ("<div style='display:flex;align-items:center;padding:8px 18px;font-size:16px;color:var(--mute)'>달러 환율&nbsp;<span class=up>1,352.70</span>&nbsp;<span class=up style='font-size:14px'>+0.4%</span></div>"
         "<div style='display:flex;gap:10px;padding:4px 14px 18px'><div style='flex:1;padding:10px 14px;border-radius:14px;background:var(--card);font-size:16px'>652원</div>"
         "<div style='flex:1;padding:10px 14px;border-radius:14px;background:var(--card);font-size:16px'>$0.00</div></div>"
         f"<div style='padding:8px 18px'><div style='font-size:15px;font-weight:700'>{title}</div><div style='font-size:27px;font-weight:700;margin-top:6px'>{won(tot)}원 ›</div>"
         f"<div class={'up' if pl >= 0 else 'down'} style='font-size:15px;margin-top:4px'>{signed(pl)}원 ({abs(pl) / (tot - pl) * 100:.1f}%)</div></div>"
         "<div style='display:flex;align-items:center;gap:6px;padding:10px 18px;font-size:14px'><span style='margin-right:auto;padding:5px 9px;border-radius:8px;background:var(--card)'>가나다 순</span>"
         "<span style='color:var(--mute)'>현재가</span><b>평가금</b><span style='margin-left:8px'>$ 원</span></div>")
    items = ""
    for gname, grows in groups:
        g_rate = sum(r["pl"] for r in grows) / sum(r["cost"] for r in grows) * 100
        items += f"<div style='display:flex;padding:18px 18px 6px;font-size:16px'><span>{gname}</span>&nbsp;<span class={'up' if g_rate >= 0 else 'down'}>{g_rate:+.1f}%</span></div>"
        for r in grows:
            icon = r.get("icon", "")
            items += ("<div style='display:flex;align-items:center;padding:10px 18px'>"
                      f"<div style='width:40px;height:40px;border-radius:12px;background:#2a4a8a;color:#fff;font-size:10px;font-weight:700;text-align:center;line-height:1.15;padding-top:6px'>{icon}</div>"
                      f"<div style='flex:1;margin-left:14px;min-width:0'><div class=nm style='font-size:17px'>{r['name']}</div>"
                      f"<div style='font-size:13.5px;color:var(--mute);margin-top:3px'>{r['qty'] / 7:.6f}주</div></div>"
                      f"<div style='text-align:right'><div style='font-size:17px;font-weight:700'>{won(r['value'])}원</div>"
                      f"<div class={'up' if r['pl'] >= 0 else 'down'} style='font-size:13.5px;margin-top:3px'>{signed(r['pl'])} ({abs(r['rate']):.1f}%)</div></div></div>")
    items += ("<div style='display:flex;justify-content:space-around;padding:16px 18px;font-size:15px;color:var(--mute);border-top:1px solid var(--rule)'><span>⚙ 보기 설정</span><span>자세히 보기 ›</span></div>"
              "<div style='display:flex;justify-content:space-between;padding:22px 18px;font-size:17px;font-weight:700'><span>주문내역</span><span style='font-weight:500;color:var(--mute)'>이번 달 4건 ›</span></div>"
              "<div style='padding:6px 18px;font-size:17px;font-weight:700'>배당금</div>")
    nav = ("<div style='position:fixed;left:14px;right:14px;bottom:24px;display:flex;justify-content:space-around;font-size:12px;padding:10px 0;border-radius:30px;background:var(--card)'>"
           "<span>←</span><span>증권</span><span>관심</span><span>발견</span><span>시장</span></div>")
    page(file, h + items + nav, dark)
    truth.append({"file": file, "layout": "F", "account_total": tot, "rows": rows})

def us(names, k, icons=()):
    rows = holdings(names, k)
    for r, ic in zip(rows, icons): r["icon"] = ic
    return rows

US = ["ARQ", "VELT", "NOVA", "QQXM", "SPXM", "TLTX", "SOXQ", "DIVY"]

# G. 줄 셋 목록형 (11-20 셋째 실제 화면들의 배치를 본뜸 — 이름 · 숫자 · 계좌는 지어낸 것)
#    종목마다 이름 | 평가금(크게), 수량 | 손익(부호), `현재가` 또는 `현재가(장마감)` | 현재가(원 또는 Pre … USD).
#    total=False — 계좌 총액 없이 맨 위가 첫 종목(첫 종목 금액을 총액으로 잘못 보면 안 된다).
#    total=True  — 계좌 줄(증권사 이름 + 번호) · 큰 총액(= 종목 합 + 출금가능금액) · `출금가능금액 …원` · 투자내역 탭, 아래 안내 두 줄
def layout_g(file, rows, title, total=False, cash=0, us=()):
    tot = sum(r["value"] for r in rows) + cash
    h = (f"<div style='display:flex;align-items:center;padding:10px 16px;font-size:15px'><span>‹ 내 계좌</span>"
         f"<b style='margin:0 auto;font-size:18px'>{title}</b><span style='color:#1a9b4b'>관리</span></div>")
    if total:
        h += (f"<div style='padding:16px 16px 10px'><div style='font-size:14px;color:var(--mute);text-decoration:underline'>가나증권 012345678901</div>"
              f"<div style='display:flex;align-items:center;margin-top:6px'><span style='font-size:28px;font-weight:700'>{won(tot)}원</span>"
              f"<span style='margin-left:auto;background:#1a9b4b;color:#fff;padding:8px 14px;border-radius:6px;font-size:15px'>입금 &nbsp; 송금</span></div>"
              f"<div style='font-size:14px;color:var(--mute);margin-top:6px'>출금가능금액 <b style='color:var(--ink)'>{won(cash)}원</b></div></div>"
              "<div style='display:flex;font-size:16px;font-weight:700;border-bottom:1px solid var(--rule);padding:14px 0'><span style='flex:1;text-align:center'>투자내역</span>"
              "<span style='flex:1;text-align:center;color:var(--mute);font-weight:500'>거래내역</span></div>")
    h += "<div style='display:flex;justify-content:flex-end;gap:18px;padding:14px 16px;font-size:15px;color:var(--mute)'><b style='color:var(--ink)'>· 전체</b><span>주식</span><span>펀드</span><span>기타</span></div>"
    items = ""
    for r in rows:
        overseas = r["name"] in us
        price = max(1000, round(r["value"] / r["qty"] / 10) * 10)
        ptext = (f"<span style='color:var(--mute);font-size:12px'>Pre</span> {price / 1350:.2f} USD <span class=down>▼ -1.23 (-0.9%)</span>" if overseas
                 else f"{won(price)}원 <span class=down>▼ -{won(max(10, price // 20))} (-4.80%)</span>")
        qty = f"{r['qty'] / 7:.6f}주" if overseas else f"{r['qty']}주"
        items += ("<div style='margin:0 16px;padding:16px 0;border-bottom:1px solid var(--rule)'>"
                  f"<div style='display:flex;justify-content:space-between;font-size:17px;font-weight:700'><span class=nm style='max-width:55%'>{r['name']}</span><span>{won(r['value'])}원</span></div>"
                  f"<div style='display:flex;justify-content:space-between;font-size:15px;margin-top:8px'><span>{qty}</span>"
                  f"<span class={'up' if r['pl'] >= 0 else 'down'}>{'+' if r['pl'] >= 0 else '-'}{won(abs(r['pl']))}원 ({r['rate']:+.2f}%)</span></div>"
                  f"<div style='display:flex;justify-content:space-between;font-size:14px;margin-top:10px;color:var(--mute)'><span>{'현재가' if overseas else '현재가(장마감)'}</span>"
                  f"<span style='color:var(--ink)'>{ptext} ›</span></div></div>")
    if total:
        items += ("<div style='padding:14px 16px;font-size:12.5px;color:var(--mute);text-align:right;line-height:1.7'>현재가 제공 : 가나 증권 11.20 22:53<br>"
                  "외화 및 해외 종목은 오늘의 기준 환율로 계산합니다</div>")
    page(file, h + items)
    truth.append({"file": file, "layout": "G", "account_total": tot if total else None, "rows": rows})

layout_a("a1", holdings(ETF, 9), "종합매매 · 아빠 · 123-45-****")
layout_a("a2", holdings(STOCK, 9), "종합매매 · 엄마 · 234-56-****")
layout_a("a3-dark", holdings(ETF + STOCK, 9), "ISA · 아빠 · 345-67-****", dark=True)
layout_b("b1", holdings(ETF, 5), "연금저축 · 엄마 · 456-78-****")
layout_b("b2", holdings(STOCK, 5), "종합 · 아들 · 567-89-****")
layout_c("c1", holdings(ETF + STOCK, 13), "종합 · 딸 · 678-90-****")
layout_c("c2", holdings(ETF + STOCK, 13), "IRP · 아빠 · 789-01-****")
layout_d("d1", holdings(FUND, 4), "연금저축펀드 · 아빠 · 890-12-****")
layout_d("d2", holdings(FUND, 4), "IRP · 엄마 · 901-23-****")
# E — 실제 화면에서 틀린 배치. 손실 종목이 섞여(매입금액 > 평가금액) 큰 값 고르기로는 틀린다
layout_e("e1", holdings(STOCK, 3), "123-4567-8901-0 [종합_주식] 딸 일반주식")
layout_e("e2", holdings(ETF + STOCK, 5), "234-5678-9012-0 [종합_주식] 아빠 일반주식")
layout_e("e3-merged", holdings(STOCK, 4), "345-6789-0123-0 [종합_주식] 엄마 일반주식", merged=True)
layout_e("e4-dark", holdings(ETF, 4), "456-7890-1234-0 [종합_주식] 아들 일반주식", dark=True)
# F — 두 번째 실제 화면에서 본 배치. 아이콘 안 글자 · 소수 수량 · 환율 소수 · 반올림 몇 원
random.seed(7)
layout_f("f1", [("Alpha", us(US[:4], 2)), ("Core", us(US[4:], 2, ["나스닥<br>100", "S&amp;P<br>500"]))], "아무개의 투자")
layout_f("f2", [("성장", us(US[:4], 3, ["", "나스닥<br>100"])), ("배당", us(US[4:], 2, ["S&amp;P<br>500"]))], "우리집 투자", rounding=-1)
# G — 셋째 실제 화면들. 총액 없는 목록 · 현재가(장마감) 줄 · 총액에 현금이 든 계좌
random.seed(11)
g1 = holdings(US[:3], 3) + holdings(STOCK, 2)
layout_g("g1", g1, "기본계좌", us=US)
layout_g("g2", holdings(ETF, 1), "ISA(중개형)", total=True, cash=12_345)
layout_g("g3", holdings(STOCK, 3), "연금저축", total=True, cash=503_310)
for t in truth:
    for r in t["rows"]: r.pop("icon", None)
json.dump(truth, open(os.path.join(HERE, "truth.json"), "w"), ensure_ascii=False, indent=1)
print(sum(len(t["rows"]) for t in truth), "holdings in", len(truth), "screens")
