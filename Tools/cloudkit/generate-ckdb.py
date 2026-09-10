#!/usr/bin/env python3
"""Core Data 모델에서 CloudKit 스키마 파일(.ckdb)을 만든다.

    python3 Tools/cloudkit/generate-ckdb.py > Tools/cloudkit/slowrich.ckdb

**원본은 `App/SlowRich.xcdatamodeld` 다.** 예전에는 `@Model` 선언을 읽었는데,
4차 1b-2 로 그것이 사라졌다. 그때 이 생성기만 못 따라와서, 돌리면 **빈 스키마가
나오는 상태**로 한동안 있었다 (CI 는 파일끼리 대조만 해서 안 걸렸다).

**왜 손으로 안 쓰고 만들어 내나.** 엔티티가 15개, 필드가 백 개가 넘는다. 손으로
옮겨 적으면 빠뜨리고, 나중에 칸을 더할 때 또 어긋난다.

**규칙은 애플이 정한 것이다** (WWDC19 "Using Core Data With CloudKit").

 · 엔티티 하나 → 레코드 타입 `CD_<엔티티>`
 · 속성 하나 → 필드 `CD_<속성>`
 · 모든 레코드에 `CD_entityName` — 엔티티 상속 때문에 진짜 이름을 따로 든다
 · 길이가 변하는 값(String·Data)은 1MB 를 넘을 수 있어 `CD_<속성>_ckAsset` 이
   딸린다. Core Data 가 알아서 외부 에셋으로 넘긴다
 · **다대일 관계는 상대 레코드의 UUID 를 그대로 들고 있는다.** 일대다 쪽은
   저장하지 않는다 — 역관계에서 유도된다
 · 다대다는 `CDMR` 조인 레코드가 생기는데, **이 앱에는 다대다가 없다**

**타입 매핑은 확인했다.** UUID 는 STRING 이고, 관계는 레퍼런스가 아니라 상대
UUID 를 담은 STRING 이다. 그래도 이것은 문서를 읽어 옮긴 것이지 실제로 돌려
본 것이 아니다 — **진짜 검증은 앱이 실제로 동기화되는지 보는 것**이고,
그래서 `더보기 → 동기화` 에 마지막 내보내기 성공·실패를 띄운다.
"""
import sys
import xml.etree.ElementTree as ET

MODEL = "App/SlowRich.xcdatamodeld/SlowRich.xcdatamodel/contents"

# `.xcdatamodeld` 가 쓰는 이름 그대로.
TYPE_MAP = {
    "String": "STRING",
    "Integer 16": "INT64",
    "Integer 32": "INT64",
    "Integer 64": "INT64",
    "Boolean": "INT64",       # CloudKit 에 불리언 타입이 없다
    "Double": "DOUBLE",
    "Float": "DOUBLE",
    "Decimal": "DOUBLE",
    "Date": "TIMESTAMP",
    # UUID 는 STRING 이다. CloudKit Console 에도 String 으로 보인다 (확인함).
    "UUID": "STRING",
    "Binary": "BYTES",
    "URI": "STRING",
}

# 에셋 필드(`_ckAsset`)가 딸리는 타입.
#
# String·Binary 는 확실하다 — CloudKit 레코드가 1MB 로 제한되는데 Core Data
# 속성에는 한계가 없어서, 넘치면 외부 에셋으로 넘긴다.
#
# **UUID 는 애매해서 넣어 둔다.** 고정 길이라 필요 없어 보이지만 자료마다
# 말이 갈린다. 여기서 비대칭이 중요하다 — 안 쓰는 필드가 스키마에 있는 것은
# 무해하지만, **써야 하는데 없으면 Production 이 거부한다.** 그리고 Production
# 스키마는 지울 수 없으므로, 모자라서 실패하는 쪽이 남아서 지저분한 쪽보다
# 훨씬 비싸다.
ASSET_BACKED = {"String", "Binary", "UUID", "URI"}


def fields_of(entity):
    """(필드이름, CloudKit타입, 에셋딸림). 모델에 적힌 순서를 지킨다.

    순서를 지키는 것은 멋이 아니다 — 이 파일은 사람이 diff 로 읽는 물건이라,
    순서가 흔들리면 칸 하나 더한 커밋이 백 줄짜리로 보인다.
    """
    out = []
    for child in entity:
        if child.tag == "attribute":
            kind = child.get("attributeType")
            if kind not in TYPE_MAP:
                sys.exit(f"모르는 타입입니다: {entity.get('name')}.{child.get('name')}"
                         f": {kind} — TYPE_MAP 에 더하세요")
            out.append((child.get("name"), TYPE_MAP[kind], kind in ASSET_BACKED))
        elif child.tag == "relationship":
            # 일대다는 저장하지 않는다 — 역관계에서 유도된다.
            if child.get("toMany") == "YES":
                continue
            out.append((child.get("name"), "STRING", False))
    return out


def main():
    entities = sorted(ET.parse(MODEL).getroot().findall("entity"),
                      key=lambda e: e.get("name"))

    print("DEFINE SCHEMA")
    print()
    for entity in entities:
        print(f"    RECORD TYPE CD_{entity.get('name')} (")
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
        # **레코드를 존 사이로 옮길 때** Core Data 가 붙이는 영수증. 공유
        # (`share(_:to:)`)가 기존 레코드를 공유 존으로 옮기면서 이 칸을 쓰는데,
        # 없으면 Production 이 통째로 거부한다 — 기기에서 이렇게 막혔다 (4차 2b ③):
        #     Cannot create or modify field 'CD_moveReceipt' in record 'CD_ChangeLog'
        # 가변 길이라 `_ckAsset` 딸림 필드도 함께 간다.
        print("        CD_moveReceipt  BYTES,")
        print("        CD_moveReceipt_ckAsset ASSET,")
        for field, kind, asset in fields_of(entity):
            print(f"        CD_{field} {kind},")
            if asset:
                print(f"        CD_{field}_ckAsset ASSET,")
        # private database 전용이라 소유자만 읽고 쓴다.
        print('        GRANT WRITE TO "_creator",')
        print('        GRANT CREATE TO "_creator",')
        print('        GRANT READ TO "_creator"')
        print("    );")
        print()

    # **공유의 레코드 타입.** 우리 모델에는 없지만 CloudKit 이 요구한다.
    #
    # 기기에서 이렇게 막혔다 (4차 2b):
    #
    #     Cannot create new type cloudkit.share in production schema
    #
    # CKShare 는 `cloudkit.share` 라는 시스템 레코드 타입으로 저장된다.
    # CloudKit 은 그것을 **Development 에서 앱이 처음 공유를 시도할 때**
    # 자동으로 만든다. 그런데 이 앱은 맥이 없어 Development 에서 돌아간 적이
    # 없고 TestFlight(Production)만 썼다. Production 은 타입을 즉석에서
    # 안 만들어 주므로 공유 레코드 자체를 저장할 수 없었다.
    #
    # `CD_*` 타입에서 한 번 겪은 함정(CLAUDE.md "CloudKit 스키마는 저절로
    # 생기지 않는다")을 시스템 타입에서 다시 겪은 것이다. 그래서 여기서
    # 함께 뽑아 같은 길(apply → Deploy)로 올린다.
    #
    # 필드는 시스템 필드뿐이다 — 참가자·권한 같은 것은 CloudKit 이
    # 내부적으로 관리하고 스키마에 드러내지 않는다. 읽기는 `_world` 다:
    # 초대 링크를 받은 사람이 수락하기 전에 공유 정보를 읽어야 하기
    # 때문이고, 레코드 내용 접근은 별개로 CKShare 의 참가자 목록이 정한다.
    # **따옴표가 필요하다.** 점이 든 이름을 그냥 쓰면 서버 파서가 막는다:
    #     Encountered "." at line 433, column 25. Was expecting "("
    # 로컬 `validate` 는 통과시켰다 — 그쪽이 더 너그럽다. 서버가 판정한다.
    #
    # 아래 셋은 **서버가 스스로 채운 것**이다. 시스템 필드만 넣어 apply 했더니
    # CloudKit 이 공유 타입으로 알아보고 이 셋을 붙여 돌려줬다. 파일은 서버가
    # 실제로 가진 모양을 적는다 — `cloudkit.title` 이 초대 화면의 제목이다.
    print('    RECORD TYPE "cloudkit.share" (')
    print('        "___createTime"               TIMESTAMP,')
    print('        "___createdBy"                REFERENCE,')
    print('        "___etag"                     STRING,')
    print('        "___modTime"                  TIMESTAMP,')
    print('        "___modifiedBy"               REFERENCE,')
    print('        "___recordID"                 REFERENCE,')
    print('        "cloudkit.thumbnailImageData" BYTES,')
    print('        "cloudkit.title"              STRING,')
    print('        "cloudkit.type"               STRING,')
    print('        GRANT WRITE TO "_creator",')
    print('        GRANT READ TO "_world"')
    print("    );")
    print()


if __name__ == "__main__":
    main()
