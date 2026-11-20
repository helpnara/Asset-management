// "완벽한 OCR" — 가상 캡처의 글자 덩어리와 위치를 그대로 뽑는다 (기기 텍스트 인식이 거의 100% 라서, 11-20).
// 읽기 규칙(평가금액 고르기 · 이름 맞추기 · 검산)만 따로 시험하려는 것. 출력: ideal.jsonl (ocr.jsonl 과 같은 꼴)
import { createRequire } from 'module';
const { chromium } = createRequire(import.meta.url)('playwright');
import fs from 'fs';
const truth = JSON.parse(fs.readFileSync('truth.json', 'utf8'));
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 402, height: 874 }, deviceScaleFactor: 3 });
const out = [];
for (const t of truth) {
  await page.goto('file://' + process.cwd() + '/shots/' + t.file + '.html');
  await page.evaluate(() => document.fonts.ready);
  const lines = await page.evaluate(() => {
    const res = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walker.nextNode())) {
      const text = n.textContent.trim();
      if (!text) continue;
      const range = document.createRange(); range.selectNodeContents(n);
      // 꺾인 글자는 줄마다 따로 (Vision 도 줄 단위로 준다)
      for (const r of range.getClientRects()) {
        if (r.width < 1) continue;
        // 다른 것(맨 아래 메뉴 막대 등)에 가려진 글자는 캡처에 안 보인다
        const hit = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
        if (!hit || !(hit === n.parentElement || n.parentElement.contains(hit) || hit.contains(n.parentElement))) continue;
        // 말줄임(…)으로 잘린 이름은 보이는 만큼만
        const el = n.parentElement; let shown = text;
        if (getComputedStyle(el).textOverflow === 'ellipsis' && el.scrollWidth > el.clientWidth) {
          const ratio = el.clientWidth / el.scrollWidth; shown = text.slice(0, Math.max(1, Math.floor(text.length * ratio) - 1)) + '…';
        }
        res.push({ text: range.getClientRects().length > 1 ? null : shown, x: r.left / 402, top: r.top / 874, w: r.width / 402, h: r.height / 874 });
      }
    }
    return res;
  });
  // 여러 줄로 꺾인 글자 노드는 줄별 글자를 근사 — 꺾인 자리에서 나눈다
  for (const l of lines) {
    if (l.text === null) continue;
    out.push({ file: t.file, fix: 1, text: l.text, conf: 1, x: l.x, y: 1 - l.top - l.h, w: l.w, h: l.h });
  }
  // 줄바꿈된 노드 처리: 펀드 이름(두 줄)
  const wrapped = await page.evaluate(() => {
    const res = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    let n;
    while ((n = walker.nextNode())) {
      const text = n.textContent.trim(); if (!text) continue;
      const range = document.createRange(); range.selectNodeContents(n);
      const rects = [...range.getClientRects()]; if (rects.length < 2) continue;
      // 글자마다 위치를 재서 줄을 가른다
      let cur = '', curTop = null, curRect = null;
      for (let i = 0; i < n.textContent.length; i++) {
        const rr = document.createRange(); rr.setStart(n, i); rr.setEnd(n, i + 1);
        const b = rr.getBoundingClientRect();
        if (curTop !== null && Math.abs(b.top - curTop) > 4) { res.push({ text: cur.trim(), r: curRect }); cur = ''; curRect = null; }
        curTop = b.top; cur += n.textContent[i];
        curRect = curRect ? { left: Math.min(curRect.left, b.left), top: Math.min(curRect.top, b.top), right: Math.max(curRect.right, b.right), bottom: Math.max(curRect.bottom, b.bottom) } : { left: b.left, top: b.top, right: b.right, bottom: b.bottom };
      }
      if (cur.trim()) res.push({ text: cur.trim(), r: curRect });
    }
    return res;
  });
  for (const w of wrapped) out.push({ file: t.file, fix: 1, text: w.text, conf: 1, x: w.r.left / 402, y: 1 - w.r.bottom / 874, w: (w.r.right - w.r.left) / 402, h: (w.r.bottom - w.r.top) / 874 });
}
fs.writeFileSync('ideal.jsonl', out.map(o => JSON.stringify(o)).join('\n') + '\n');
await browser.close();
console.log(out.length, 'lines');
