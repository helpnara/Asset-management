#!/usr/bin/env python3
"""개인정보 처리방침 · 지원 페이지만 담은 작은 사이트를 만든다.

GitHub Pages 에 `/docs` 폴더 전체를 올리면 설계 문서와 피드백 기록까지 다
공개된다 (2026-09-11 사용자: "방침만 따로 두자"). 그래서 이 스크립트가
`docs/privacy-policy.md` **하나만** HTML 로 바꿔 `_site/` 에 놓고,
`.github/workflows/pages.yml` 이 그 폴더만 배포한다.

원본은 여전히 `docs/privacy-policy.md` 다 — 고치면 다음 푸시에 반영된다.
외부 패키지를 안 쓰려고 마크다운 변환기를 손으로 썼다. 방침이 쓰는 문법
(제목 · 문단 · 굵게 · 인라인 코드 · 링크 · 목록 · 표)만 안다.

사용법:  python3 Tools/site/build.py [출력 폴더=_site]
"""
import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "privacy-policy.md"
OUT = Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / "_site")

APP_NAME = "느린 부자의 기록"
SUPPORT_EMAIL = "kyunglagkwon@gmail.com"
ISSUES_URL = "https://github.com/helpnara/Asset-management/issues"

STYLE = """
:root { color-scheme: light dark; }
body { margin: 0; padding: 32px 20px 64px; font: 16px/1.7 -apple-system, BlinkMacSystemFont,
  "Apple SD Gothic Neo", "Pretendard", "Noto Sans KR", sans-serif; color: #1c2128; background: #fbfbfa; }
main { max-width: 680px; margin: 0 auto; }
h1 { font-size: 26px; line-height: 1.3; margin: 0 0 8px; }
h2 { font-size: 19px; margin: 36px 0 8px; }
h3 { font-size: 16px; margin: 24px 0 6px; }
p, li { margin: 8px 0; }
ul { padding-left: 22px; }
code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.92em;
  background: rgba(127,127,127,0.14); padding: 1px 5px; border-radius: 4px; }
table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 15px; }
th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid rgba(127,127,127,0.3); vertical-align: top; }
th { font-weight: 600; }
a { color: #2f5bd7; }
.eyebrow { font-size: 12px; letter-spacing: 0.18em; color: #6b7280; margin: 0 0 6px; }
.muted { color: #6b7280; font-size: 14px; }
footer { margin-top: 48px; padding-top: 16px; border-top: 1px solid rgba(127,127,127,0.3); }
.card { border: 1px solid rgba(127,127,127,0.3); border-radius: 12px; padding: 16px 18px; margin: 16px 0; }
@media (prefers-color-scheme: dark) {
  body { color: #e6e8eb; background: #111418; }
  a { color: #8fb0ff; }
  .eyebrow, .muted { color: #9aa3ad; }
}
"""


def inline(text: str) -> str:
    """굵게 · 인라인 코드 · 링크 · <url>."""
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', text)
    text = re.sub(r"&lt;(https?://[^&]+)&gt;", r'<a href="\1">\1</a>', text)
    text = re.sub(r"&lt;([^&\s]+@[^&\s]+)&gt;", r'<a href="mailto:\1">\1</a>', text)
    return text


def convert(markdown: str) -> tuple[str, str]:
    """(제목, 본문 HTML). 문단은 빈 줄로 끊고, 줄바꿈은 공백으로 잇는다."""
    title = ""
    out: list[str] = []
    paragraph: list[str] = []
    list_open = False
    table: list[str] = []

    def flush_paragraph() -> None:
        nonlocal paragraph
        if paragraph:
            out.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph = []

    def close_list() -> None:
        nonlocal list_open
        if list_open:
            out.append("</ul>")
            list_open = False

    def flush_table() -> None:
        nonlocal table
        if not table:
            return
        rows = [r for r in table if not re.match(r"^\|\s*-", r)]
        cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
        head, body = cells[0], cells[1:]
        out.append("<table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>")
        for row in body:
            out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
        out.append("</tbody></table>")
        table = []

    for raw in markdown.splitlines():
        line = raw.rstrip()
        if line.startswith("|"):
            flush_paragraph(); close_list()
            table.append(line)
            continue
        flush_table()
        if not line.strip():
            flush_paragraph(); close_list()
            continue
        m = re.match(r"^(#{1,3})\s+(.*)$", line)
        if m:
            flush_paragraph(); close_list()
            level = len(m.group(1))
            text = m.group(2)
            if level == 1 and not title:
                title = text
                continue
            out.append(f"<h{level}>{inline(text)}</h{level}>")
            continue
        m = re.match(r"^\s*-\s+(.*)$", line)
        if m:
            flush_paragraph()
            if not list_open:
                out.append("<ul>")
                list_open = True
            out.append(f"<li>{inline(m.group(1))}</li>")
            continue
        close_list()
        paragraph.append(line.strip())

    flush_paragraph(); close_list(); flush_table()
    return title, "\n".join(out)


def page(title: str, body: str, eyebrow: str = APP_NAME) -> str:
    return f"""<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} — {APP_NAME}</title>
<style>{STYLE}</style>
</head>
<body>
<main>
<p class="eyebrow">{html.escape(eyebrow)}</p>
<h1>{html.escape(title)}</h1>
{body}
<footer class="muted">
<p>{APP_NAME} · 문의 <a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a> ·
<a href="{ISSUES_URL}">GitHub Issues</a></p>
</footer>
</main>
</body>
</html>
"""


def main() -> None:
    markdown = SOURCE.read_text(encoding="utf-8")
    title, body = convert(markdown)
    (OUT / "privacy-policy").mkdir(parents=True, exist_ok=True)
    (OUT / "privacy-policy" / "index.html").write_text(page(title, body), encoding="utf-8")

    support = f"""
<p>매주 토요일, 가족 자산을 직접 적습니다. 그 숫자가 은퇴 계획선 위인지
아래인지 하나의 궤적으로 보여 주는 iPhone 앱입니다.</p>
<div class="card">
<p><strong>문의 · 피드백</strong><br>
<a href="mailto:{SUPPORT_EMAIL}">{SUPPORT_EMAIL}</a><br>
<span class="muted">앱의 더보기 → 도움말 → "문의 · 피드백 메일" 을 누르면 버전이 함께 적힙니다.
"진단 정보 복사" 를 붙여 주시면 더 빨리 답할 수 있습니다 (금액은 들어가지 않습니다).</span></p>
</div>
<div class="card">
<p><strong>개인정보 처리방침</strong><br>
<a href="privacy-policy/">privacy-policy</a><br>
<span class="muted">이 앱은 어떤 개인정보도 수집하거나 외부로 보내지 않습니다.</span></p>
</div>
<p class="muted">서버가 없고, 시세를 가져오지 않으며, 광고와 분석 도구가 없습니다.
자료는 기기와 본인의 iCloud 에만 있습니다.</p>
"""
    (OUT / "index.html").write_text(page("지원", support), encoding="utf-8")
    (OUT / ".nojekyll").write_text("", encoding="utf-8")
    print(f"만들었습니다: {OUT}/index.html · {OUT}/privacy-policy/index.html")


if __name__ == "__main__":
    main()
