// App Store 미리 보기 편집 — 녹화(raw/raw.mp4)를 장면 표시(raw/marks.txt)대로 잘라 886×1920 으로.
//
//   node Tools/preview/edit.mjs        # → Tools/preview/out/app-preview-886x1920.mp4
//
// 화면은 손대지 않는다(애플 2.3.4 — 앱 화면 녹화만). 위쪽에 장면마다 한 줄 자막을 얹고, 장면 사이를
// 0.35초 녹여 잇는다. 길이는 애플 규정 15~30초 — 넘으면 장면마다 고르게 줄인다.
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require("playwright"); }
catch { playwright = require("/opt/node22/lib/node_modules/playwright"); }

const here = path.dirname(fileURLToPath(import.meta.url));
const raw = path.join(here, "raw", "raw.mp4");
const out = path.join(here, "out");
const work = path.join(out, "work");
mkdirSync(work, { recursive: true });

const W = 886, H = 1920;          // 애플이 받는 큰 아이폰 세로 크기
const TOP = 300;                   // 자막 띠 높이
const FADE = 0.35;
const MAX = 29.5;

// 장면 순서 · 자막 — 대본(AppUITests/PreviewRecording.swift)과 같은 이름
const SCENES = [
  { key: "review", title: "매주 토요일, 직접 적기", sub: "적으면 지난주 대비 증감이 바로" },
  { key: "complete", title: "점검 완료, 연속 기록", sub: "3분이면 이번 주가 끝납니다" },
  { key: "dashboard", title: "계획선 위인가, 아래인가", sub: "은퇴까지 하나의 궤적으로" },
  { key: "simulation", title: "‘만약에’를 돌려 보기", sub: "손잡이를 돌리면 그래프가 따라옵니다" },
  { key: "diagnostics", title: "원칙은 앱이 기억합니다", sub: "4% 규칙 · 부동산 비중 · 국가 배분" },
];

// ── 장면 표시 읽기 ───────────────────────────────────────────
const lines = readFileSync(path.join(here, "raw", "marks.txt"), "utf8").trim().split("\n");
const recordStart = Number(lines.find(l => l.startsWith("RECORD-START")).split(" ")[1]);
const marks = {};
for (const l of lines.filter(l => l.startsWith("PREVIEW-MARK"))) {
  const [, key, edge, time] = l.split(" ");
  marks[key] ??= {};
  marks[key][edge] = Number(time) - recordStart;
}
const scenes = SCENES.filter(s => marks[s.key]?.start != null && marks[s.key]?.end != null)
  .map(s => ({ ...s, start: marks[s.key].start, dur: marks[s.key].end - marks[s.key].start }));
if (scenes.length === 0) throw new Error("장면 표시가 없습니다 — raw/marks.txt 를 보세요");

// 길이 맞추기: 전환이 겹치는 만큼 빼고 30초 안으로
let total = scenes.reduce((s, x) => s + x.dur, 0) - FADE * (scenes.length - 1);
if (total > MAX) {
  const k = (MAX + FADE * (scenes.length - 1)) / (total + FADE * (scenes.length - 1));
  for (const s of scenes) s.dur *= k;   // 장면 끝을 잘라 낸다(시작은 그대로)
  total = MAX;
}
console.log(scenes.map(s => `${s.key} ${s.start.toFixed(2)}+${s.dur.toFixed(2)}`).join("\n"), `\n합계 ${total.toFixed(2)}초`);

// ── 자막 띠 그림 (Pretendard) ────────────────────────────────
const browser = await playwright.chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H } });
const fonts = pathToFileURL(path.join(here, "..", "promo", "fonts")).href;
for (const [i, s] of scenes.entries()) {
  await page.setContent(`<!doctype html><html><head><meta charset="utf-8"><style>
    @font-face { font-family: P; font-weight: 500; src: url("${fonts}/Pretendard-Medium.woff2"); }
    @font-face { font-family: P; font-weight: 800; src: url("${fonts}/Pretendard-ExtraBold.woff2"); }
    html, body { margin: 0; width: ${W}px; height: ${H}px; background: #F4F7F8; font-family: P; }
    .t { position: absolute; left: 0; right: 0; top: 96px; text-align: center; font-size: 62px; font-weight: 800; color: #0B1017; letter-spacing: -1.4px; }
    .s { position: absolute; left: 0; right: 0; top: 186px; text-align: center; font-size: 34px; font-weight: 500; color: #5E6A75; }
  </style></head><body><div class="t">${s.title}</div><div class="s">${s.sub}</div></body></html>`);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(work, `bg-${i}.png`) });
}
await browser.close();

// ── 장면마다 자르고 얹기 ─────────────────────────────────────
// 녹화(1206×2622 안팎)를 띠 아래 칸에 맞춘다: 높이 H-TOP-40, 가운데.
const vh = H - TOP - 40;
const parts = [];
for (const [i, s] of scenes.entries()) {
  const part = path.join(work, `scene-${i}.mp4`);
  execFileSync("ffmpeg", [
    "-y", "-loglevel", "error",
    "-loop", "1", "-t", s.dur.toFixed(3), "-i", path.join(work, `bg-${i}.png`),
    "-ss", s.start.toFixed(3), "-t", s.dur.toFixed(3), "-i", raw,
    "-filter_complex",
    `[1:v]fps=30,scale=-2:${vh}:flags=lanczos,setsar=1[app];` +
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
const file = path.join(out, "app-preview-886x1920.mp4");
execFileSync("ffmpeg", [
  "-y", "-loglevel", "error", ...inputs,
  ...(parts.length > 1 ? ["-filter_complex", filter.replace(/;$/, ""), "-map", "[v]"] : []),
  // 애플: H.264, 30fps 이하. 소리는 없어도 되지만 무음 트랙을 넣으면 업로드가 덜 까다롭다.
  "-f", "lavfi", "-t", total.toFixed(3), "-i", "anullsrc=channel_layout=stereo:sample_rate=44100",
  ...(parts.length > 1 ? ["-map", `${parts.length}:a`] : ["-map", "0:v", "-map", "1:a"]),
  "-c:v", "libx264", "-profile:v", "high", "-level", "4.0", "-pix_fmt", "yuv420p", "-r", "30", "-crf", "18",
  "-c:a", "aac", "-b:a", "128k", "-shortest", "-movflags", "+faststart", file,
]);
writeFileSync(path.join(out, "scenes.txt"), scenes.map(s => `${s.key}\t${s.dur.toFixed(2)}s\t${s.title}`).join("\n") + "\n");
console.log("완성:", file);
