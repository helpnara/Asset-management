import Core
import Foundation
import SwiftData

/// 주간 점검 1회. 완료한 주에만 스냅샷이 생긴다.
@Model
final class ReviewSession {
    var id: UUID = UUID()
    /// 그 주 토요일(00:00)로 정규화한 값. 주차의 키다.
    var weekAnchor: Date = Date.now
    var startedAt: Date = Date.now
    var completedAt: Date?
    var enteredCount: Int = 0
    var totalCount: Int = 0
    /// 알림에서 총액만 적고 넘어간 주. 궤적의 점은 남고 분해는 비어 있다.
    var isTotalOnly: Bool = false
    var totalValueMinor: Int = 0
    var previousTotalValueMinor: Int = 0

    init(weekAnchor: Date, totalCount: Int) {
        self.weekAnchor = weekAnchor
        self.startedAt = .now
        self.totalCount = totalCount
    }
}

extension ReviewSession {
    var isComplete: Bool { completedAt != nil }
    var changeMinor: Int { totalValueMinor - previousTotalValueMinor }
}

/// 주간 실제 기록. 궤적의 "실제" 선은 이 값을 이은 것이다.
@Model
final class Snapshot {
    var id: UUID = UUID()
    var weekAnchor: Date = Date.now
    var netWorthMinor: Int = 0
    var investableMinor: Int = 0
    var liabilitiesMinor: Int = 0

    init(weekAnchor: Date, netWorthMinor: Int, investableMinor: Int, liabilitiesMinor: Int) {
        self.weekAnchor = weekAnchor
        self.netWorthMinor = netWorthMinor
        self.investableMinor = investableMinor
        self.liabilitiesMinor = liabilitiesMinor
    }
}
