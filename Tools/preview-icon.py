#!/usr/bin/env python3
"""아이콘을 실제 표시 크기로 미리 본다.

    python3 Tools/preview-icon.py

`/tmp/icon-preview.png` 에 대조 시트를 만든다.
큰 화면에서 예뻐 보이는 것과 홈 화면에서 읽히는 것은 다른 문제다.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ICON = Path("App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
OUTPUT = Path("/tmp/icon-preview.png")

# 왼쪽부터: 앱스토어 카드 · 설정 목록 · 홈 화면(60pt @3x 를 1배로 본 크기)
SIZES = [(320, "1024px 원본"), (180, "180px"), (120, "120px"), (60, "60px 홈 화면")]


def main() -> None:
    icon = Image.open(ICON)
    pad, gap = 28, 24
    width = pad * 2 + sum(s for s, _ in SIZES) + gap * (len(SIZES) - 1)
    height = pad * 2 + SIZES[0][0] + 34
    sheet = Image.new("RGB", (width, height), (232, 232, 234))
    pen = ImageDraw.Draw(sheet)

    x = pad
    for size, label in SIZES:
        sheet.paste(icon.resize((size, size), Image.LANCZOS), (x, pad))
        pen.text((x, pad + SIZES[0][0] + 10), label, fill=(70, 70, 70))
        x += size + gap

    sheet.save(OUTPUT)
    print(OUTPUT)


if __name__ == "__main__":
    main()
