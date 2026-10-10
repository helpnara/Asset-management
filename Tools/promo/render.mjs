// 느린 부자 홍보 영상 굽기 — promo.html 을 1/30초씩 찍어 MP4 로.
//
//   node Tools/promo/render.mjs                 # → Tools/promo/out/slowrich-promo.mp4
//   node Tools/promo/render.mjs --stills 2,10,15  # 그 초의 한 장씩 PNG 로 (확인용)
//
// 필요한 것: Node, Playwright(Chromium), ffmpeg. 원격 세션에는 셋 다 있다.
// 화면은 render(t) 하나로 그려지므로 찍을 때마다 같은 그림이 나온다.
import { spawn } from "node:child_process";
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
mkdirSync(out, { recursive: true });

const FPS = 30;
const args = process.argv.slice(2);
const stillsArg = args.includes("--stills") ? args[args.indexOf("--stills") + 1] : null;

const browser = await playwright.chromium.launch();
const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(path.join(here, "promo.html")).href + "?frames");
await page.evaluate(() => window.ready);
const duration = await page.evaluate(() => window.DURATION);

if (stillsArg) {
  for (const s of stillsArg.split(",").map(Number)) {
    await page.evaluate(t => window.render(t), s);
    const file = path.join(out, `still-${String(s).replace(".", "_")}.png`);
    await page.screenshot({ path: file });
    console.log("찍음:", file);
  }
  await browser.close();
  process.exit(0);
}

const file = path.join(out, "slowrich-promo.mp4");
const ffmpeg = spawn("ffmpeg", [
  "-y", "-loglevel", "error",
  "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "mjpeg", "-i", "-",
  "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p",
  "-movflags", "+faststart", file,
], { stdio: ["pipe", "inherit", "inherit"] });

const frames = Math.round(duration * FPS);
for (let i = 0; i < frames; i++) {
  await page.evaluate(t => window.render(t), i / FPS);
  const jpg = await page.screenshot({ type: "jpeg", quality: 95 });
  if (!ffmpeg.stdin.write(jpg)) await new Promise(r => ffmpeg.stdin.once("drain", r));
  if (i % 150 === 0) console.log(`${i}/${frames}`);
}
ffmpeg.stdin.end();
await new Promise((resolve, reject) => ffmpeg.on("close", code => code === 0 ? resolve() : reject(new Error(`ffmpeg ${code}`))));
await browser.close();
console.log("완성:", file);
