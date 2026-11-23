"""**한 계좌가 여러 장으로 나뉘는** 가상 캡처 (226번). `make_shots.py` 의 배치를 길게 늘려 스크롤하며 찍는다.

- 상태 막대는 늘 위에 붙어 있고(`sticky`), 아래 탭 막대도 그대로(`fixed`) — 장마다 같은 자리에 되풀이된다
- `m-sticky` 는 계좌 줄 · 총액 머리가 스크롤해도 위에 남는 앱(머리가 장마다 되풀이)
- 이름 · 숫자는 모두 지어낸 것. 출력: shots/m-*.html, long_truth.json → `node long_lines.mjs` → long.jsonl
"""
import json, os, random

HERE = os.path.dirname(os.path.abspath(__file__))
# make_shots 를 불러오면 shots/ · truth.json 을 다시 쓴다 — 그림은 같은 씨앗이라 그대로지만, truth.json 의
# `visible` 은 render.mjs 가 나중에 붙인 것이라 지워진다. 읽어 두었다가 되돌린다.
saved = open(os.path.join(HERE, "truth.json")).read()
import make_shots as ms
open(os.path.join(HERE, "truth.json"), "w").write(saved)
start = len(ms.truth)
random.seed(226)

def longify(file, sticky_head=False):
    path = os.path.join(HERE, "shots", file + ".html")
    html = open(path).read()
    html = html.replace("height:874px;overflow:hidden", "min-height:874px")
    # 실제 앱처럼 맨 끝 줄이 아래 탭 막대에 가리지 않게 아래 여백
    extra = ".status{position:sticky;top:0;z-index:5;background:var(--bg)} body{padding-bottom:110px}"
    if sticky_head:
        extra += ".top{position:sticky;top:54px;z-index:4;background:var(--bg)}"
    html = html.replace("</style>", extra + "</style>", 1)
    open(path, "w").write(html)

# 목록형 24종목 — 세 장
ms.layout_a("m-list", ms.holdings(ms.ETF + ms.STOCK, 24), "종합매매 · 엄마 · 135-79-****")
longify("m-list")
# 2단 표형 12종목 — 머리줄은 첫 장에만
ms.layout_e("m-table", ms.holdings(ms.ETF + ms.STOCK, 12), "567-8901-2345-0 [종합_주식] 딸 일반주식")
longify("m-table")
# 머리가 붙어 다니는 목록형 16종목
ms.layout_a("m-sticky", ms.holdings(ms.STOCK + ms.ETF, 16), "ISA · 아들 · 246-80-****")
longify("m-sticky", sticky_head=True)

json.dump(ms.truth[start:], open(os.path.join(HERE, "long_truth.json"), "w"), ensure_ascii=False, indent=1)
print([(t["file"], len(t["rows"])) for t in ms.truth[start:]])
