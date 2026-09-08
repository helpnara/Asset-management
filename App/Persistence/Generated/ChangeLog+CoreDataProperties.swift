// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension ChangeLog {

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChangeLog> {
        NSFetchRequest<ChangeLog>(entityName: "ChangeLog")
    }

    @NSManaged var id: UUID

    @NSManaged var at: Date

    /// 누가. 공유 전에는 기기 이름, 공유 후에는 참가자 이름이 들어간다.
    @NSManaged var actor: String

    @NSManaged var kindRaw: String

    /// 무엇을. `아빠 / ISA / TIGER 미국S&P500` 처럼 사람이 읽는 경로다.
    @NSManaged var subject: String

    /// 어떻게. `2,850,199 → 2,910,000`
    @NSManaged var summary: String
}
