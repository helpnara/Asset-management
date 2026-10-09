import CoreData
import Foundation

/// **편집 시트의 취소** (docs/08-feedback.md 104번).
///
/// 이 앱의 편집 시트는 값을 살아 있는 객체에 바로 쓰고 자동 저장이 곧 저장해
/// 버린다 — 그래서 `취소` 가 없었고, 잘못 고친 값을 되돌릴 길이 없었다.
/// 열 때 속성과 다대일 관계를 떠 두고, 취소하면 그대로 되돌린다. 새로 만든
/// 것이면 시트가 지운다. `context.rollback()` 은 못 쓴다 — 400ms 마다 저장되어
/// 되돌릴 것이 남아 있지 않다.
///
/// **이 기기에서 고친 칸만 되돌린다** (194번 E1). 예전에는 열 때와 다른 칸을
/// 전부 되썼다 — 시트를 열어 둔 사이 다른 기기의 점검 값이 iCloud 로 들어와
/// 합쳐져도 "열 때와 다르다" 에 걸려, `취소` 한 번에 가족이 적은 값이 모든
/// 기기에서 지워졌다. 그래서 이 기기의 저장 직전(`willSave`)마다 이 객체의
/// **고친 칸**(`changedValues`)을 모아 둔다. iCloud 에서 합쳐진 값은 고친 칸이
/// 아니므로(합치기는 저장할 변경을 남기지 않는다) 취소해도 그대로 남는다.
@MainActor
final class EditSnapshot: NSObject {
    private let values: [String: Any]
    private let relations: [String: NSManagedObject]
    private let nilKeys: Set<String>
    private let objectID: NSManagedObjectID
    /// 시트가 열린 뒤 이 기기에서 고쳐 저장한 칸.
    private var touchedKeys: Set<String> = []

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
        self.objectID = object.objectID
        super.init()
        // 셀렉터 방식은 객체가 사라지면 저절로 풀린다 — deinit 에서 뗄 것이 없다.
        if let context = object.managedObjectContext {
            NotificationCenter.default.addObserver(self, selector: #selector(contextWillSave(_:)),
                                                   name: .NSManagedObjectContextWillSave,
                                                   object: context)
        }
    }

    /// 저장 직전 — 아직 저장 안 된 이 객체의 변경이 곧 **이 기기에서 고친 칸**이다.
    /// 자동 저장은 화면 컨텍스트(주 스레드)에서만 돈다.
    @objc private func contextWillSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext,
              let object = context.registeredObject(for: objectID),
              object.hasChanges else { return }
        touchedKeys.formUnion(object.changedValues().keys)
    }

    func restore(to object: NSManagedObject) {
        guard !object.isDeleted else { return }
        // 아직 저장 안 된 마지막 고침도 이 기기의 것이다.
        let touched = touchedKeys.union(object.changedValues().keys)
        for (key, value) in values where touched.contains(key) && !isEqual(object.value(forKey: key), value) {
            object.setValue(value, forKey: key)
        }
        for (key, value) in relations where touched.contains(key)
            && (object.value(forKey: key) as? NSManagedObject) != value {
            object.setValue(value, forKey: key)
        }
        for key in nilKeys where touched.contains(key) && object.value(forKey: key) != nil {
            object.setValue(nil, forKey: key)
        }
    }

    private func isEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
        guard let lhs else { return false }
        return (lhs as AnyObject).isEqual(rhs)
    }
}
