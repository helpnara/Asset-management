import CoreData
import Foundation

/// **CloudKit 이 요구하는 기본값을 모델에 심는다.**
///
/// CloudKit 미러링은 저장소를 열 때 이렇게 막는다:
///
///     NSCocoaErrorDomain 134060
///     CloudKit integration requires that all attributes be optional, or have
///     a default value set. The following attributes are marked non-optional
///     but do not have a default value:
///       Account: id
///       ... (16개)
///
/// **왜 파일에 적어 둔 기본값으로는 안 되나.** `.xcdatamodeld` 에는 열여섯 곳
/// 모두 `defaultValueString="00000000-0000-0000-0000-000000000000"` 이 적혀
/// 있다. 그런데 Core Data 는 **UUID 속성에서 그 글자를 읽지 않는다** — Xcode
/// 모델 편집기가 UUID 에 기본값 칸을 아예 안 내주는 것과 같은 이유다. 런타임의
/// `attribute.defaultValue` 는 `nil` 이고, CloudKit 은 그걸 본다.
/// (`momc` 는 통과시킨다. 컴파일 때는 안 걸리고 기기에서만 걸린다.)
///
/// **왜 옵셔널로 바꾸지 않나.** 옵셔널 여부는 **판본 해시에 들어간다.** 열여섯
/// 곳을 옵셔널로 돌리면 해시가 달라지고, SwiftData 가 쓰던 저장소가 안 열린다
/// — 사용자에게는 몇 달치 기록이 사라진 것으로 보인다 (4차 1단계, 걸린 것 2번).
/// **기본값은 해시에 안 들어간다.** 그래서 이 길을 쓴다: 저장소 호환성은
/// 그대로 두고, 모델을 만든 직후에 값을 하나 심는다.
///
/// SwiftData 가 이걸 어떻게 넘겼는지도 이제 설명이 된다 — 파일이 아니라
/// **코드로** 심었을 것이다. 우리 저장소의 속성이 필수인 채로 미러링이
/// 되고 있었으니 그 길밖에 없다.
///
/// 심는 값은 **아무도 안 보는 값**이다. `awakeFromInsert` 가 새 객체마다
/// 진짜 값을 곧바로 덮어쓰고, iCloud 에서 내려온 레코드는 제 값을 들고 온다.
/// 기본값은 CloudKit 의 검사를 통과하기 위해서만 있다.
enum ModelDefaults {

    /// 파일에서 읽은 모델을 **고칠 수 있는 것으로 바꾼다.**
    ///
    /// 컴파일된 `.momd` 에서 읽은 모델은 **못 고친다.** 손대면 그 자리에서
    /// 죽는다 — CI 검사기가 이걸로 한 번 죽어서 알았다:
    ///
    ///     NSInternalInconsistencyException: 'Can't modify an immutable model.'
    ///       -[NSAttributeDescription setDefaultValue:]
    ///
    /// **이걸 모르고 배포했으면 앱이 뜨자마자 죽었다.** 저장 계층을 갈아타는
    /// 동안 세운 심판 중 이게 제일 값했다.
    ///
    /// `copy()` 는 안 쓴다 — 변경 불가 객체의 `copy()` 가 자기 자신을 돌려주는
    /// 것은 Foundation 의 흔한 최적화라, 됐는지 안 됐는지가 실행해 봐야 안다.
    /// `byMerging:` 은 **엔티티를 옮겨 담아 새 모델을 만든다.** 하나만 넣어도
    /// 그렇다. 판본 해시는 이름·타입·옵셔널에서 나오므로 그대로다.
    static func editableCopy(of model: NSManagedObjectModel) -> NSManagedObjectModel {
        NSManagedObjectModel(byMerging: [model]) ?? model
    }

    /// 필수인데 기본값이 없는 속성에 값을 심고, 심은 곳의 이름을 돌려준다.
    ///
    /// **`editableCopy(of:)` 를 거친 모델에만** 쓴다. 그리고 저장소
    /// 코디네이터가 가져가기 전에 불러야 한다 — 한 번 쓰이면 또 못 고친다.
    @discardableResult
    static func fill(_ model: NSManagedObjectModel) -> [String] {
        var filled: [String] = []
        for entity in model.entities {
            for case let attribute as NSAttributeDescription in entity.properties
            where !attribute.isOptional && attribute.defaultValue == nil {
                guard let value = zero(for: attribute.attributeType) else { continue }
                attribute.defaultValue = value
                filled.append("\(entity.name ?? "?").\(attribute.name)")
            }
        }
        return filled
    }

    /// 타입별 "아무 뜻 없는 값".
    ///
    /// 오늘 실제로 필요한 것은 UUID 하나뿐이다 — 나머지 타입은 모델 파일의
    /// `defaultValueString` 을 Core Data 가 읽어 준다. 그래도 전부 적어 두는
    /// 것은, 다음에 타입 하나가 늘었을 때 **또 기기에서 처음 알게 되지**
    /// 않으려는 것이다.
    private static func zero(for type: NSAttributeType) -> Any? {
        switch type {
        case .UUIDAttributeType:
            return UUID(uuidString: "00000000-0000-0000-0000-000000000000")
        case .stringAttributeType:
            return ""
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
            return 0
        case .doubleAttributeType, .floatAttributeType:
            return 0.0
        case .decimalAttributeType:
            return NSDecimalNumber.zero
        case .booleanAttributeType:
            return false
        case .dateAttributeType:
            return Date(timeIntervalSinceReferenceDate: 0)
        case .binaryDataAttributeType:
            return Data()
        case .URIAttributeType:
            return URL(string: "about:blank")
        default:
            // Transformable · Undefined 는 값 하나로 못 정한다. 여기서 조용히
            // 넘기면 CloudKit 이 기기에서 막으므로, CI 검사기가 대신 잡는다
            // (Tools/coredata/check-cloudkit-model.swift).
            return nil
        }
    }
}
