#!/usr/bin/env python3
"""Projection.run 을 파이썬으로 **독립 구현**해 Swift 테스트의 기댓값과 대조한다.

    python3 Tools/verify/projection_model.py

CLAUDE.md 규칙 — "컴파일할 수 없는 코드에 지어낸 기댓값을 넣지 않는다" — 의
반대편이다. Swift 쪽 기댓값 여섯 개를 이 스크립트가 같은 공식으로 다시 내어
전부 맞았다 (2026-09-10, docs/08-feedback.md 52번). 공식을 고치면 양쪽을
같이 고치고 여기서 다시 맞춘다.

공식: 월 성장 배수 = (1 + 연수익률)^(1/12) 을 소수 12자리로 고정 · 한 달은
적립(+목돈) → 수익 순 · 매달 은행가 반올림 · 적립액은 12개월마다 증가율만큼 ·
실질가치 = 액면가 ÷ 누적 물가 배수.
"""
from decimal import Decimal, ROUND_HALF_EVEN, getcontext
from datetime import date
getcontext().prec = 40

def rint(d):  # 은행가 반올림 정수
    return int(d.quantize(Decimal(1), rounding=ROUND_HALF_EVEN))

def monthly_factor(bp):
    if bp == 0: return Decimal(1)
    r = bp / 10000
    return Decimal("%.12f" % ((1 + r) ** (1 / 12)))

def months_between(a, b):
    m = (b.year - a.year) * 12 + (b.month - a.month)
    if b.day < a.day: m -= 1
    return m

def run(start, end, balance, monthly, return_bp, growth_bp=0, inflation_bp=0, events=()):
    months = months_between(start, end)
    g = monthly_factor(return_bp); infl = monthly_factor(inflation_bp)
    step = Decimal(1) + Decimal(growth_bp) / 10000
    ev = {}
    for d, amt in events:
        off = months_between(start, d)
        if 1 <= off <= months: ev[off] = ev.get(off, 0) + amt
    bal = balance; contrib = monthly; deflator = Decimal(1)
    for m in range(1, months + 1):
        deflator *= infl
        bal += contrib + ev.get(m, 0)
        if m % 12 == 0: contrib = rint(Decimal(contrib) * step)
        bal = rint(Decimal(bal) * g)
    real = rint(Decimal(bal) * (Decimal(1) / deflator))
    return bal, real

s = date(2026, 1, 1)
cases = [
    ("1yr 1e8 @8%", run(s, date(2027,1,1), 100_000_000, 0, 800), (107_999_999, None)),
    ("10yr +1M @8%", run(s, date(2036,1,1), 100_000_000, 1_000_000, 800), (397_175_701, None)),
    ("growth 3%", run(s, date(2036,1,1), 100_000_000, 1_000_000, 800, 300), (419_871_001, None)),
    ("real 2%", run(s, date(2036,1,1), 100_000_000, 1_000_000, 800, 0, 200), (397_175_701, 325_822_411)),
    ("event 1e8 @2027-01", run(s, date(2036,1,1), 100_000_000, 1_000_000, 800, events=[(date(2027,1,1), 100_000_000)]), (598_362_328, None)),
    ("2yr 0% 1M", run(s, date(2028,1,1), 0, 1_000_000, 0), (24_000_000, None)),
]
for name, (nom, real), (en, er) in cases:
    ok = nom == en and (er is None or real == er)
    print(f"{'OK ' if ok else 'XX '} {name}: nominal {nom:,} (expect {en:,})" + (f" real {real:,} (expect {er:,})" if er else ""))
