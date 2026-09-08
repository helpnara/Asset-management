// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation

@objc(TodoItem)
/// `Identifiable` 은 손으로 붙인다. SwiftData 의 `@Model` 은 거저 줬지만
/// `NSManagedObject` 는 안 준다 — `ForEach` · `sheet(item:)` 이 요구한다.
/// 엔티티마다 `id: UUID` 가 있으므로 준수는 자동으로 합성된다.
class TodoItem: NSManagedObject, Identifiable {

    /// 모델의 기본값은 **자리 채우기**다 (`00000000-…` · 2001-01-01).
    /// 진짜 값은 여기서 넣는다 — 안 그러면 모든 행의 id 가 같아진다.
    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = .now
    }
}
