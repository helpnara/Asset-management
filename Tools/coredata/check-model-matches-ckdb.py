#!/usr/bin/env python3
"""Core Data 모델 파일과 CloudKit 스키마 파일이 **같은 것을 말하는지** 대조한다.

    python3 Tools/coredata/check-model-matches-ckdb.py

둘 다 `@Model` 에서 뽑지만, 뽑는 규칙이 다르므로 한쪽만 고치는 실수가 난다.
그리고 어긋났을 때의 값이 비싸다 — 모델이 저장소와 안 맞으면 **앱은 멀쩡히 뜨고
화면만 빈다.** 사용자는 몇 달치 기록이 날아간 것을 본다
(docs/09-family-sharing.md 1단계, 걸린 것 2번).

대조하는 것:

 · 엔티티 집합 == 레코드 타입 집합 (`CD_` 를 뗀 것)
 · 엔티티마다 **속성 + 다대일 관계**의 이름 집합이 같은가

일대다 관계는 양쪽 다 저장하지 않으므로 뺀다 — 역관계에서 유도된다.

이 스크립트는 **파일 둘만 읽는다.** 두 생성기를 다시 돌리지 않으므로,
"고치고 하나만 다시 돌렸다" 를 잡아낸다.
"""
import re
import sys
import xml.etree.ElementTree as ET

MODEL = "App/SlowRich.xcdatamodeld/SlowRich.xcdatamodel/contents"
CKDB = "Tools/cloudkit/slowrich.ckdb"

# CloudKit 이 스스로 붙이는 것들. 우리 모델에는 없어야 정상이다.
SYSTEM_FIELDS = {"entityName"}


def from_model():
    out = {}
    for entity in ET.parse(MODEL).getroot().findall("entity"):
        names = {a.get("name") for a in entity.findall("attribute")}
        # 다대일만. 일대다(`toMany="YES"`)는 저장되지 않는다.
        names |= {r.get("name") for r in entity.findall("relationship")
                  if r.get("toMany") != "YES"}
        out[entity.get("name")] = names
    return out


def from_ckdb():
    source = open(CKDB, encoding="utf-8").read()
    out = {}
    for block in re.finditer(r"RECORD TYPE CD_(\w+) \((.*?)\n    \);", source, re.S):
        entity, body = block.group(1), block.group(2)
        names = set()
        for field in re.findall(r"^\s+CD_(\w+)\s", body, re.M):
            if field.endswith("_ckAsset"):
                continue          # 긴 값이 넘칠 때 쓰는 딸림 필드
            if field in SYSTEM_FIELDS:
                continue
            names.add(field)
        out[entity] = names
    return out


def cloudkit_rules():
    """CloudKit 미러링이 요구하는 것을 여기서 먼저 잡는다.

    안 그러면 `momc` 가 CI 에서 처음 알려 주는데, 그러면 한 바퀴가 10분이다.

        error: Account.id must have a default value [8]

    규칙: **속성은 옵셔널이거나 기본값이 있어야 한다.** 이 앱은 기본값 쪽을
    골랐으므로(ADR-0001) 필수 속성에는 반드시 기본값이 붙어야 한다.
    """
    problems = []
    for entity in ET.parse(MODEL).getroot().findall("entity"):
        for attribute in entity.findall("attribute"):
            if attribute.get("optional") == "YES":
                continue
            has_default = (attribute.get("defaultValueString") is not None
                           or attribute.get("defaultDateTimeInterval") is not None)
            if not has_default:
                problems.append(
                    f"{entity.get('name')}.{attribute.get('name')}: "
                    f"필수인데 기본값이 없습니다 (momc 가 막습니다)")
        for relationship in entity.findall("relationship"):
            if relationship.get("optional") != "YES":
                problems.append(
                    f"{entity.get('name')}.{relationship.get('name')}: "
                    f"관계는 전부 옵셔널이어야 합니다 (ADR-0001)")
            if relationship.get("inverseName") is None:
                problems.append(
                    f"{entity.get('name')}.{relationship.get('name')}: 역관계가 없습니다")
    return problems


def main():
    model, ckdb = from_model(), from_ckdb()
    problems = cloudkit_rules()

    only_model = sorted(set(model) - set(ckdb))
    only_ckdb = sorted(set(ckdb) - set(model))
    if only_model:
        problems.append(f"모델에만 있는 엔티티: {', '.join(only_model)}")
    if only_ckdb:
        problems.append(f"CloudKit 스키마에만 있는 엔티티: {', '.join(only_ckdb)}")

    for entity in sorted(set(model) & set(ckdb)):
        missing = sorted(ckdb[entity] - model[entity])
        extra = sorted(model[entity] - ckdb[entity])
        if missing:
            problems.append(f"{entity}: 모델에 없는 칸 — {', '.join(missing)}")
        if extra:
            problems.append(f"{entity}: CloudKit 스키마에 없는 칸 — {', '.join(extra)}")

    if problems:
        print("모델 파일에 문제가 있습니다:\n", file=sys.stderr)
        for line in problems:
            print(f"  · {line}", file=sys.stderr)
        print("\n둘 다 다시 뽑으세요:", file=sys.stderr)
        print("  python3 Tools/coredata/generate-xcdatamodel.py", file=sys.stderr)
        print("  python3 Tools/cloudkit/generate-ckdb.py > Tools/cloudkit/slowrich.ckdb",
              file=sys.stderr)
        sys.exit(1)

    fields = sum(len(v) for v in model.values())
    print(f"맞습니다 — 엔티티 {len(model)}개 · 칸 {fields}개 · CloudKit 규칙도 통과")


if __name__ == "__main__":
    main()
