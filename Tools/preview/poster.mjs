// 미리 보기의 포스터 장면을 **스크린샷 크기**로 — App Store Connect 스크린샷 칸이 받는 크기 (2026-10-13 사용자 화면).
//
//   node Tools/preview/poster.mjs   # → out/poster-1206x2622.png · out/poster-2064x2752.png
//
// 미리 보기 영상(886×1920 · 1200×1600)에서 뽑은 프레임은 스크린샷 칸에 안 맞는다(아이폰 1179×2556 · 1206×2622,
// 아이패드 2048×2732 · 2064×2752). 그래서 영상과 같은 배치(자막 띠 + 앱 화면)를 그 크기로 다시 짠다 —
// 영상을 키우면 글자가 뭉개지므로 녹화 원본에서 그 순간을 다시 꺼낸다.
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require("playwright"); }
catch { playwright = require("/opt/node22/lib/node_modules/playwright"); }

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, "out");
const work = path.join(out, "work");
mkdirSync(work, { recursive: true });

// base = 영상의 배치(edit.mjs PROFILES). 그 비율 그대로 W 에 맞춰 키운다.
// at = 녹화 원본에서 손잡이를 끈 뒤 그래프가 올라간 순간 (영상의 아이폰 22.5초 · 아이패드 23.7초).
const TITLE = "‘만약에’를 돌려 보기";
const SUB = "손잡이를 돌리면 그래프가 따라옵니다";
const POSTERS = [
  { W: 1206, H: 2622, src: "raw-run2.mp4", at: 297.35,
    base: { W: 886, TOP: 300, titleTop: 96, titleSize: 62, subTop: 186, subSize: 34 } },
  { W: 2064, H: 2752, src: "raw-ipad.mp4", at: 308.25,
    base: { W: 1200, TOP: 230, titleTop: 62, titleSize: 58, subTop: 142, subSize: 30 } },
];

const browser = await playwright.chromium.launch();
const fonts = pathToFileURL(path.join(here, "..", "promo", "fonts")).href;
for (const p of POSTERS) {
  const k = p.W / p.base.W;
  const px = v => Math.round(v * k);
  const page = await browser.newPage({ viewport: { width: p.W, height: p.H } });
  await page.setContent(`<!doctype html><html><head><meta charset="utf-8"><style>
    @font-face { font-family: P; font-weight: 500; src: url("${fonts}/Pretendard-Medium.woff2"); }
    @font-face { font-family: P; font-weight: 800; src: url("${fonts}/Pretendard-ExtraBold.woff2"); }
    html, body { margin: 0; width: ${p.W}px; height: ${p.H}px; background: #F4F7F8; font-family: P; }
    .t { position: absolute; left: 0; right: 0; top: ${px(p.base.titleTop)}px; text-align: center; font-size: ${px(p.base.titleSize)}px; font-weight: 800; color: #0B1017; letter-spacing: ${(-1.4 * k).toFixed(1)}px; }
    .s { position: absolute; left: 0; right: 0; top: ${px(p.base.subTop)}px; text-align: center; font-size: ${px(p.base.subSize)}px; font-weight: 500; color: #5E6A75; }
  </style></head><body><div class="t">${TITLE}</div><div class="s">${SUB}</div></body></html>`);
  await page.evaluate(() => document.fonts.ready);
  const bg = path.join(work, `poster-bg-${p.W}.png`);
  await page.screenshot({ path: bg });
  await page.close();

  // edit.mjs 와 같이 처음부터 풀어 30fps 로 메운 뒤 그 시각의 한 장 — 가변 프레임 녹화라 -ss 로 감으면 밀린다.
  const top = px(p.base.TOP);
  const vh = p.H - top - px(40);
  const file = path.join(out, `poster-${p.W}x${p.H}.png`);
  execFileSync("ffmpeg", [
    "-y", "-loglevel", "error",
    "-i", bg, "-i", path.join(here, "raw", p.src),
    "-filter_complex",
    `[1:v]fps=30,trim=start=${p.at},setpts=PTS-STARTPTS,scale=-2:${vh}:flags=lanczos,setsar=1[app];` +
    `[0:v][app]overlay=x=(W-w)/2:y=${top}:eof_action=pass,format=rgb24[v]`,
    "-map", "[v]", "-frames:v", "1", file,
  ]);
  console.log("완성:", file);
}
await browser.close();
