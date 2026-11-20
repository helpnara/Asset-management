#!/bin/bash
# macOS 러너에서 읽고 바로 채점한다 — 로그만 보면 된다 (docs/25).
cd "$(dirname "$0")"
swift ocr.swift shots/*.png > ocr.raw 2> ocr.err
grep -v '^OCR' ocr.raw | head -40
grep '^OCR' ocr.raw | cut -f2- > ocr.jsonl
echo "── 읽은 줄 보기 (a1, 보정 켬) ──"; python3 -c "
import json
for l in open('ocr.jsonl'):
    o=json.loads(l)
    if o['file']=='a1' and o['fix']==1: print(f\"{1-o['y']-o['h']:.3f} {o['x']:.2f} {o['h']:.3f} {o['conf']:.2f} {o['text']}\")
"
echo "── 채점 ──"; python3 score.py ocr.jsonl 1; python3 score.py ocr.jsonl 0 | tail -1
