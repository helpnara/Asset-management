// shots/*.html → shots/*.png (1206×2622, @3x). 화면 밖으로 잘린 줄은 정답에서 뺀다 (실제 캡처도 그렇다).
import { createRequire } from 'module';
const { chromium } = createRequire(import.meta.url)('playwright');
import fs from 'fs';
const truth = JSON.parse(fs.readFileSync('truth.json', 'utf8'));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 402, height: 874 }, deviceScaleFactor: 3 });
for (const t of truth) {
  await page.goto('file://' + process.cwd() + '/shots/' + t.file + '.html');
  await page.evaluate(() => document.fonts.ready);
  // 각 종목 줄의 아래 끝이 화면 안에 있는지 — 금액이 다 보여야 읽을 수 있다
  const bottoms = await page.evaluate((names) => names.map(n => {
    const el = [...document.querySelectorAll('div,span')].find(e => e.textContent === n);
    if (!el) return 9999;
    let box = el.closest("div[style*='padding']") || el;
    return box.getBoundingClientRect().bottom;
  }), t.rows.map(r => r.name));
  t.rows.forEach((r, i) => r.visible = bottoms[i] <= 874);
  await page.screenshot({ path: 'shots/' + t.file + '.png' });
}
fs.writeFileSync('truth.json', JSON.stringify(truth, null, 1));
await browser.close();
console.log(truth.map(t => `${t.file}: ${t.rows.filter(r => r.visible).length}/${t.rows.length} 보임`).join('\n'));
