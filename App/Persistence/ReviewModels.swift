import Core
import Foundation
import CoreData

/// 주간 점검 1회. 완료한 주에만 스냅샷이 생긴다.
extension ReviewSession {
    convenience init(context: NSManagedObjectContext, weekAnchor: Date, totalCount: Int) {
        self.init(context: context)
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
extension Snapshot {
    convenience init(context: NSManagedObjectContext, weekAnchor: Date, netWorthMinor: Int, investableMinor: Int, liabilitiesMinor: Int) {
        self.init(context: context)
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
extension SnapshotLine {
    convenience init(context: NSManagedObjectContext, memberID: UUID, memberName: String, valueMinor: Int, sortIndex: Int) {
        self.init(context: context)
        self.memberID = memberID
        self.memberName = memberName
        self.valueMinor = valueMinor
        self.sortIndex = sortIndex
    }
}

extension Snapshot {
    var sortedLines: [SnapshotLine] {
        (lines as? Set<SnapshotLine> ?? []).sorted { $0.sortIndex < $1.sortIndex }
    }
}
