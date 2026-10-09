#!/usr/bin/env python3
"""**백업 되돌리기 · 전부 지우기가 모든 엔티티를 지우나** (docs/18 5-2).

`Backup.swift` 의 `restore` 와 `wipeAll` 은 지울 엔티티를 `deleteAll(X.self, …)` 로 하나씩
적는다. 모델에 엔티티를 더하고 여기에 안 적으면 되돌리기 뒤에 옛 자료가 남고, 전부 지우기가
일부를 남긴다 — 아무 오류 없이. 그래서 모델과 대조한다.

가구(`Household`)는 **일부러** 안 지운다 — 공유(`CKShare`)가 매달린 뿌리다.
"""
import os
import plistlib
import re
import sys

ROOT = "App/SlowRich.xcdatamodeld"
BACKUP = "App/Services/Backup.swift"
KEEP = {"Household"}


def current_model_contents():
    with open(os.path.join(ROOT, ".xccurrentversion"), "rb") as file:
        name = plistlib.load(file)["_XCCurrentVersionName"]
    return os.path.join(ROOT, name, "contents")


def function_body(source, signature):
    start = source.find(signature)
    if start < 0:
        sys.exit(f"{BACKUP} 에서 `{signature}` 를 못 찾았습니다")
    # 다음 같은 들여쓰기의 `func` 까지를 몸으로 본다.
    end = source.find("\n    func ", start + len(signature))
    return source[start:end if end > 0 else len(source)]


def main():
    with open(current_model_contents(), encoding="utf-8") as file:
        entities = set(re.findall(r'<entity name="([^"]+)"', file.read()))
    with open(BACKUP, encoding="utf-8") as file:
        source = file.read()

    problems = []
    for signature in ("func restore", "func wipeAll"):
        deleted = set(re.findall(r"deleteAll\((\w+)\.self", function_body(source, signature)))
        missing = sorted(entities - deleted - KEEP)
        unknown = sorted(deleted - entities)
        if missing:
            problems.append(f"`{signature}` 가 안 지우는 엔티티: {', '.join(missing)}")
        if unknown:
            problems.append(f"`{signature}` 가 지우는데 모델에 없는 엔티티: {', '.join(unknown)}")

    if problems:
        print("백업의 지울 목록이 모델과 다릅니다:\n", file=sys.stderr)
        for line in problems:
            print(f"  · {line}", file=sys.stderr)
        print("\nBackup.swift 의 restore · wipeAll 에 deleteAll 을 더하세요.", file=sys.stderr)
        sys.exit(1)
    print(f"백업의 지울 목록 — 엔티티 {len(entities)}개 중 {len(entities - KEEP)}개 모두 (가구는 일부러 남김)")


if __name__ == "__main__":
    main()
