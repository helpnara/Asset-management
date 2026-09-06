#!/usr/bin/env python3
"""앱 아이콘을 만든다.

    python3 Tools/make-icon.py

`Tools/icon-source.png` 를 App Store 규격에 맞춰
`App/Assets.xcassets/AppIcon.appiconset/icon-1024.png` 로 굽는다.

의존성: Pillow (`pip install pillow`)

── 하는 일 ──────────────────────────────────────────────────────
1. 정사각형으로 자른다 (가운데 기준). 이미 정사각형이면 그대로 둔다.
2. 1024×1024 로 줄인다 (LANCZOS).
3. **알파 채널을 없앤다.** 알파가 있으면 App Store 가 반려한다.
4. 모서리를 깎지 않는다 — iOS 가 알아서 한다. 여기서 깎으면 이중으로 깎인다.

── 아이콘을 바꾸려면 ────────────────────────────────────────────
`Tools/icon-source.png` 를 새 이미지로 갈아 끼우고 이 스크립트를 다시 돌린다.
원본을 저장소에 두는 이유는, 결과물만 있으면 나중에 손볼 수가 없기 때문이다.

── 원본 이미지를 고를 때 ────────────────────────────────────────
홈 화면에서 아이콘은 **60pt** 로 그려진다. 그 크기에서 죽는 것들이 있다.

· 글자      한글은 60pt 에서 읽히지 않는다 (Apple HIG 가 아이콘에 글자를
            넣지 말라고 못 박는다). 넣는다면 '읽는 글'이 아니라 '무늬'로 여긴다
· 잔 디테일 사진의 질감·작은 사물은 뭉갠다. 큰 색 덩어리만 남는다
· 원·테두리 iOS 가 이미 모서리를 깎는다. 안에 원을 그리면 귀퉁이가 어중간해진다
· 저작물     실존하는 책 표지·로고가 알아볼 수 있게 들어가면 상표 문제가 된다

`python3 Tools/preview-icon.py` 로 실제 크기(180·120·60px)를 미리 볼 수 있다.
"""

from pathlib import Path

from PIL import Image

SOURCE = Path("Tools/icon-source.png")
OUTPUT = Path("App/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
SIZE = 1024


def square(image: Image.Image) -> Image.Image:
    """가운데를 기준으로 정사각형을 잘라낸다."""
    width, height = image.size
    if width == height:
        return image
    side = min(width, height)
    left = (width - side) // 2
    top = (height - side) // 2
    return image.crop((left, top, left + side, top + side))


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"원본이 없습니다: {SOURCE}")

    # 알파가 있으면 흰 바탕에 합성해서 없앤다. 그냥 convert("RGB") 하면
    # 투명했던 자리가 검게 남는 경우가 있다.
    source = Image.open(SOURCE)
    if source.mode in ("RGBA", "LA", "P"):
        source = source.convert("RGBA")
        flat = Image.new("RGB", source.size, (255, 255, 255))
        flat.paste(source, mask=source.split()[-1])
        source = flat
    else:
        source = source.convert("RGB")

    icon = square(source).resize((SIZE, SIZE), Image.LANCZOS)

    assert icon.mode == "RGB", "알파 채널이 있으면 App Store 가 반려한다"
    assert icon.size == (SIZE, SIZE)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUTPUT, "PNG")
    print(f"{OUTPUT} ({icon.size[0]}×{icon.size[1]}, {icon.mode})")


if __name__ == "__main__":
    main()
