#!/usr/bin/env python3
"""앱 아이콘을 그린다.

    python3 Tools/make-icon.py

`App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 를 덮어쓴다.
의존성: Pillow (`pip install pillow`)

── 왜 이 그림인가 ────────────────────────────────────────────────
**펼친 책 위에 그려진 상승 곡선.** 앱 이름 그대로다 —

  · 책     "기록". 매주 손으로 적어 넣는 행위
  · 곡선   "느린 부자". 로그축에서 복리가 그리는 완만한 상승
  · 끝점   지금 내가 서 있는 자리

블로그 아이콘(Moat연구소)의 색과 상단 마크를 이어받았다.
색은 블로그 이미지에서 직접 뽑은 값이다.

── 아이콘 크기에서 살아남게 하려고 지킨 것 ──────────────────────
아이콘은 홈 화면에서 60pt 로 그려진다. 그 크기에서 죽는 것들이 있다.

1. **글자를 넣지 않는다.** 60pt 에서 한글은 읽히지 않는다 (Apple HIG).
2. **가는 선과 잔detail 을 넣지 않는다.** 점선·그림자·사진은 뭉갠다.
3. **원을 그려 넣지 않는다.** iOS 가 이미 모서리를 깎는다. 안에 원을 그리면
   네 귀퉁이가 어중간하게 남아 '스티커'처럼 보인다.
4. **꽉 찬 도형 하나로 읽히게.** 여기서는 책 실루엣이 그 역할을 하고,
   곡선은 크림색으로 그 안에서 뚫려 보인다 — 하나의 마크가 된다.

── 만들면서 실패한 것 ───────────────────────────────────────────
· 굵은 폴리라인(`line(joint="curve")`)은 이음매에 지저러기를 남긴다.
  원을 촘촘히 겹쳐 그린다.
· 곡선을 책의 모서리에서 모서리로 그으면 **취소선처럼 읽힌다.**
  양 끝을 안쪽으로 넣고 곡률을 분명히 준다.
· 막대 차트를 책 안에 넣어 봤더니 등뼈 틈과 겹쳐 무슨 도형인지 알 수 없었다.
· 알파 채널이 있으면 App Store 가 반려한다. RGB 로 저장한다.
"""

from pathlib import Path

from PIL import Image, ImageDraw

SUPERSAMPLE = 3072          # 3배로 그린 뒤 줄여 안티에일리어싱을 얻는다
FINAL = 1024

# 블로그 아이콘에서 직접 뽑은 색.
GREEN = (47, 57, 37)        # #2F3925 — 제목 글자 · 배지
CREAM = (250, 242, 229)     # #FAF2E5 — 바탕

OUTPUT = Path("App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")

# 책의 비율. 바깥 위 모서리가 들리고 등뼈 쪽이 내려앉은 펼친 책 모양이다.
HALF = 0.335                # 등뼈에서 바깥 모서리까지
TOP_OUTER, TOP_SPINE = 0.335, 0.415
BOTTOM_SPINE, BOTTOM_OUTER = 0.760, 0.665
CORNER = 0.020              # 모서리를 둥글리는 정도
LINE_WIDTH = 0.046


def scale(value: float) -> float:
    return value * SUPERSAMPLE


def curve(p0, p1, p2, steps: int = 300):
    """2차 베지에. p1 이 당기는 점이다."""
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0],
                    u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def stroke(pen, points, width: float, fill) -> None:
    """원을 촘촘히 겹쳐 선을 그린다. 이음매가 원리적으로 둥글다."""
    radius = scale(width) / 2
    for x, y in points:
        pen.ellipse([scale(x) - radius, scale(y) - radius,
                     scale(x) + radius, scale(y) + radius], fill=fill)


def draw() -> Image.Image:
    image = Image.new("RGB", (SUPERSAMPLE, SUPERSAMPLE), CREAM)
    pen = ImageDraw.Draw(image)

    # 펼친 책 — 좌우 페이지를 따로 그린다. 사이의 크림 틈이 등뼈가 된다.
    for side in (-1, 1):
        outer_top = (0.5 + side * HALF, TOP_OUTER)
        spine_top = (0.5 + side * 0.022, TOP_SPINE)
        spine_bottom = (0.5 + side * 0.022, BOTTOM_SPINE)
        outer_bottom = (0.5 + side * HALF, BOTTOM_OUTER)

        outline = curve(outer_top, (0.5 + side * HALF * 0.55, TOP_OUTER + 0.012),
                        spine_top, steps=120)
        outline += [spine_bottom]
        outline += curve(spine_bottom, (0.5 + side * HALF * 0.55, BOTTOM_OUTER + 0.030),
                         outer_bottom, steps=120)

        polygon = [(scale(x), scale(y)) for x, y in outline]
        pen.polygon(polygon, fill=GREEN)
        # 같은 색 굵은 윤곽선을 덧그려 모서리를 둥글린다.
        pen.line(polygon + [polygon[0]], fill=GREEN,
                 width=int(scale(CORNER)), joint="curve")
        stroke(pen, outline, CORNER, GREEN)

    # 페이지 위에 그려진 상승 곡선. 양 끝을 안쪽으로 넣어 취소선으로 안 읽히게 한다.
    rise = curve((0.275, 0.660), (0.415, 0.505), (0.730, 0.470))
    stroke(pen, rise, LINE_WIDTH, CREAM)

    # 지금 내가 서 있는 자리.
    x, y = rise[-1]
    radius = scale(0.040)
    pen.ellipse([scale(x) - radius, scale(y) - radius,
                 scale(x) + radius, scale(y) + radius], fill=CREAM)

    return image.resize((FINAL, FINAL), Image.LANCZOS)


def main() -> None:
    icon = draw()
    assert icon.mode == "RGB", "알파 채널이 있으면 App Store 가 반려한다"
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUTPUT, "PNG")
    print(f"{OUTPUT} ({icon.size[0]}×{icon.size[1]}, {icon.mode})")


if __name__ == "__main__":
    main()
