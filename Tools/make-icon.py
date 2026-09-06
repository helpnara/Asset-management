#!/usr/bin/env python3
"""앱 아이콘을 그린다.

    python3 Tools/make-icon.py

`App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 를 덮어쓴다.

── 왜 이 그림인가 ────────────────────────────────────────────────
앱 이름은 "느린 부자의 기록"이고, 화면의 핵심은 로그축 위에 그려지는
완만한 상승 궤적이다. 아이콘을 그 궤적 자체로 만들었다 —
앱이 하는 일을 그대로 그린 것이다.

  · 곡선      로그축에서 복리가 그리는 완만한 상승
  · 점 다섯   매주 적어 넣은 기록
  · 점선      목표선. 마지막 기록이 막 닿는 높이에 둔다

색은 전부 앱의 팔레트(App/DesignSystem/Palette.swift)에서 가져왔다.

── 기술적으로 주의할 것 ──────────────────────────────────────────
1. 4배로 그린 뒤 줄인다. 안티에일리어싱을 얻는 가장 단순한 방법.
2. 굵은 폴리라인을 쓰지 않는다. PIL 의 line(joint="curve") 은 이음매에
   지저러기를 남긴다 — 실제로 첫 시도에서 곡선 가장자리가 털처럼 나왔다.
   원을 촘촘히 겹쳐 그리면 이음매가 완벽하게 둥글다.
3. **알파 채널이 있으면 App Store 가 반려한다.** RGB 로 저장한다.
4. iOS 가 모서리를 둥글게 깎으므로 내용은 가장자리에서 띄운다.

의존성: Pillow (`pip install pillow`)
"""

from pathlib import Path

from PIL import Image, ImageDraw

# 4배로 그린 뒤 줄인다.
SUPERSAMPLE = 4096
FINAL = 1024

# App/DesignSystem/Palette.swift 와 같은 값이다.
INK = (11, 16, 23)        # Color.ink      — 배경
LINE = (127, 178, 204)    # Color.dad 계열 — 궤적
DOT = (244, 247, 248)     # Color.surface  — 매주의 기록
FAINT = (48, 64, 78)      # 목표선

OUTPUT = Path("App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")


def curve(t: float) -> tuple[float, float]:
    """t(0~1) 에서의 좌표.

    지수 0.70 이 "처음엔 가파르고 뒤로 갈수록 완만한" 모양을 만든다.
    로그축에서 복리가 그리는 선이 딱 이렇게 생겼다.

    가로 0.19~0.81, 세로 0.745~0.29 안에 둔다 — iOS 가 모서리를 깎으므로
    가장자리까지 채우면 잘린다.
    """
    return (
        SUPERSAMPLE * (0.19 + 0.62 * t),
        SUPERSAMPLE * (0.745 - 0.455 * (t ** 0.70)),
    )


def draw() -> Image.Image:
    image = Image.new("RGB", (SUPERSAMPLE, SUPERSAMPLE), INK)
    pen = ImageDraw.Draw(image)

    # 목표선 — 마지막 기록보다 살짝 위. "거의 닿았다"로 읽힌다.
    target_y = int(curve(1.0)[1] - SUPERSAMPLE * 0.055)
    x = int(SUPERSAMPLE * 0.15)
    while x < SUPERSAMPLE * 0.855:
        pen.rounded_rectangle(
            [x, target_y - SUPERSAMPLE // 420, x + SUPERSAMPLE // 60, target_y + SUPERSAMPLE // 420],
            radius=SUPERSAMPLE // 840,
            fill=FAINT,
        )
        x += SUPERSAMPLE // 34

    # 궤적. 원을 촘촘히 겹쳐 그린다 (위 주의사항 2번).
    width = SUPERSAMPLE // 30
    for step in range(3001):
        px, py = curve(step / 3000)
        pen.ellipse([px - width, py - width, px + width, py + width], fill=LINE)

    # 매주 적어 넣은 기록.
    radius = SUPERSAMPLE // 42
    for t in (0.0, 0.25, 0.5, 0.75, 1.0):
        px, py = curve(t)
        pen.ellipse([px - radius, py - radius, px + radius, py + radius], fill=DOT)

    return image.resize((FINAL, FINAL), Image.LANCZOS)


def main() -> None:
    icon = draw()
    assert icon.mode == "RGB", "알파 채널이 있으면 App Store 가 반려한다"
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUTPUT, "PNG")
    print(f"{OUTPUT} ({icon.size[0]}×{icon.size[1]}, {icon.mode})")


if __name__ == "__main__":
    main()
