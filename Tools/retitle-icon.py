#!/usr/bin/env python3
"""아이콘 그림에 박힌 제목을 `느린 부자의 기록` → `느린 부자` 로 고친다.

    python3 Tools/retitle-icon.py

`Tools/icon-source-original.png`(처음 받은 그림) 을 읽어
`Tools/icon-source.png` 로 쓴다. 그 다음 `Tools/make-icon.py` 가 앱 아이콘을 굽는다.

── 왜 이렇게 했나 ───────────────────────────────────────────────
2026-09-24 에 앱 이름을 `느린 부자` 로 줄였는데 (`느린` 시리즈), 아이콘 띠에
제목이 그림으로 박혀 있었다. 같은 서체·같은 굵기로 다시 쓰려면 원본 서체가
필요한데 그것이 없다. 그래서 **이미 그려져 있는 `느린 부자` 글자를 그대로
오려서 가운데로 옮기고, `의 기록` 이 있던 자리는 배너 초록으로 메웠다.**
서체가 바뀌지 않는 유일한 방법이다.

── 하는 일 ─────────────────────────────────────────────────────
1. 글자 줄(y 940~1112)에서 `느린 부자`(x 200~720) 를 조각으로 떠 둔다.
   초록이 아닌 픽셀만 고르므로 배경은 딸려오지 않는다.
2. 글자 줄 전체(x 195~1060)를 배너 초록으로 덮는다. 색은 줄 위아래의
   깨끗한 줄을 **가로로 뭉갠 뒤 세로로 선형 보간**해서 만든다 — 한 줄의
   중앙값으로 평평하게 칠하면 덮은 자리가 네모로 비치고, 한 픽셀씩 그대로
   쓰면 잡티가 세로줄로 번진다. 둘 다 실제로 겪고 나서 이 방법으로 왔다.
3. 조각을 오른쪽으로 162px 옮겨 붙인다. 옮긴 뒤 글자 가운데가 배너 가운데
   (x 627) 에 온다. **같은 줄로 옮기기 때문에** 배경의 세로 그라데이션이
   그대로 맞아 이음매가 보이지 않는다.
4. 새싹은 원래 제목 전체의 가운데에 있었다 — 새 제목도 같은 가운데라서
   **움직이지 않는다.** 다만 줄기가 글자 줄까지 내려와 2번에서 지워지므로
   제자리에 다시 그린다 (밝은 초록만 골라서).

── 숫자를 고쳐야 한다면 ─────────────────────────────────────────
원본 그림이 바뀌면 아래 좌표는 전부 무효다. 그때는 글자 덩어리의 x 범위를
다시 재고 (밝은 픽셀의 열 분포를 보면 덩어리가 갈라진다) 여기에 적는다.

의존성: Pillow, numpy
"""

from pathlib import Path

import numpy as np
from PIL import Image

SOURCE = Path("Tools/icon-source-original.png")
OUTPUT = Path("Tools/icon-source.png")

TOP, BOT = 940, 1112        # 글자 잉크가 있는 줄 (실제 잉크는 949~1107)
LEFT, RIGHT = 195, 1060     # 지울 가로 범위 — `느` 왼쪽부터 `록` 오른쪽까지
KEEP_L, KEEP_R = 200, 720   # 남길 조각 = `느린 부자` (`자`와 `의` 사이 골짜기가 718~721)
SHIFT = 162                 # 오른쪽으로 옮길 양 = (627 - (213+718)/2) 의 반올림
STEM = (606, 672, 976)      # 제자리에 다시 그릴 새싹 줄기 (x 시작, x 끝, y 끝)
SMOOTH = 41                 # 배경 기준 줄을 가로로 뭉갤 폭


def main() -> None:
    image = np.array(Image.open(SOURCE).convert("RGB")).astype(np.int16)
    red, green = image[:, :, 0], image[:, :, 1]
    is_background = green > red + 25            # 배너 초록 + 새싹 초록
    is_sprout = (green > 130) & (green > red + 30)   # 새싹 초록만
    is_letter = ~is_background

    assert is_letter[TOP:BOT, LEFT - 25:LEFT].sum() == 0, "지울 범위 왼쪽 바로 밖에 글자가 있다"
    assert is_letter[TOP:BOT, RIGHT:RIGHT + 25].sum() == 0, "지울 범위 오른쪽 바로 밖에 글자가 있다"

    patch = image[TOP:BOT, KEEP_L:KEEP_R].copy()
    mask = is_letter[TOP:BOT, KEEP_L:KEEP_R]
    grown = mask.copy()                         # 안티에일리어싱 자락 한 픽셀까지
    grown[1:, :] |= mask[:-1, :]
    grown[:-1, :] |= mask[1:, :]
    grown[:, 1:] |= mask[:, :-1]
    grown[:, :-1] |= mask[:, 1:]

    stem_l, stem_r, stem_bot = STEM
    stem = image[TOP:stem_bot, stem_l:stem_r].copy()
    stem_mask = is_sprout[TOP:stem_bot, stem_l:stem_r]

    top_reference = background_row(image, is_background, is_sprout, TOP - 9)
    bottom_reference = background_row(image, is_background, is_sprout, BOT + 5)
    span = (BOT + 7) - (TOP - 7)
    for y in range(TOP, BOT):
        t = (y - (TOP - 7)) / span
        image[y, LEFT:RIGHT] = np.rint(top_reference * (1 - t) + bottom_reference * t)

    image[TOP:BOT, KEEP_L + SHIFT:KEEP_R + SHIFT][grown] = patch[grown]
    image[TOP:stem_bot, stem_l:stem_r][stem_mask] = stem[stem_mask]

    Image.fromarray(image.astype(np.uint8)).save(OUTPUT)
    print(f"{OUTPUT} 를 썼습니다 — 이어서 `python3 Tools/make-icon.py`")


def background_row(image, is_background, is_sprout, start):
    """`start` 부터 다섯 줄의 배너 색을 뽑아 가로로 뭉갠다.

    새싹이 걸린 칸은 그 줄의 중앙값으로 바꾼다 — 안 그러면 밝은 초록이
    아래로 번져 세로줄이 된다.
    """
    width = RIGHT - LEFT
    total = np.zeros((width, 3))
    count = np.zeros((width, 1))
    for y in range(start, start + 5):
        usable = (is_background[y, LEFT:RIGHT] & ~is_sprout[y, LEFT:RIGHT])[:, None]
        total += image[y, LEFT:RIGHT] * usable
        count += usable
    seen = count[:, 0] > 0
    middle = np.median(total[seen] / count[seen], axis=0)
    row = np.where(count > 0, total / np.maximum(count, 1), middle)

    kernel = np.ones(SMOOTH) / SMOOTH
    pad = SMOOTH // 2
    return np.stack(
        [np.convolve(np.pad(row[:, c], pad, mode="edge"), kernel, "same")[pad:-pad]
         for c in range(3)],
        axis=1,
    )


if __name__ == "__main__":
    main()
