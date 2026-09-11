#!/usr/bin/env python3
"""App Store 제출용 스크린샷에 문장을 얹는다 (docs/10 §4 · 136번).

    python3 Tools/store/compose.py <원본 폴더> <출력 폴더> <iphone|ipad>

원본은 시뮬레이터가 찍은 그대로(iPhone 6.9" 1320×2868 · iPad 13" 2064×2752).
출력도 같은 크기다 — App Store 는 이 크기만 받는다. 위에 문장 두 줄, 아래에
화면을 조금 줄여 둥근 모서리로 앉힌다. 첫 장에서 "직접 적는 앱" 임을 말해야
자동 연동을 기대한 사람이 별 하나를 안 준다.

Pillow 가 필요하다 (`pip3 install pillow`). 한글 서체는 macOS 의
AppleSDGothicNeo 를 쓰고, 없으면 있는 것 중 한글이 되는 것을 찾는다.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

CAPTIONS = [
    ("계획선 위인가, 아래인가", "매주 적은 숫자가 은퇴까지 하나의 궤적이 됩니다"),
    ("매주 토요일, 3분", "시세를 가져오지 않습니다. 손으로 적는 그 수고가 계획을 몸에 새깁니다"),
    ("노후는 가족 단위입니다", "넷이 각자의 궤적과 가족 총합을 같은 화면에서 봅니다"),
    ("규칙이 스스로 감시합니다", "4% 규칙 · 부동산 비중 · 국가 배분 — 기준은 전부 내가 정합니다"),
    ("서버가 없습니다", "통신도 광고도 없습니다. 자료는 내 기기와 내 iCloud 에만 있습니다"),
]

FONT_CANDIDATES = [
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
    "/Library/Fonts/NotoSansCJKkr-Regular.otf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
]

BACKGROUND = (244, 245, 247)
INK = (28, 33, 40)
MUTED = (91, 102, 112)


def font(size: int, bold: bool) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES:
        if not Path(path).exists():
            continue
        try:
            # AppleSDGothicNeo.ttc: 0 Regular … 6 Bold 근처. 굵기는 index 로 고른다.
            index = 6 if (bold and path.endswith("AppleSDGothicNeo.ttc")) else 0
            return ImageFont.truetype(path, size, index=index)
        except OSError:
            continue
    return ImageFont.load_default()


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, image.width - 1, image.height - 1], radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def compose(source: Path, target: Path, title: str, subtitle: str, kind: str) -> None:
    shot = Image.open(source).convert("RGB")
    width, height = shot.size
    canvas = Image.new("RGB", (width, height), BACKGROUND)
    draw = ImageDraw.Draw(canvas)

    # 문장 자리. 아이폰은 위 1/5, 아이패드는 위 1/4 — 가로가 넓어 줄이 짧다.
    scale = width / 1320
    title_font = font(int(92 * scale), bold=True)
    sub_font = font(int(46 * scale), bold=False)
    top = int(150 * scale)
    draw.text((int(90 * scale), top), title, font=title_font, fill=INK)
    # 부제는 폭에 맞춰 줄바꿈.
    words = subtitle.split(" ")
    lines, line = [], ""
    max_width = width - int(180 * scale)
    for word in words:
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=sub_font) <= max_width:
            line = trial
        else:
            lines.append(line)
            line = word
    lines.append(line)
    y = top + int(130 * scale)
    for text in lines:
        draw.text((int(90 * scale), y), text, font=sub_font, fill=MUTED)
        y += int(64 * scale)

    # 화면. 문장 아래에서 시작해 바닥 아래로 흘러 나가게 — 잘리는 것이 자연스럽다.
    shot_top = y + int(70 * scale)
    shot_width = int(width * 0.86)
    shot_scaled = shot.resize((shot_width, int(height * shot_width / width)), Image.LANCZOS)
    radius = int(70 * scale) if kind == "iphone" else int(40 * scale)
    shot_rounded = rounded(shot_scaled, radius)

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [(width - shot_width) // 2, shot_top + int(12 * scale),
         (width + shot_width) // 2, shot_top + shot_scaled.height + int(12 * scale)],
        radius=radius, fill=(0, 0, 0, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(int(28 * scale)))
    canvas = Image.alpha_composite(canvas.convert("RGBA"), shadow)
    canvas.alpha_composite(shot_rounded, ((width - shot_width) // 2, shot_top))
    canvas.convert("RGB").save(target, "PNG", optimize=True)


def main() -> None:
    source_dir, target_dir, kind = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    target_dir.mkdir(parents=True, exist_ok=True)
    sources = sorted(source_dir.glob("*.png"))
    if len(sources) != len(CAPTIONS):
        sys.exit(f"원본 {len(sources)}장, 문장 {len(CAPTIONS)}개 — 수가 맞아야 한다")
    for source, (title, subtitle) in zip(sources, CAPTIONS):
        target = target_dir / source.name
        compose(source, target, title, subtitle, kind)
        with Image.open(target) as done:
            print(f"{target} {done.width}×{done.height}")


if __name__ == "__main__":
    main()
