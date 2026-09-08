#!/usr/bin/env python3
"""SwiftData 모델에서 Core Data 모델 파일(`.xcdatamodeld`)을 만든다.

    python3 Tools/coredata/generate-xcdatamodel.py

**왜 만들어 내나.** 맥이 없어서 Xcode 의 모델 편집기를 쓸 수 없다
(docs/09-family-sharing.md 1단계). 그렇다고 XML 을 손으로 쓰면 필드 백 개를
옮겨 적다 빠뜨리고, 나중에 `@Model` 을 고칠 때 또 어긋난다.

**`generate-ckdb.py` 와 같은 곳을 읽는다.** 그 스크립트가 이미 `@Model` 을
읽어 CloudKit 스키마를 뽑고 있으므로, 같은 입력에서 Core Data 모델도 뽑으면
**둘이 어긋날 수 없다.** 어긋나는 것이 4차에서 제일 비싼 사고다 — 모델이
저장소와 안 맞으면 앱은 멀쩡히 뜨고 화면만 빈다.

**이 파일은 아직 아무 데도 안 쓰인다.** 1a 단계는 파일을 넣고 CI 가 컴파일하는
것까지다. 저장 계층을 바꾸는 것은 1b 다. 컴파일러를 먼저 심판으로 세워 둔다.

## 지키는 제약 (ADR-0001 — CloudKit 미러링)

 · 모든 속성이 optional — CloudKit 은 필수 필드를 못 만든다
 · 유니크 제약 없음
 · 모든 관계가 optional, 역관계가 반드시 있다
 · `usedWithCloudKit="YES"`
"""
import os
import plistlib
import re
import sys

MODEL_RE = re.compile(r"@Model\s*\n\s*final class (\w+)\s*\{(.*?)\n\}", re.S)
# 저장 프로퍼티만. 계산 프로퍼티(`var x: T {`)는 걸러진다.
FIELD_RE = re.compile(r"^\s{4}var (\w+)\s*:\s*([^\n={]+?)\s*(?:=|$)", re.M)
# `@Relationship(... inverse: \Account.owner)` 바로 다음 줄의 `var accounts: [Account]?`
RELATION_RE = re.compile(
    r"@Relationship\([^)]*inverse:\s*\\(\w+)\.(\w+)[^)]*\)\s*\n\s*var (\w+)\s*:\s*\[(\w+)\]", re.S
)

# Swift 타입 → Core Data 속성 타입.
#
# **`usesScalarValueType` 를 정확히 적는다.** Int·Bool·Double 은 스칼라로
# 저장되고 String·Date·UUID·Data 는 객체다. 여기가 틀리면 컴파일은 되고
# 런타임에 값이 안 붙는다.
ATTRIBUTE_TYPES = {
    "String":  ("String",     "NO"),
    "Int":     ("Integer 64", "YES"),
    "Bool":    ("Boolean",    "YES"),
    "Double":  ("Double",     "YES"),
    "Date":    ("Date",       "NO"),
    "UUID":    ("UUID",       "NO"),
    "Data":    ("Binary",     "NO"),
}

SOURCES = "App/Persistence"
DEST = "App/SlowRich.xcdatamodeld"
MODEL_NAME = "SlowRich"


def models():
    out = []
    for name in sorted(os.listdir(SOURCES)):
        if not name.endswith(".swift"):
            continue
        source = open(os.path.join(SOURCES, name), encoding="utf-8").read()
        for match in MODEL_RE.finditer(source):
            out.append((match.group(1), match.group(2)))
    return sorted(out)


def relationships(body, entity, class_names):
    """(이름, 대상, 역이름, 다대다여부) 목록."""
    out = []
    for inverse_entity, inverse_name, field, target in RELATION_RE.findall(body):
        # `inverse: \Account.owner` 의 Account 는 대상 엔티티와 같아야 한다.
        if inverse_entity != target:
            sys.exit(f"{entity}.{field}: inverse 가 \\{inverse_entity}.{inverse_name} 인데 "
                     f"대상은 [{target}] 입니다 — 둘이 같아야 합니다")
        out.append((field, target, inverse_name, True))
    # 다대일 쪽 (`var owner: Member?`)
    for field, raw in FIELD_RE.findall(body):
        swift = raw.strip().rstrip("?")
        if swift in class_names:
            out.append((field, swift, None, False))
    return out


def attributes(body, class_names):
    out = []
    for field, raw in FIELD_RE.findall(body):
        swift = raw.strip().rstrip("?")
        if swift.startswith("[") or swift in class_names:
            continue                       # 관계는 따로 쓴다
        if swift not in ATTRIBUTE_TYPES:
            sys.exit(f"모르는 타입입니다: {field}: {swift} — ATTRIBUTE_TYPES 에 더하세요")
        kind, scalar = ATTRIBUTE_TYPES[swift]
        out.append((field, kind, scalar))
    return out


def to_one_inverse(all_models, entity, field):
    """다대일 관계의 역이름을 상대 엔티티의 일대다 선언에서 찾는다."""
    class_names = {n for n, _ in all_models}
    for name, body in all_models:
        for rel_field, target, inverse_name, is_many in relationships(body, name, class_names):
            if is_many and target == entity and inverse_name == field:
                return rel_field, name
    sys.exit(f"{entity}.{field}: 짝이 되는 일대다 선언을 못 찾았습니다. "
             f"CloudKit 은 역관계 없는 관계를 못 만듭니다 (ADR-0001)")


def contents(all_models):
    class_names = {n for n, _ in all_models}
    lines = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>']
    lines.append(
        '<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0"'
        ' lastSavedToolsVersion="23507" systemVersion="25A000" minimumToolsVersion="Automatic"'
        ' sourceLanguage="Swift" usedWithCloudKit="YES" userDefinedModelVersionIdentifier="">'
    )
    for entity, body in all_models:
        # `codeGenerationType` 을 적지 않는다. 클래스는 우리가 손으로 들고 있고
        # (계산 프로퍼티가 1,700줄이다), Xcode 가 또 만들면 이름이 겹친다.
        lines.append(f'    <entity name="{entity}" representedClassName="{entity}"'
                     f' syncable="YES">')
        for field, kind, scalar in attributes(body, class_names):
            # **전부 optional 이다.** CloudKit 미러링은 필수 속성을 못 만든다.
            lines.append(f'        <attribute name="{field}" optional="YES"'
                         f' attributeType="{kind}" usesScalarValueType="{scalar}"/>')
        for field, target, inverse_name, is_many in relationships(body, entity, class_names):
            if is_many:
                # 일대다. 지우면 딸린 것도 함께 지운다 — SwiftData 의 `.cascade` 다.
                lines.append(
                    f'        <relationship name="{field}" optional="YES" toMany="YES"'
                    f' deletionRule="Cascade" destinationEntity="{target}"'
                    f' inverseName="{inverse_name}" inverseEntity="{target}"/>')
            else:
                inverse_field, owner = to_one_inverse(all_models, entity, field)
                lines.append(
                    f'        <relationship name="{field}" optional="YES" maxCount="1"'
                    f' deletionRule="Nullify" destinationEntity="{owner}"'
                    f' inverseName="{inverse_field}" inverseEntity="{owner}"/>')
        lines.append("    </entity>")
    lines.append("</model>")
    return "\n".join(lines) + "\n"


def main():
    all_models = models()
    if not all_models:
        sys.exit(f"{SOURCES} 에서 @Model 을 하나도 못 찾았습니다")

    version_dir = os.path.join(DEST, f"{MODEL_NAME}.xcdatamodel")
    os.makedirs(version_dir, exist_ok=True)
    with open(os.path.join(version_dir, "contents"), "w", encoding="utf-8") as file:
        file.write(contents(all_models))
    # 어느 판을 쓸지 적어 두는 파일. 판이 하나뿐이어도 있어야 한다.
    with open(os.path.join(DEST, ".xccurrentversion"), "wb") as file:
        plistlib.dump({"_XCCurrentVersionName": f"{MODEL_NAME}.xcdatamodel"}, file)

    print(f"{len(all_models)}개 엔티티를 {version_dir}/contents 에 썼습니다")
    for name, _ in all_models:
        print(f"  · {name}")


if __name__ == "__main__":
    main()
