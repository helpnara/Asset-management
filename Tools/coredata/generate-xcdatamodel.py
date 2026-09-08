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

CloudKit 미러링은 속성이 **옵셔널이거나 기본값이 있어야** 한다. 이 앱은
`@Model` 마다 기본값을 적는 쪽을 골랐다(ADR-0001 표). 그러니 **속성은
옵셔널이 아니다** — Swift 가 `?` 를 붙인 열넷만 옵셔널이다.

처음에는 145개를 전부 옵셔널로 뽑았다가 엔티티 15개의 판본 해시가 **하나도**
안 맞았다. 옵셔널 여부는 해시에 들어간다.

 · 옵셔널은 Swift 선언 그대로
 · 기본값은 리터럴인 것만 적는다 (해시에는 안 들어가지만 CloudKit 이 본다)
 · 유니크 제약 없음
 · 모든 관계가 optional, 역관계가 반드시 있다
 · `usedWithCloudKit="YES"`
"""
import os
import plistlib
import re
import sys

MODEL_RE = re.compile(r"@Model\s*\n\s*final class (\w+)\s*\{(.*?)\n\}", re.S)
# 저장 프로퍼티만. 계산 프로퍼티(`var x: T {`)는 걸러진다 — 그 줄은 `{` 로
# 끝나서 아래의 `=` 도 줄끝도 만나지 못한다.
#
# **기본값까지 잡는다.** `var name: String = ""` 의 `""` 가 세 번째 무리다.
FIELD_RE = re.compile(
    r"^\s{4}var (\w+)\s*:\s*([^\n={]+?)\s*(?:=\s*([^\n]+))?$", re.M)
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
    for field, raw, _ in FIELD_RE.findall(body):
        swift = raw.strip().rstrip("?")
        if swift in class_names:
            out.append((field, swift, None, False))
    return out


# Swift 기본값 → Core Data `defaultValueString`.
#
# **판본 해시에는 안 들어간다.** 그래도 적는 이유는 CloudKit 때문이다 —
# 미러링은 속성이 옵셔널이거나 기본값이 있어야 한다(ADR-0001). 이 앱은
# 기본값 쪽을 골랐으므로 그 값이 모델에도 있어야 말이 맞는다.
#
# `UUID()` · `Date.now` · 열거형 rawValue 처럼 **리터럴이 아닌 것은 건너뛴다.**
# Core Data 에 적을 수 있는 꼴이 아니고, 해시에 안 들어가므로 없어도 무방하다.
def default_string(raw, kind):
    """Core Data 가 적을 수 있는 기본값. 없으면 그 타입의 빈 값을 준다.

    **비어 있으면 안 된다.** `momc` 가 CloudKit 모델에서 막는다:

        error: Account.id must have a default value [8]

    Swift 쪽 기본값이 리터럴이면 그대로 쓰고, `UUID()` · `Date.now` ·
    열거형 rawValue 처럼 여기서 계산할 수 없는 것은 **자리만 채운다.**
    실제 값은 언제나 이니셜라이저가 넣으므로 이 자리 값이 쓰이는 일은 없고,
    판본 해시에도 안 들어간다.
    """
    value = None
    if raw is not None:
        # `var roleNote: String = ""   // "본인"` 처럼 뒤에 주석이 붙는다.
        text = re.sub(r"\s+//.*$", "", raw.strip())
        if text == "true":
            value = "YES"
        elif text == "false":
            value = "NO"
        elif re.fullmatch(r"-?\d+(_\d+)*", text):
            value = text.replace("_", "")
        elif re.fullmatch(r'"[^"\\]*"', text):
            value = text[1:-1]

    if value is not None:
        return value
    # 자리 채우기.
    if kind == "String":
        return ""
    if kind == "Boolean":
        return "NO"
    if kind == "UUID":
        return "00000000-0000-0000-0000-000000000000"
    if kind in ("Integer 64", "Double"):
        return "0"
    return None                 # Date · Binary 는 아래에서 따로 적는다


def attributes(body, class_names):
    out = []
    for field, raw, default in FIELD_RE.findall(body):
        swift = raw.strip()
        # **옵셔널은 Swift 가 말하는 그대로 적는다.** 전부 옵셔널로 두었더니
        # 엔티티 15개의 판본 해시가 **하나도** 안 맞았다 — 옵셔널 여부는 해시에
        # 들어가기 때문이다. ADR-0001 이 요구한 것은 "기본값 **또는** 옵셔널"
        # 이고 이 앱은 기본값 쪽을 골랐다. 그러니 속성은 옵셔널이 아니다.
        optional = swift.endswith("?")
        swift = swift.rstrip("?")
        if swift.startswith("[") or swift in class_names:
            continue                       # 관계는 따로 쓴다
        if swift not in ATTRIBUTE_TYPES:
            sys.exit(f"모르는 타입입니다: {field}: {swift} — ATTRIBUTE_TYPES 에 더하세요")
        kind, scalar = ATTRIBUTE_TYPES[swift]
        out.append((field, kind, scalar, optional, default_string(default, kind)))
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
        for field, kind, scalar, optional, default in attributes(body, class_names):
            parts = [f'name="{field}"']
            if optional:
                parts.append('optional="YES"')
            parts.append(f'attributeType="{kind}"')
            if optional:
                # **옵셔널에는 기본값을 붙이지 않는다.** 붙이면 Core Data 가
                # `nil` 대신 그 값을 돌려주는데, 이 앱에서 `nil` 은 "안 정했다"
                # 라는 **뜻이 있는 값**이다.
                #
                # 실제로 크게 당했다: `Account.expectedReturnBP` 에 기본값 0 이
                # 붙어 있어서 `?? 기본수익률` 이 한 번도 안 걸렸고, 모든 덩어리가
                # **연 0% 로 자랐다.** 은퇴 예상이 63.1억에서 21.0억으로 떨어졌는데
                # 화면은 멀쩡해 보였다 (4차 1b-2).
                #
                # 스칼라 힌트도 끈다 — 옵셔널 숫자는 `NSNumber?` 로 다룬다.
                if kind in ("Integer 64", "Double", "Boolean"):
                    scalar = "NO"
            else:
                # 필수 속성에는 반드시 기본값이 있어야 한다 (momc · CloudKit).
                if kind == "Date":
                    # 날짜만 다른 칸을 쓴다. 0 은 2001-01-01 이다.
                    parts.append('defaultDateTimeInterval="0"')
                elif default is not None:
                    parts.append(f'defaultValueString="{default}"')
            parts.append(f'usesScalarValueType="{scalar}"')
            lines.append("        <attribute " + " ".join(parts) + "/>")
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
