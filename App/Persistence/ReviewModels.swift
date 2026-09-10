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

    /// 이번 주에 제 몫을 적은 구성원들 (C8). 읽고 쓰는 길은 이 둘뿐이다 —
    /// `Member.editorIDs` 와 같은 쉼표 꼴이다.
    var enteredMemberIDSet: Set<UUID> {
        Set(enteredMemberIDs.split(separator: ",")
            .compactMap { UUID(uuidString: $0.trimmingCharacters(in: .whitespaces)) })
    }

    func setEnteredMembers(_ ids: Set<UUID>) {
        let next = ids.map(\.uuidString).sorted().joined(separator: ",")
        if next != enteredMemberIDs { enteredMemberIDs = next }
    }

    /// **구성원 한 사람의 연속 기록 주차** (C8 · 안정화 기준 2 "넷이 각자 4주 연속").
    ///
    /// 가구의 연속 기록과 같은 규칙으로 센다 — 이번 주를 아직 안 적었어도
    /// 지난주까지 이어져 있으면 그 수를 보인다. 총액만 적은 주(`isTotalOnly`)
    /// 에는 구성원 칸이 비어 있어 그 주에서 끊긴다.
    static func memberStreak(_ memberID: UUID, sessions: [ReviewSession], asOf: Date = .now) -> Int {
        let anchors = sessions
            .filter { $0.isComplete && $0.enteredMemberIDSet.contains(memberID) }
            .map(\.weekAnchor)
        return ReviewWeek.streak(completedAnchors: anchors, asOf: asOf)
    }

    /// 이번 주에 그 구성원 몫이 적혔나.
    static func enteredThisWeek(_ memberID: UUID, sessions: [ReviewSession], asOf: Date = .now) -> Bool {
        let anchor = ReviewWeek.anchor(for: asOf)
        return sessions.contains { $0.weekAnchor == anchor && $0.enteredMemberIDSet.contains(memberID) }
    }
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
