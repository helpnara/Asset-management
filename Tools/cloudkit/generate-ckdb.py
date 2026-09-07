#!/usr/bin/env python3
"""SwiftData 모델에서 CloudKit 스키마 파일(.ckdb)을 만든다.

    python3 Tools/cloudkit/generate-ckdb.py > Tools/cloudkit/slowrich.ckdb

**왜 손으로 안 쓰고 만들어 내나.** 모델이 15개, 필드가 백 개가 넘는다. 손으로
옮겨 적으면 빠뜨리고, 나중에 필드를 더할 때 또 어긋난다. 모델을 읽어서 만들면
`@Model` 을 고칠 때마다 다시 돌리기만 하면 된다.

**규칙은 애플이 정한 것이다** (WWDC19 "Using Core Data With CloudKit").
SwiftData 는 속으로 Core Data 를 쓰므로 같은 규칙을 따른다.

 · 엔티티 하나 → 레코드 타입 `CD_<엔티티>`
 · 속성 하나 → 필드 `CD_<속성>`
 · 모든 레코드에 `CD_entityName` — 엔티티 상속 때문에 진짜 이름을 따로 든다
 · 길이가 변하는 값(String·Data)은 1MB 를 넘을 수 있어 `CD_<속성>_ckAsset` 이
   딸린다. Core Data 가 알아서 외부 에셋으로 넘긴다
 · **다대일 관계는 상대 레코드의 UUID 를 그대로 들고 있는다.** 일대다 쪽은
   저장하지 않는다 — 역관계에서 유도된다
 · 다대다는 `CDMR` 조인 레코드가 생기는데, **이 앱에는 다대다가 없다**
   (구성원→계좌, 계좌→종목, 스냅샷→줄 모두 일대다)

⚠️ **확신하지 못하는 것 둘.** 아래 `UNCERTAIN` 표시를 보라. 그래서 진짜
컨테이너에 바로 적용하지 않고 시험용 컨테이너로 먼저 확인한다
(docs/06-testflight.md).
"""
import glob
import re
import sys

# Swift 타입 → CloudKit 필드 타입.
#
# UNCERTAIN(1): UUID 를 STRING 으로 본다. Core Data 는 레코드 이름으로 UUID
#   문자열을 쓰고 화면(CloudKit Console)에도 문자열로 보이지만, UUID **속성**이
#   BYTES 로 갈 가능성을 배제하지 못했다. 시험용 컨테이너에서 확인한다.
# UNCERTAIN(2): 다대일 관계를 STRING 으로 본다. 애플 설명은 "상대의 UUID 를
#   그대로 들고 있는다" 이므로 CKReference 가 아니라 값일 것이다.
TYPE_MAP = {
    "String": "STRING",
    "Int": "INT64",
    "Bool": "INT64",       # CloudKit 에 불리언 타입이 없다
    "Double": "DOUBLE",
    "Date": "TIMESTAMP",
    "UUID": "STRING",      # UNCERTAIN(1)
    "Data": "BYTES",
}

# 길이가 변해서 에셋이 딸리는 타입.
ASSET_BACKED = {"String", "Data"}

MODEL_RE = re.compile(r"@Model\s*\n\s*final class (\w+)\s*\{(.*?)\n\}", re.S)
# 저장 프로퍼티만. 계산 프로퍼티(`var x: T {`)와 주석은 걸러진다.
FIELD_RE = re.compile(r"^\s{4}var (\w+)\s*:\s*([^\n={]+?)\s*(?:=|$)", re.M)


def swift_models(paths):
    for path in sorted(paths):
        source = open(path, encoding="utf-8").read()
        for match in MODEL_RE.finditer(source):
            yield match.group(1), match.group(2)


def fields_of(body, class_names):
    """(필드이름, CloudKit타입, 에셋딸림) 목록. 일대다 관계는 건너뛴다."""
    out = []
    for name, raw in FIELD_RE.findall(body):
        swift = raw.strip().rstrip("?")
        # 일대다 관계(`[Account]?`)는 저장하지 않는다 — 역관계에서 유도된다.
        if swift.startswith("["):
            continue
        # 다대일 관계(`Member?`)는 상대의 UUID 를 문자열로 들고 있는다.
        if swift in class_names:
            out.append((name, "STRING", False))   # UNCERTAIN(2)
            continue
        if swift not in TYPE_MAP:
            sys.exit(f"모르는 타입입니다: {name}: {swift} — TYPE_MAP 에 더하세요")
        out.append((name, TYPE_MAP[swift], swift in ASSET_BACKED))
    return out


def main():
    models = list(swift_models(glob.glob("App/Persistence/*.swift")))
    class_names = {name for name, _ in models}

    print("DEFINE SCHEMA")
    print()
    for name, body in sorted(models):
        print(f"    RECORD TYPE CD_{name} (")
        # CloudKit 시스템 필드. private database 라 QUERYABLE 인덱스는
        # recordID 하나면 된다 — 쿼리를 쓰지 않기 때문이다.
        print('        "___createTime" TIMESTAMP,')
        print('        "___createdBy"  REFERENCE,')
        print('        "___etag"       STRING,')
        print('        "___modTime"    TIMESTAMP,')
        print('        "___modifiedBy" REFERENCE,')
        print('        "___recordID"   REFERENCE QUERYABLE,')
        # 엔티티 상속을 위해 Core Data 가 진짜 엔티티 이름을 따로 든다.
        print("        CD_entityName   STRING,")
        for field, kind, asset in fields_of(body, class_names):
            print(f"        CD_{field} {kind},")
            if asset:
                print(f"        CD_{field}_ckAsset ASSET,")
        # private database 전용이라 소유자만 읽고 쓴다.
        print('        GRANT WRITE TO "_creator",')
        print('        GRANT CREATE TO "_creator",')
        print('        GRANT READ TO "_creator"')
        print("    );")
        print()


if __name__ == "__main__":
    main()
