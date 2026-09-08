#!/usr/bin/env python3
"""생성한 `@NSManaged` 선언이 모델 파일과 **같은 칸을 말하는지** 대조한다.

    python3 Tools/coredata/check-managed-matches-model.py

**빠진 칸은 컴파일을 통과한다.** `@NSManaged` 선언이 하나 없으면 그 값을
읽는 코드가 없을 뿐 빌드는 멀쩡하고, 화면에서 값 하나가 조용히 비는 것으로만
드러난다. 그래서 컴파일러가 아니라 여기서 잡는다.

파일 둘만 읽는다 — 생성기를 다시 돌리지 않으므로 "고치고 하나만 다시 돌렸다"
를 잡아낸다.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

MODEL = "App/SlowRich.xcdatamodeld/SlowRich.xcdatamodel/contents"
GENERATED = "App/Persistence/Generated"

# `@NSManaged var x: T` 와 `@NSManaged @objc(x) var xNumber: NSNumber?` 둘 다.
MANAGED_RE = re.compile(
    r"@NSManaged\s+(?:@objc\((\w+)\)\s+)?var (\w+)\s*:", re.M)


def from_model():
    out = {}
    for entity in ET.parse(MODEL).getroot().findall("entity"):
        names = {a.get("name") for a in entity.findall("attribute")}
        names |= {r.get("name") for r in entity.findall("relationship")}
        out[entity.get("name")] = names
    return out


def from_generated():
    out = {}
    for name in sorted(os.listdir(GENERATED)):
        if not name.endswith("+CoreDataProperties.swift"):
            continue
        entity = name.split("+")[0]
        source = open(os.path.join(GENERATED, name), encoding="utf-8").read()
        # `@objc(x)` 가 있으면 KVC 이름은 그쪽이다 — 모델의 칸 이름과 견줄 것은
        # Swift 프로퍼티 이름이 아니라 이것이다.
        out[entity] = {objc or swift for objc, swift in MANAGED_RE.findall(source)}
    return out


def main():
    model, generated = from_model(), from_generated()
    problems = []

    for entity in sorted(set(model) | set(generated)):
        if entity not in generated:
            problems.append(f"{entity}: 생성물이 없습니다")
            continue
        if entity not in model:
            problems.append(f"{entity}: 모델에 없는 엔티티의 생성물이 남아 있습니다")
            continue
        missing = sorted(model[entity] - generated[entity])
        extra = sorted(generated[entity] - model[entity])
        if missing:
            problems.append(f"{entity}: 선언이 없는 칸 — {', '.join(missing)}")
        if extra:
            problems.append(f"{entity}: 모델에 없는 선언 — {', '.join(extra)}")

    # 클래스 파일도 엔티티마다 하나씩 있어야 한다.
    for entity in sorted(model):
        if not os.path.exists(os.path.join(GENERATED, f"{entity}+CoreDataClass.swift")):
            problems.append(f"{entity}: 클래스 파일이 없습니다")

    if problems:
        print("생성물이 모델과 어긋납니다:\n", file=sys.stderr)
        for line in problems:
            print(f"  · {line}", file=sys.stderr)
        print("\n다시 뽑으세요:", file=sys.stderr)
        print("  python3 Tools/coredata/generate-managed-classes.py", file=sys.stderr)
        sys.exit(1)

    fields = sum(len(v) for v in generated.values())
    print(f"맞습니다 — 엔티티 {len(generated)}개 · 선언 {fields}개")


if __name__ == "__main__":
    main()
