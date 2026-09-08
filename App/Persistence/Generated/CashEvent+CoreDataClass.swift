// **이 파일은 이제 손으로 고친다.** 예전에는 생성물이었다.
//
// 4차 1b-2 로 `@Model` 이 사라지면서 원본이 `App/SlowRich.xcdatamodeld` 가
// 됐다. 그런데 모델 파일에는 주석 칸이 없다 — 아래 `///` 들은 "왜 이 칸이
// 있나" 를 적어 둔 이 저장소의 자산인데, 모델에서 다시 뽑으면 **전부
// 날아간다.** 그래서 `generate-managed-classes.py` 는 더 돌리지 않는다
// (돌리면 스스로 막는다).
//
// 칸을 더할 때는 **셋을 함께** 고친다:
//   App/SlowRich.xcdatamodeld · 이 파일 · Tools/cloudkit/slowrich.ckdb
// CI 가 서로 대조하므로 하나만 고치면 빌드가 막힌다.

import Core
import CoreData
import Foundation

/// `Identifiable` 은 손으로 붙인다. SwiftData 의 `@Model` 은 거저 줬지만
/// `NSManagedObject` 는 안 준다 — `ForEach` · `sheet(item:)` 이 요구한다.
/// 엔티티마다 `id: UUID` 가 있으므로 준수는 자동으로 합성된다.
@objc(CashEvent)
class CashEvent: NSManagedObject, Identifiable {

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
        date = Date.now
    }
}
