// 이 파일은 **만들어진 것**이다. 손으로 고치지 않는다.
//
//     python3 Tools/coredata/generate-managed-classes.py
//
// 원본은 App/Persistence/*.swift 의 `@Model` 선언이다. 거기를 고치고 다시 뽑는다.
// CI 가 대조하므로 안 뽑고 넘어가면 빌드가 막힌다.

import CoreData
import Foundation


extension CashEvent {

    @nonobjc class func fetchRequest() -> NSFetchRequest<CashEvent> {
        NSFetchRequest<CashEvent>(entityName: "CashEvent")
    }

    @NSManaged var id: UUID

    @NSManaged var date: Date

    @NSManaged var label: String

    /// 부호로 방향을 표현한다. 양수는 유입, 음수는 유출.
    @NSManaged var amountMinor: Int

    /// 이미 현재 잔고에 반영된 이벤트. 예측에서 빼야 두 번 세지 않는다.
    ///
    /// 1페이지의 "이 표의 모든 금액은 이사 완료 후 기준 — 중복 계산 방지" 가
    /// 바로 이 문제였다.
    @NSManaged var isAlreadyReflected: Bool

    @NSManaged var note: String

    @NSManaged var sortIndex: Int
}
