// 긴 가상 화면(make_long.py)을 **스크롤하며 여러 장** 찍은 것처럼 글자 줄을 뽑는다 (226번).
// 두 가지로 찍는다 — `ov`: 한두 줄씩 겹치게(권하는 찍기), `cut`: 겹침 없이 화면 높이만큼(줄이 장 경계에서 잘린다).
// 출력: long.jsonl — {file: "m-list#ov#0", page, text, x, top, w, h} (위에서부터, 그림 크기에 대한 비율)
import { createRequire } from 'module';
const { chromium } = createRequire(import.meta.url)('playwright');
import fs from 'fs';
const truth = JSON.parse(fs.readFileSync('long_truth.json', 'utf8'));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 402, height: 874 }, deviceScaleFactor: 3 });
const out = [];
for (const t of truth) {
  await page.goto('file://' + process.cwd() + '/shots/' + t.file + '.html');
  await page.evaluate(() => document.fonts.ready);
  const height = await page.evaluate(() => document.documentElement.scrollHeight);
  for (const [mode, step] of [['ov', 560], ['cut', 874 - 54 - 70]]) {
    const offsets = [];
    for (let y = 0; ; y += step) { offsets.push(Math.min(y, height - 874)); if (y >= height - 874) break; }
    for (const [index, y] of offsets.entries()) {
      await page.evaluate(y => window.scrollTo(0, y), y);
      const lines = await page.evaluate(() => {
        const res = [];
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let n;
        while ((n = walker.nextNode())) {
          const text = n.textContent.trim();
          if (!text) continue;
          const range = document.createRange(); range.selectNodeContents(n);
          const rects = [...range.getClientRects()];
          // 말줄임(…)으로 잘린 글자는 글자 상자가 여럿으로 쪼개져 칸 밖으로 뻗는다 — 보이는 칸 상자로 잰다
          const box = n.parentElement;
          const clipped = getComputedStyle(box).textOverflow === 'ellipsis' && box.scrollWidth > box.clientWidth;
          if (!clipped && rects.length !== 1) continue;   // 꺾인 글자(펀드 이름)는 이 시험에 없다
          const r = clipped ? box.getBoundingClientRect() : rects[0];
          if (r.width < 1 || r.top < 0 || r.bottom > 874.5) continue;   // 화면 밖 · 경계에 걸린 글자는 못 읽는다
          const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
          if (!hit || !(hit === n.parentElement || n.parentElement.contains(hit) || hit.contains(n.parentElement))) continue;
          const el = n.parentElement; let shown = text;
          if (getComputedStyle(el).textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth) {
            const ratio = el.clientWidth / el.scrollWidth; shown = text.slice(0, Math.max(1, Math.floor(text.length * ratio) - 1)) + '…';
          }
          res.push({ text: shown, x: r.left / 402, top: r.top / 874, w: r.width / 402, h: r.height / 874 });
        }
        return res;
      });
      for (const l of lines) out.push({ file: `${t.file}#${mode}`, page: index, ...l });
    }
  }
}
fs.writeFileSync('long.jsonl', out.map(o => JSON.stringify(o)).join('\n') + '\n');
await browser.close();
const pages = {}; for (const o of out) pages[o.file] = Math.max(pages[o.file] ?? 0, o.page + 1);
console.log(out.length, 'lines', pages);
