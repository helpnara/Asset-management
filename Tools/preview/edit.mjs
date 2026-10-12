// App Store 미리 보기 편집 — 녹화(raw/)에서 고른 구간을 잘라 아이폰 886×1920 · 아이패드 1200×1600 으로.
//
//   node Tools/preview/edit.mjs                  # → out/app-preview-886x1920.mp4
//   node Tools/preview/edit.mjs --device ipad    # → out/app-preview-1200x1600.mp4
//
// 화면은 손대지 않는다(애플 2.3.4 — 앱 화면 녹화만). 위쪽에 장면마다 한 줄 자막을 얹고, 장면 사이를
// 0.35초 녹여 잇는다. 길이는 애플 규정 15~30초.
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
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

const FADE = 0.35;

// 장면마다 같은 자막 — 기기마다 고른 구간만 다르다
const CAPTIONS = {
  review: { title: "매주 토요일, 직접 적기", sub: "적으면 지난주 대비 증감이 바로" },
  complete: { title: "점검 완료, 연속 기록", sub: "3분이면 이번 주가 끝납니다" },
  dashboard: { title: "계획선 위인가, 아래인가", sub: "은퇴까지 하나의 궤적으로" },
  simulation: { title: "‘만약에’를 돌려 보기", sub: "손잡이를 돌리면 그래프가 따라옵니다" },
  diagnostics: { title: "원칙은 앱이 기억합니다", sub: "4% 규칙 · 부동산 비중 · 국가 배분" },
};

// **고른 구간** — 장면 표시(marks.txt)는 녹화 시간축과 어긋났다(simctl 녹화는 화면이 멈춘 동안 프레임을
// 건너뛰어, 진단 장면 끝이 표시와 51초 차이). 그래서 녹화를 눈으로 훑어 구간을 골랐다 (2026-10-12).
// speed > 1 은 그만큼 빠르게(점검 입력의 멈춰 있는 몇 초를 줄인다).
//
// 크기는 App Store Connect 가 받는 미리 보기 크기 (2026-10-12 사용자가 보낸 화면):
//   아이폰 15.5 · 15.9cm(6.1 · 6.3")  886×1920   — 스크린샷 1179×2556 · 1206×2622 칸
//   아이패드 32.8 · 33.0cm(12.9 · 13") 1200×1600 — 스크린샷 2048×2732 · 2064×2752 칸
const PROFILES = {
  iphone: {
    W: 886, H: 1920, TOP: 300, titleTop: 96, titleSize: 62, subTop: 186, subSize: 34,
    file: "app-preview-886x1920.mp4",
    //   raw.mp4      = 세 번째 녹화 — 점검 입력 · 점검 완료가 제대로 찍혔다
    //   raw-run2.mp4 = 두 번째 녹화 — 현황판 스크롤 · 시뮬레이션 손잡이 · 진단이 제대로 찍혔다
    scenes: [
      { key: "review", src: "raw.mp4", from: 166.8, to: 175.3, speed: 1.4 },
      { key: "complete", src: "raw.mp4", from: 181.6, to: 185.6, speed: 1 },
      { key: "dashboard", src: "raw-run2.mp4", from: 268.5, to: 275.5, speed: 1 },
      { key: "simulation", src: "raw-run2.mp4", from: 291.0, to: 299.0, speed: 1 },
      { key: "diagnostics", src: "raw-run2.mp4", from: 319.5, to: 324.3, speed: 1 },
    ],
  },
  ipad: {
    W: 1200, H: 1600, TOP: 230, titleTop: 62, titleSize: 58, subTop: 142, subSize: 30,
    file: "app-preview-1200x1600.mp4",
    scenes: [],   // raw-ipad.mp4 를 훑어 채운다
  },
};

const device = process.argv.includes("--device") ? process.argv[process.argv.indexOf("--device") + 1] : "iphone";
const profile = PROFILES[device];
if (!profile) throw new Error(`모르는 기기: ${device} (iphone · ipad)`);
const { W, H, TOP } = profile;
const scenes = profile.scenes.map(s => ({ ...s, ...CAPTIONS[s.key], dur: (s.to - s.from) / s.speed }));
if (scenes.length === 0) throw new Error(`${device} 구간이 비었다 — 녹화를 훑어 PROFILES.${device}.scenes 를 채운다`);
const total = scenes.reduce((sum, s) => sum + s.dur, 0) - FADE * (scenes.length - 1);
if (total < 15 || total > 30) throw new Error(`길이 ${total.toFixed(2)}초 — 애플 규정 15~30초를 벗어난다`);
console.log(device, scenes.map(s => `${s.key} ${s.src} ${s.from}-${s.to} ×${s.speed} → ${s.dur.toFixed(2)}초`).join("\n"),
  `\n합계 ${total.toFixed(2)}초`);

// ── 자막 띠 그림 (Pretendard) ────────────────────────────────
const browser = await playwright.chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H } });
const fonts = pathToFileURL(path.join(here, "..", "promo", "fonts")).href;
for (const [i, s] of scenes.entries()) {
  await page.setContent(`<!doctype html><html><head><meta charset="utf-8"><style>
    @font-face { font-family: P; font-weight: 500; src: url("${fonts}/Pretendard-Medium.woff2"); }
    @font-face { font-family: P; font-weight: 800; src: url("${fonts}/Pretendard-ExtraBold.woff2"); }
    html, body { margin: 0; width: ${W}px; height: ${H}px; background: #F4F7F8; font-family: P; }
    .t { position: absolute; left: 0; right: 0; top: ${profile.titleTop}px; text-align: center; font-size: ${profile.titleSize}px; font-weight: 800; color: #0B1017; letter-spacing: -1.4px; }
    .s { position: absolute; left: 0; right: 0; top: ${profile.subTop}px; text-align: center; font-size: ${profile.subSize}px; font-weight: 500; color: #5E6A75; }
  </style></head><body><div class="t">${s.title}</div><div class="s">${s.sub}</div></body></html>`);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(work, `${device}-bg-${i}.png`) });
}
await browser.close();

// ── 장면마다 자르고 얹기 ─────────────────────────────────────
// 녹화를 띠 아래 칸에 맞춘다: 높이 H-TOP-40, 가운데.
const vh = H - TOP - 40;
const parts = [];
for (const [i, s] of scenes.entries()) {
  const part = path.join(work, `${device}-scene-${i}.mp4`);
  execFileSync("ffmpeg", [
    "-y", "-loglevel", "error",
    "-loop", "1", "-t", s.dur.toFixed(3), "-i", path.join(work, `${device}-bg-${i}.png`),
    "-ss", s.from.toFixed(3), "-t", (s.to - s.from).toFixed(3), "-i", path.join(here, "raw", s.src),
    "-filter_complex",
    `[1:v]fps=30,setpts=(PTS-STARTPTS)/${s.speed},fps=30,scale=-2:${vh}:flags=lanczos,setsar=1[app];` +
    `[0:v]fps=30,format=yuv420p[bg];` +
    `[bg][app]overlay=x=(W-w)/2:y=${TOP}:shortest=1,format=yuv420p[v]`,
    "-map", "[v]", "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "16", "-r", "30", part,
  ]);
  parts.push(part);
}

// ── 이어 붙이기 (녹이며) ─────────────────────────────────────
const inputs = parts.flatMap(p => ["-i", p]);
let filter = "", last = "[0:v]", offset = 0;
for (let i = 1; i < parts.length; i++) {
  offset += scenes[i - 1].dur - FADE;
  const label = i === parts.length - 1 ? "[v]" : `[x${i}]`;
  filter += `${last}[${i}:v]xfade=transition=fade:duration=${FADE}:offset=${offset.toFixed(3)}${label};`;
  last = label;
}
const file = path.join(out, profile.file);
execFileSync("ffmpeg", [
  "-y", "-loglevel", "error", ...inputs,
  // 애플: H.264, 30fps 이하. 소리는 없어도 되지만 무음 트랙을 넣으면 업로드가 덜 까다롭다.
  "-f", "lavfi", "-t", total.toFixed(3), "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
  ...(parts.length > 1 ? ["-filter_complex", filter.replace(/;$/, ""), "-map", "[v]"] : ["-map", "0:v"]),
  "-map", `${parts.length}:a`,
  "-c:v", "libx264", "-profile:v", "high", "-level", "4.0", "-pix_fmt", "yuv420p", "-r", "30", "-crf", "18",
  "-c:a", "aac", "-b:a", "128k", "-shortest", "-movflags", "+faststart", file,
]);
writeFileSync(path.join(out, `scenes-${device}.txt`), scenes.map(s => `${s.key}\t${s.dur.toFixed(2)}s\t${s.title}`).join("\n") + "\n");
console.log("완성:", file);
