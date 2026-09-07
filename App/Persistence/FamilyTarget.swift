import Core
import Foundation
import SwiftData

/// 가족 전체를 가로지르는 목표 — 지역과 자산군 (docs/08-feedback.md 15번).
///
/// 계좌 안 종목 목표(`Holding.targetWeightBP`)와는 **다른 질문**이다.
/// 저쪽은 "이 계좌를 무엇으로 채울까", 이쪽은 "우리 집 돈 전부에서 미국이
/// 몇 %인가 · 부동산이 몇 %인가" 다. 계좌 구조를 가로지르므로 계좌 목표를
/// 아무리 잘 세워도 이 질문에는 답이 안 나온다.
///
/// 목표를 안 적어도 된다. 그러면 화면은 실제 비중만 보여준다.
@Model
final class FamilyTarget {
    var id: UUID = UUID()
    /// `Dimension.rawValue`. 지역인지 자산군인지.
    var dimensionRaw: String = FamilyTarget.Dimension.assetClass.rawValue
    /// 그 축 안에서의 키 — `Region.rawValue` 또는 `AssetClass.rawValue`.
    var key: String = ""
    var targetBP: Int = 0

    init(dimension: Dimension = .assetClass, key: String = "", targetBP: Int = 0) {
        self.dimensionRaw = dimension.rawValue
        self.key = key
        self.targetBP = targetBP
    }

    enum Dimension: String, CaseIterable, Identifiable {
        case region
        case assetClass

        var id: String { rawValue }

        var label: String {
            switch self {
            case .region: return "지역"
            case .assetClass: return "자산군"
            }
        }

        var footnote: String {
            switch self {
            case .region:
                return "상장 국가로 가릅니다. 부동산·전세보증금·예적금처럼 상장되지 않은 것은 한국으로 잡힙니다."
            case .assetClass:
                return "계좌를 가로질러 봅니다. 같은 자산군이 여러 계좌에 흩어져 있어도 하나로 합칩니다."
            }
        }
    }

    var dimension: Dimension {
        get { Dimension(rawValue: dimensionRaw) ?? .assetClass }
        set { dimensionRaw = newValue.rawValue }
    }
}

// MARK: - 4층 · 계좌 안의 종목 (여기에만 목표가 붙는다)

extension Account {
    /// 이 계좌의 자산 합계. 부채 계좌면 절댓값이다.
    var totalMinor: Int {
        sortedHoldings.reduce(0) { $0 + $1.valueMinor }
    }

    /// 비중을 재는 종목 (값이 0이 아닌 것).
    var weightedHoldings: [Holding] {
        sortedHoldings.filter { $0.valueMinor != 0 }
    }

    private var allocationEntries: [Allocation.Entry] {
        weightedHoldings.map { holding in
            Allocation.Entry(label: holding.weightLabel,
                             amount: holding.value,
                             targetBP: holding.targetWeightBP)
        }
    }

    /// **계좌 안 종목 비중.** 분모는 이 계좌의 합계다.
    ///
    /// 계좌마다 투자 목적과 규모가 다르므로 계좌를 넘어 합치지 않는다 —
    /// 같은 종목이 IRP·연금저축·ISA 에 흩어져 있어도 각 계좌 안에서 따로 잰다.
    func holdingSlices(tolerance: Allocation.Tolerance) -> [Allocation.Slice] {
        Allocation.slices(allocationEntries, tolerance: tolerance)
    }

    /// 적어 둔 목표의 합. **100%(10,000)여야 한다** — 계좌 안 종목 비중의 합이
    /// 100%가 되는 것이 이 층의 규칙이다. 아니면 화면이 눈에 띄게 적는다.
    var targetSumBP: Int { Allocation.targetSumBP(allocationEntries) }

    /// 목표를 세울 준비가 됐나 (종목이 하나라도 있나).
    var canSetTargets: Bool { !weightedHoldings.isEmpty && !kind.isLiability }
}

extension Holding {
    /// 비중을 잴 때 쓰는 이름. 빈 이름도 한 칸을 차지해야 합계가 맞는다.
    var weightLabel: String { name.isEmpty ? "이름 없음" : name }

    /// 이 종목이 **자기 계좌 안에서** 어느 상태인가.
    func driftSlice(tolerance: Allocation.Tolerance) -> Allocation.Slice? {
        account?.holdingSlices(tolerance: tolerance).first { $0.label == weightLabel }
    }
}

// MARK: - 3층 · 구성원 안의 계좌 (목표 없음)

extension Member {
    /// 이 사람의 자산 합계 (부채 제외).
    var assetTotalMinor: Int {
        sortedAccounts
            .filter { !$0.isArchived && !$0.kind.isLiability }
            .reduce(0) { $0 + $1.totalMinor }
    }

    /// **계좌 비중.** 분모는 이 사람의 자산 합계다.
    ///
    /// **목표를 두지 않는다.** 계좌 잔고는 급여와 납입 한도가 정하는 것이라
    /// 사람이 비율로 고를 수 있는 값이 아니다. 지금 어떻게 나뉘어 있는지를
    /// 보여 주기만 한다.
    var accountSlices: [Allocation.Slice] {
        let entries = sortedAccounts
            .filter { !$0.isArchived && !$0.kind.isLiability && $0.totalMinor != 0 }
            .map { account in
                Allocation.Entry(label: account.weightLabel,
                                 amount: Money(minorUnits: account.totalMinor, currency: .krw),
                                 targetBP: nil)
            }
        return Allocation.slices(entries)
    }

    /// 비중을 재는 대상 종목 (부채 계좌 제외, 값이 있는 것).
    var investableHoldings: [Holding] {
        sortedAccounts
            .filter { !$0.isArchived && !$0.kind.isLiability }
            .flatMap(\.weightedHoldings)
    }

    var investableHoldingCount: Int { investableHoldings.count }

    /// 목표를 아직 안 정한 종목 수. **이것도 알림거리다.**
    var untargetedHoldingCount: Int {
        investableHoldings.filter { $0.targetWeightBP == nil }.count
    }

    /// 목표에서 벗어난 종목 수. 계좌마다 따로 세어 더한다.
    func driftingHoldingCount(tolerance: Allocation.Tolerance) -> Int {
        sortedAccounts
            .filter { !$0.isArchived && !$0.kind.isLiability }
            .reduce(0) { count, account in
                count + account.holdingSlices(tolerance: tolerance)
                    .filter { $0.status == .watch || $0.status == .act }.count
            }
    }

    /// 종목 목표 합이 100%가 아닌 계좌들. 그 자체로 "아직 안 세운 계좌" 다.
    var accountsWithIncompleteTargets: [Account] {
        sortedAccounts.filter { $0.canSetTargets && !$0.isArchived && $0.targetSumBP != 10_000 }
    }
}

extension Account {
    /// 목록과 비중에서 쓰는 이름.
    var weightLabel: String { name.isEmpty ? kind.label : name }
}

// MARK: - 1·2층과 가로지르는 축 · 가족 전체

/// 가족 전체를 재는 것들. 구성원 비중과, 계좌 구조를 가로지르는 지역·자산군 비중.
enum FamilyAllocation {

    /// 자산으로 세는 계좌만 (부채·보관 종료 제외).
    private static func assetAccounts(_ members: [Member]) -> [Account] {
        members.flatMap(\.sortedAccounts).filter { !$0.isArchived && !$0.kind.isLiability }
    }

    /// **1층 — 구성원 비중.** 분모는 가족 자산 합계다. 목표는 두지 않는다.
    static func memberSlices(_ members: [Member]) -> [Allocation.Slice] {
        let entries = members
            .filter { $0.assetTotalMinor != 0 }
            .map { member in
                Allocation.Entry(label: member.name.isEmpty ? "이름 없음" : member.name,
                                 amount: Money(minorUnits: member.assetTotalMinor, currency: .krw),
                                 targetBP: nil)
            }
        return Allocation.slices(entries)
    }

    /// 지역·자산군 한 축을 잰다. 목표는 `targets` 에서 가져온다.
    static func slices(_ members: [Member],
                       dimension: FamilyTarget.Dimension,
                       targets: [FamilyTarget],
                       tolerance: Allocation.Tolerance) -> [Allocation.Slice] {
        var targetByKey: [String: Int] = [:]
        for target in targets where target.dimension == dimension {
            targetByKey[target.key, default: 0] += target.targetBP
        }

        // 목표는 한 축에 한 번만 붙인다. 종목마다 붙이면 합쳐지면서 몇 배가 된다.
        var attached = Set<String>()
        var entries: [Allocation.Entry] = []
        for account in assetAccounts(members) {
            for holding in account.weightedHoldings {
                let key = self.key(of: holding, dimension: dimension)
                let bp = attached.insert(key).inserted ? targetByKey[key] : nil
                entries.append(Allocation.Entry(label: label(forKey: key, dimension: dimension),
                                                amount: holding.value,
                                                targetBP: bp))
            }
        }
        return Allocation.slices(entries, tolerance: tolerance)
    }

    /// 적어 둔 목표의 합. 화면이 100%인지 적는다.
    static func targetSumBP(_ targets: [FamilyTarget],
                            dimension: FamilyTarget.Dimension) -> Int {
        targets.filter { $0.dimension == dimension }.reduce(0) { $0 + $1.targetBP }
    }

    /// 실제로 갖고 있는 축의 값들. 목표를 세울 때 이 목록을 보여준다.
    static func usedKeys(_ members: [Member],
                         dimension: FamilyTarget.Dimension) -> [String] {
        var seen: [String] = []
        for account in assetAccounts(members) {
            for holding in account.weightedHoldings {
                let key = self.key(of: holding, dimension: dimension)
                if !seen.contains(key) { seen.append(key) }
            }
        }
        return seen
    }

    static func key(of holding: Holding, dimension: FamilyTarget.Dimension) -> String {
        switch dimension {
        case .region: return Region.of(countryCode: holding.listingCountryCode).rawValue
        case .assetClass: return holding.assetClass.rawValue
        }
    }

    static func label(forKey key: String, dimension: FamilyTarget.Dimension) -> String {
        switch dimension {
        case .region: return (Region(rawValue: key) ?? .other).label
        case .assetClass: return (AssetClass(rawValue: key) ?? .other).label
        }
    }
}
