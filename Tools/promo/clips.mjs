// 쇼츠 2편(whatif.html)에 넣을 앱 녹화 구간을 1/30초 그림으로 풀어 둔다.
//
//   node Tools/promo/clips.mjs        # → Tools/promo/out/clips/<이름>/0001.jpg …
//
// 원본은 App Store 미리 보기 녹화(Tools/preview/raw — 체험 자료, 가상의 가족). 그림은 다시 만들 수 있어
// 커밋하지 않는다(.gitignore). 구간을 고르는 법은 Tools/preview/README.md 와 같다 — 녹화가 가변 프레임이라
// 입력 앞 `-ss` 로 감지 않고 처음부터 풀어 `trim` 으로 자른다(앞으로 0.6초쯤 밀렸다).
import { execFileSync } from "node:child_process";
import { mkdirSync, readdirSync, renameSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const raw = path.join(here, "..", "preview", "raw");
const out = path.join(here, "out", "clips");

// 쓰는 폭 — whatif.html 의 화면 창(940px)과 같다.
const WIDTH = 940;
export const CLIPS = {
  //   raw-run2.mp4 의 시뮬레이션 — 월 적립 손잡이를 410만 → 670만원으로 끌고, 2049년 예상이 61억 9,249만 →
  //   87억 7,203만원으로 바뀐다(계획보다 25억 7,953만원 많다). 푼 그림을 6장마다 훑어 고름(10-25): 끄는 것은 70~98번째,
  //   금액은 210~216번째에 바뀐다. 그 사이 4초는 `반영 중` 으로 멈춰 있어 **잘라 낸다**(keep — 0부터 센 그림 번호).
  sim: { src: "raw-run2.mp4", from: 289.5, to: 297.5, speed: 1, keep: [[40, 114], [196, 266]] },
  //   App Store 미리 보기와 같은 구간 — 해외 ETF 두 칸을 친다. 키보드를 기다리는 틈을 1.4배로 줄인다.
  review: { src: "raw.mp4", from: 166.8, to: 175.5, speed: 1.4 },
};

for (const [name, clip] of Object.entries(CLIPS)) {
  const dir = path.join(out, name);
  rmSync(dir, { recursive: true, force: true });
  mkdirSync(dir, { recursive: true });
  execFileSync("ffmpeg", [
    "-y", "-loglevel", "error", "-i", path.join(raw, clip.src),
    "-vf", `trim=start=${clip.from}:end=${clip.to},setpts=(PTS-STARTPTS)/${clip.speed},fps=30,scale=${WIDTH}:-2`,
    "-q:v", "3", path.join(dir, "%04d.jpg"),
  ]);
  if (clip.keep) {
    // 남길 구간만 1번부터 다시 번호를 매긴다.
    const files = readdirSync(dir).sort();
    const kept = clip.keep.flatMap(([a, b]) => files.slice(a, b + 1));
    kept.forEach((file, i) => renameSync(path.join(dir, file), path.join(dir, `k${String(i + 1).padStart(4, "0")}.jpg`)));
    for (const file of readdirSync(dir)) if (!file.startsWith("k")) rmSync(path.join(dir, file));
    for (const file of readdirSync(dir)) renameSync(path.join(dir, file), path.join(dir, file.slice(1)));
  }
  console.log(name, readdirSync(dir).length, "장");
}
