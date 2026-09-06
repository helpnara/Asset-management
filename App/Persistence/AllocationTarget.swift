import Core
import Foundation
import SwiftData

/// 자산군 목표 — 목표 비중의 1층 (docs/08-feedback.md 14번).
///
/// "주식·ETF 60% · 채권 20% · 금 10% · 예적금 10%" 처럼 **사람마다** 세운다.
/// 종목 목표(2층)는 `Holding.targetWeightBP` 에 있고, 그 자산군 안에서 100%가 된다.
@Model
final class AllocationTarget {
    var id: UUID = UUID()
    var assetClassRaw: String = AssetClass.equity.rawValue
    var targetBP: Int = 0
    /// 관계와 **함께** 들고 다닌다. 공유로 넘어갈 때를 위해서다 (ADR-0004).
    var memberID: UUID?
    var member: Member?

    init(assetClass: AssetClass = .equity, targetBP: Int = 0, member: Member? = nil) {
        self.assetClassRaw = assetClass.rawValue
        self.targetBP = targetBP
        self.member = member
        self.memberID = member?.id
    }
}

extension AllocationTarget {
    var assetClass: AssetClass {
        get { AssetClass(rawValue: assetClassRaw) ?? .other }
        set { assetClassRaw = newValue.rawValue }
    }
}

extension Member {
    /// **1층 — 자산군 비중.**
    ///
    /// 분모는 이 사람의 **자산 합계(부채 제외)** 다. 전세보증금·예적금·현금도
    /// 들어간다 — 굴리는 돈만이 아니라 가진 돈 전부를 어떻게 나눠 두었는가가
    /// 이 층의 질문이기 때문이다.
    func assetClassSlices(tolerance: Allocation.Tolerance) -> [Allocation.Slice] {
        var targets: [AssetClass: Int] = [:]
        for target in allocationTargets ?? [] where target.targetBP > 0 {
            targets[target.assetClass, default: 0] += target.targetBP
        }

        var entries: [Allocation.Entry] = []
        for account in sortedAccounts where !account.isArchived && !account.kind.isLiability {
            for holding in account.sortedHoldings where holding.valueMinor != 0 {
                entries.append(Allocation.Entry(
                    label: holding.assetClass.label,
                    amount: holding.value,
                    targetBP: nil
                ))
            }
        }
        // 목표는 자산군마다 한 번만 붙인다. 종목마다 붙이면 합쳐지면서 몇 배가 된다.
        var seen = Set<String>()
        entries = entries.map { entry in
            guard let assetClass = AssetClass.allCases.first(where: { $0.label == entry.label }),
                  let bp = targets[assetClass], seen.insert(entry.label).inserted
            else { return entry }
            return Allocation.Entry(label: entry.label, amount: entry.amount, targetBP: bp)
        }
        return Allocation.slices(entries, tolerance: tolerance)
    }

    /// **2층 — 한 자산군 안의 종목 비중.**
    ///
    /// 분모는 그 자산군 합계다. 같은 이름의 종목은 합쳐진다 — 실제로 한 종목이
    /// 세 계좌에 흩어져 있기 때문이다.
    func holdingSlices(in assetClass: AssetClass,
                       tolerance: Allocation.Tolerance) -> [Allocation.Slice] {
        var entries: [Allocation.Entry] = []
        for account in sortedAccounts where !account.isArchived && !account.kind.isLiability {
            for holding in account.sortedHoldings
            where holding.assetClass == assetClass && holding.valueMinor != 0 {
                entries.append(Allocation.Entry(
                    label: holding.name.isEmpty ? "이름 없음" : holding.name,
                    amount: holding.value,
                    targetBP: holding.targetWeightBP
                ))
            }
        }
        return Allocation.slices(entries, tolerance: tolerance)
    }

    /// 이 사람이 실제로 갖고 있는 자산군들. 목표를 세울 때 이 목록을 보여준다.
    var usedAssetClasses: [AssetClass] {
        var seen: [AssetClass] = []
        for account in sortedAccounts where !account.isArchived && !account.kind.isLiability {
            for holding in account.sortedHoldings where holding.valueMinor != 0 {
                if !seen.contains(holding.assetClass) { seen.append(holding.assetClass) }
            }
        }
        return seen
    }

    /// 목표에서 벗어난 종목 수. 주간 점검 완료 화면이 한 줄로 읽는다.
    func driftingHoldingCount(tolerance: Allocation.Tolerance) -> Int {
        usedAssetClasses.reduce(0) { count, assetClass in
            count + holdingSlices(in: assetClass, tolerance: tolerance)
                .filter { $0.status == .watch || $0.status == .act }.count
        }
    }
}
