#!/usr/bin/env python3
"""`@Model` 에서 Core Data 용 `@NSManaged` 선언을 뽑는다 (4차 B-1b-1).

    python3 Tools/coredata/generate-managed-classes.py

**왜 만들어 내나.** 속성이 145개다. 손으로 옮겨 적으면 반드시 빠뜨리고,
빠뜨린 칸은 컴파일도 통과한다 — 화면에서 값 하나가 조용히 비는 것으로만 드러난다.
1a 에서 모델 파일을 뽑은 것과 같은 이유이고, **같은 곳(`App/Persistence/*.swift`)을
읽으므로** 모델 파일·CloudKit 스키마·이 선언 셋이 어긋날 수 없다.

**⚠️ 1b-2 뒤로는 돌지 않는다.** 저장 계층을 Core Data 로 갈아타면서 `@Model`
선언이 사라졌기 때문이다. 이제 원본은 `App/SlowRich.xcdatamodeld` 이고,
생성물은 **커밋된 채로 손으로 고친다.** CI 가 셋(모델 파일 · 생성물 ·
CloudKit 스키마)이 서로 맞는지 대조하므로 빠뜨리면 막힌다.

이 스크립트는 그 최초 한 벌을 만든 도구로 남겨 둔다 — 어떻게 나왔는지가
남아 있어야 다음 사람이 규칙을 안다.

## 까다로운 곳 셋

1. **옵셔널 스칼라** (`Int?`) 는 `@NSManaged` 가 직접 못 든다. `NSNumber?` 로
   저장하고 `@objc` 로 KVC 이름을 붙인 뒤, 쓰는 쪽 이름은 계산 프로퍼티로
   되돌린다. 그래야 이미 있는 1,700줄이 안 바뀐다.
2. **일대다** 는 `NSSet?` 이다. `[Account]?` 가 아니다 — 정렬해 쓰는 곳
   (`sortedAccounts`)에서 풀어야 하고, 그건 관계마다 한 곳씩 세 곳뿐이다.
3. **`id` · `createdAt`** 은 모델의 기본값이 자리 채우기라
   (`00000000-…` · 2001-01-01) `awakeFromInsert` 에서 진짜 값을 넣어야 한다.
   그 뼈대도 여기서 함께 뽑는데, **익스텐션이 아니라 클래스 본문에 둔다** —
   Swift 는 익스텐션에서 메서드를 재정의할 수 없다. 파일이 둘로 나뉘는 이유다
   (`+CoreDataClass` · `+CoreDataProperties`, Xcode 의 관례와 같다).
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# 1a 의 생성기와 **같은 파서**를 쓴다. 두 벌로 두면 언젠가 어긋난다.
_spec = importlib.util.spec_from_file_location(
    "xcdatamodel", os.path.join(HERE, "generate-xcdatamodel.py"))
xcd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(xcd)

DEST = "App/Persistence/Generated"

# Core Data 가 `@NSManaged` 로 직접 들 수 있는 옵셔널 타입. 이 밖의 옵셔널
# (Int? · Bool? · Double?)은 값 타입이라 NSNumber 를 거쳐야 한다.
OBJECT_TYPES = {"String", "Date", "UUID", "Data"}

HEADER = """// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation
"""


def swift_type(raw):
    """`Int?` · `String` 처럼 Swift 가 적은 그대로."""
    return raw.strip()


def doc_comment(body, start):
    """프로퍼티 바로 위에 붙은 `///` 뭉치를 그대로 가져온다.

    **이 주석이 이 저장소의 자산이다.** "왜 이 칸이 있나" 가 거기 적혀 있고,
    1b-2 에서 원본 선언을 지울 때 같이 사라지면 안 된다. 그래서 생성물이
    데려간다.
    """
    lines = body[:start].split("\n")
    if lines and not lines[-1].strip():
        lines = lines[:-1]                 # 선언 줄 앞의 들여쓰기 조각
    picked = []
    for line in reversed(lines):
        text = line.strip()
        if text.startswith("///"):
            picked.append("    " + text)
        else:
            break                          # 빈 줄이나 다른 코드를 만나면 끝
    return list(reversed(picked))


def properties(entity, body, class_names):
    """(선언 줄들, 옵셔널 스칼라 개수)."""
    lines = []
    tricky = 0

    for match in xcd.FIELD_RE.finditer(body):
        field, raw = match.group(1), match.group(2)
        declared = swift_type(raw)
        bare = declared.rstrip("?")
        if bare.startswith("[") or bare in class_names:
            continue                                  # 관계는 아래에서
        optional = declared.endswith("?")
        docs = doc_comment(body, match.start())
        prefix = ("\n".join(docs) + "\n") if docs else ""

        if optional and bare not in OBJECT_TYPES:
            # 옵셔널 스칼라. NSNumber 로 저장하고 이름만 되돌린다.
            tricky += 1
            lines.append(
                prefix
                + f"    /// `{bare}?` 는 `@NSManaged` 가 직접 못 든다. 저장은 `NSNumber?` 로 하고\n"
                f"    /// KVC 이름만 `{field}` 로 붙여 준다 — 모델의 칸 이름이 그것이기 때문이다.\n"
                f"    @NSManaged @objc({field}) var {field}Number: NSNumber?\n"
                f"\n"
                f"    /// 쓰는 쪽은 예전 그대로 `{declared}` 를 본다.\n"
                f"    var {field}: {declared} {{\n"
                f"        get {{ {field}Number?.{_number_getter(bare)} }}\n"
                f"        set {{ {field}Number = newValue.map(NSNumber.init(value:)) }}\n"
                f"    }}")
        else:
            lines.append(prefix + f"    @NSManaged var {field}: {declared}")

    for field, target, _inverse, is_many in xcd.relationships(body, entity, class_names):
        if is_many:
            lines.append(
                f"    /// 일대다는 `NSSet?` 이다 — `[{target}]?` 가 아니다.\n"
                f"    /// 정렬해 쓰는 곳에서 풀어 쓴다.\n"
                f"    @NSManaged var {field}: NSSet?")
        else:
            lines.append(f"    @NSManaged var {field}: {target}?")

    return lines, tricky


def _number_getter(bare):
    return {"Int": "intValue", "Bool": "boolValue", "Double": "doubleValue"}[bare]


def to_many_accessors(entity, body, class_names):
    """`addToAccounts(_:)` 같은 것들. Core Data 가 KVC 로 부르는 이름이다."""
    out = []
    for field, target, _inverse, is_many in xcd.relationships(body, entity, class_names):
        if not is_many:
            continue
        capital = field[0].upper() + field[1:]
        out.append(f"""
extension {entity} {{

    @objc(add{capital}Object:)
    @NSManaged func addTo{capital}(_ value: {target})

    @objc(remove{capital}Object:)
    @NSManaged func removeFrom{capital}(_ value: {target})

    @objc(add{capital}:)
    @NSManaged func addTo{capital}(_ values: NSSet)

    @objc(remove{capital}:)
    @NSManaged func removeFrom{capital}(_ values: NSSet)
}}""")
    return out


def class_file(entity, body, class_names):
    """클래스 선언과 `awakeFromInsert`.

    **`awakeFromInsert` 는 익스텐션에 못 둔다.** Swift 는 익스텐션에서
    메서드를 재정의할 수 없다. 처음에 프로퍼티 파일에 같이 넣었다가 이걸
    발견했다 — 빌드에 넣기 전에 눈으로 읽어서 잡은 것이 1b-1 의 값이다.

    파일을 둘로 나누는 것은 Xcode 의 관례이기도 하다
    (`+CoreDataClass` · `+CoreDataProperties`).
    """
    fills = []
    for field, raw, default in xcd.FIELD_RE.findall(body):
        declared = swift_type(raw)
        bare = declared.rstrip("?")
        if declared.endswith("?") or bare.startswith("[") or bare in class_names:
            continue
        text = (default or "").strip()
        if bare == "UUID" and text.startswith("UUID("):
            fills.append(f"        {field} = UUID()")
        elif bare == "Date" and text.startswith("Date."):
            fills.append(f"        {field} = .now")
    awake = ""
    if fills:
        body_lines = "\n".join(fills)
        awake = f"""
    /// 모델의 기본값은 **자리 채우기**다 (`00000000-…` · 2001-01-01).
    /// 진짜 값은 여기서 넣는다 — 안 그러면 모든 행의 id 가 같아진다.
    override func awakeFromInsert() {{
        super.awakeFromInsert()
{body_lines}
    }}
"""
    # `final` 을 붙이지 않는다. Core Data 가 런타임에 하위 클래스를 만들 수 있다.
    #
    # **`public` 도 붙이지 않는다.** 앱이 타깃 하나라 얻는 것이 없고, 붙이면
    # `@NSManaged var id` 가 internal 이라 `Identifiable` 준수에서 막힌다:
    #   property 'id' must be declared public because it matches a requirement
    #   in public protocol 'Identifiable'
    # `Identifiable` 은 손으로 붙여야 한다. SwiftData 의 `@Model` 은 거저 줬지만
    # `NSManagedObject` 는 안 준다 — `ForEach` · `sheet(item:)` 이 요구한다.
    return f"""{HEADER}
/// `Identifiable` 은 손으로 붙인다. SwiftData 의 `@Model` 은 거저 줬지만
/// `NSManagedObject` 는 안 준다 — `ForEach` · `sheet(item:)` 이 요구한다.
/// 엔티티마다 `id: UUID` 가 있으므로 준수는 자동으로 합성된다.
@objc({entity})
class {entity}: NSManagedObject, Identifiable {{
{awake}}}
"""


def main():
    all_models = xcd.models()
    # **아무것도 못 찾았으면 손대지 않는다.** 1b-2 로 `@Model` 이 사라진 뒤
    # 무심코 돌렸다가 생성물 서른 개를 **전부 지웠다.** 지우는 것이 찾는 것보다
    # 먼저였던 탓이다. 빈손으로는 아무 일도 하지 않는다.
    if not all_models:
        sys.exit(f"{xcd.SOURCES} 에서 @Model 을 하나도 못 찾았습니다 — "
                 f"아무것도 고치지 않았습니다.\n"
                 f"1b-2 뒤로 원본은 App/SlowRich.xcdatamodeld 입니다 "
                 f"(docs/09-family-sharing.md).")

    class_names = {n for n, _ in all_models}
    os.makedirs(DEST, exist_ok=True)

    # 예전 생성물은 지운다. 엔티티를 지웠는데 파일이 남으면 빌드가 깨진다.
    for name in os.listdir(DEST):
        if name.endswith(".swift"):
            os.remove(os.path.join(DEST, name))

    total_properties = 0
    total_tricky = 0
    for entity, body in all_models:
        lines, tricky = properties(entity, body, class_names)
        total_properties += len(lines)
        total_tricky += tricky

        parts = [HEADER, f"""
extension {entity} {{

    @nonobjc class func fetchRequest() -> NSFetchRequest<{entity}> {{
        NSFetchRequest<{entity}>(entityName: "{entity}")
    }}

""" + "\n\n".join(lines) + "\n}"]
        parts += to_many_accessors(entity, body, class_names)

        with open(os.path.join(DEST, f"{entity}+CoreDataProperties.swift"),
                  "w", encoding="utf-8") as file:
            file.write("\n".join(parts).rstrip() + "\n")
        with open(os.path.join(DEST, f"{entity}+CoreDataClass.swift"),
                  "w", encoding="utf-8") as file:
            file.write(class_file(entity, body, class_names))

    print(f"{len(all_models)}개 엔티티 · 선언 {total_properties}개를 {DEST}/ 에 썼습니다")
    print(f"  옵셔널 스칼라(NSNumber 를 거치는 것): {total_tricky}개")


if __name__ == "__main__":
    main()
