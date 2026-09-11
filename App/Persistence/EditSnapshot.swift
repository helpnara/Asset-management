import CoreData
import Foundation

/// **편집 시트의 취소** (docs/08-feedback.md 104번).
///
/// 이 앱의 편집 시트는 값을 살아 있는 객체에 바로 쓰고 자동 저장이 곧 저장해
/// 버린다 — 그래서 `취소` 가 없었고, 잘못 고친 값을 되돌릴 길이 없었다.
/// 열 때 속성과 다대일 관계를 떠 두고, 취소하면 그대로 되돌린다. 새로 만든
/// 것이면 시트가 지운다. `context.rollback()` 은 못 쓴다 — 400ms 마다 저장되어
/// 되돌릴 것이 남아 있지 않다.
struct EditSnapshot {
    private let values: [String: Any]
    private let relations: [String: NSManagedObject]
    private let nilKeys: Set<String>

    @MainActor
    init(of object: NSManagedObject) {
        var values: [String: Any] = [:]
        var relations: [String: NSManagedObject] = [:]
        var nilKeys: Set<String> = []
        for key in object.entity.attributesByName.keys {
            if let value = object.value(forKey: key) { values[key] = value } else { nilKeys.insert(key) }
        }
        for (key, relation) in object.entity.relationshipsByName where !relation.isToMany {
            if let value = object.value(forKey: key) as? NSManagedObject { relations[key] = value } else { nilKeys.insert(key) }
        }
        self.values = values
        self.relations = relations
        self.nilKeys = nilKeys
    }

    @MainActor
    func restore(to object: NSManagedObject) {
        guard !object.isDeleted else { return }
        for (key, value) in values where !isEqual(object.value(forKey: key), value) {
            object.setValue(value, forKey: key)
        }
        for (key, value) in relations where (object.value(forKey: key) as? NSManagedObject) != value {
            object.setValue(value, forKey: key)
        }
        for key in nilKeys where object.value(forKey: key) != nil {
            object.setValue(nil, forKey: key)
        }
    }

    private func isEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
        guard let lhs else { return false }
        return (lhs as AnyObject).isEqual(rhs)
    }
}
