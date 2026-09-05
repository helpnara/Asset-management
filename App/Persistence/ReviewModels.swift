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

    @Relationship(deleteRule: .cascade, inverse: \SnapshotLine.snapshot)
    var lines: [SnapshotLine]? = []

    init(weekAnchor: Date, netWorthMinor: Int, investableMinor: Int, liabilitiesMinor: Int) {
        self.weekAnchor = weekAnchor
        self.netWorthMinor = netWorthMinor
        self.investableMinor = investableMinor
        self.liabilitiesMinor = liabilitiesMinor
    }
}

/// 스냅샷의 구성원별 분해.
///
/// 이게 없으면 과거 점검을 다시 열었을 때 총액은 그 시점 값인데 구성원별은
/// 현재 값이라 합이 안 맞는다. 실제로 그 어긋남을 화면에서 보고 넣었다.
///
/// 자산군·국가 축은 궤적 차트가 필요로 할 때 더한다. 지금 넣으면 쓰지도 않는
/// 필드를 CloudKit 스키마에 박아두게 된다.
@Model
final class SnapshotLine {
    var id: UUID = UUID()
    var memberID: UUID = UUID()
    /// 구성원을 지워도 과거 기록은 남아야 하므로 이름을 복사해 둔다.
    var memberName: String = ""
    var valueMinor: Int = 0
    var sortIndex: Int = 0
    var snapshot: Snapshot?

    init(memberID: UUID, memberName: String, valueMinor: Int, sortIndex: Int) {
        self.memberID = memberID
        self.memberName = memberName
        self.valueMinor = valueMinor
        self.sortIndex = sortIndex
    }
}

extension Snapshot {
    var sortedLines: [SnapshotLine] {
        (lines ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
}
