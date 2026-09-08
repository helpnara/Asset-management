// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import Core
import CoreData
import Foundation

/// `Identifiable` 은 손으로 붙인다. SwiftData 의 `@Model` 은 거저 줬지만
/// `NSManagedObject` 는 안 준다 — `ForEach` · `sheet(item:)` 이 요구한다.
/// 엔티티마다 `id: UUID` 가 있으므로 준수는 자동으로 합성된다.
@objc(SnapshotLine)
class SnapshotLine: NSManagedObject, Identifiable {

    /// **Swift 가 적어 두었던 기본값을 그대로 넣는다.**
    ///
    /// 모델 파일(`.xcdatamodeld`)의 기본값은 리터럴만 담을 수 있어서,
    /// `UUID()` · `Date.now` · 열거형 rawValue · `Calendar.current.component(...)`
    /// 같은 것은 자리만 채워 두었다(`0` · `""` · `00000000-…`). 진짜 값은 여기서 넣는다.
    ///
    /// **이걸 빠뜨리면 화면이 조용히 틀린 숫자를 보여 준다.** 실제로 `Plan.startYear`
    /// 가 0 이 되어 은퇴 예상이 63억에서 21억으로 떨어졌다 (4차 1b-2).
    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        memberID = UUID()
    }
}
