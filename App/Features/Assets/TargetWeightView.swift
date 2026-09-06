import Core
import SwiftData
import SwiftUI

/// 목표 비중을 세우는 곳 — 두 층을 한 화면에서 (docs/08-feedback.md 14번).
///
/// 위는 **자산군**(주식·ETF · 채권 · 금 · 예적금 …), 아래는 그 자산군을 펼쳤을 때
/// 나오는 **종목**이다. 각 층의 합계를 늘 보여준다. 100%가 아니어도 막지 않는다 —
/// 적다 말면 100이 안 되는 것이 정상이고, 판정은 비례로 정규화해서 한다.
///
/// **목표를 안 정한 종목은 조용히 넘어가지 않는다.** 이 앱은 목표 비중을 세우는
/// 연습을 시키는 쪽이 맞다는 것이 사용자의 판단이다.
struct TargetWeightView: View {
    let member: Member

    @Query private var plans: [Plan]
    @State private var openClass: AssetClass?

    private var tolerance: Allocation.Tolerance {
        plans.first?.driftTolerance ?? Allocation.Tolerance()
    }

    var body: some View {
        List {
            Section {
                ForEach(member.usedAssetClasses, id: \.self) { assetClass in
                    classRow(assetClass)
                    if openClass == assetClass {
                        holdingRows(assetClass)
                    }
                }
            } header: {
                HStack {
                    Text("자산군")
                    Spacer()
                    total(of: classSlices, targets: classTargetSum)
                }
                .textCase(nil)
            } footer: {
                Text("전세보증금·예적금·현금까지 **가진 돈 전부**를 어떻게 나눠 두었는지 봅니다. 자산군을 누르면 그 안의 종목 비중이 열립니다.")
            }
        }
        .navigationTitle("목표 비중")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if member.usedAssetClasses.isEmpty {
                Text("먼저 종목을 등록하세요")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    // MARK: - 1층 · 자산군

    private var classSlices: [Allocation.Slice] {
        member.assetClassSlices(tolerance: tolerance)
    }

    private var classTargetSum: Int {
        (member.allocationTargets ?? []).reduce(0) { $0 + $1.targetBP }
    }

    @ViewBuilder
    private func classRow(_ assetClass: AssetClass) -> some View {
        let slice = classSlices.first { $0.label == assetClass.label }
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                openClass = openClass == assetClass ? nil : assetClass
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: openClass == assetClass ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.faint)
                Text(assetClass.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.ink)
                if let slice { DriftBadge(status: slice.status) }
                Spacer()
                actualAndTarget(slice)
                Stepper("", value: binding(for: assetClass), in: 0...10_000, step: 250)
                    .labelsHidden()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 자산군 목표는 없으면 만들어 준다. 목록에 보이는 것부터 0% 로 시작한다.
    private func binding(for assetClass: AssetClass) -> Binding<Int> {
        Binding(
            get: { existing(assetClass)?.targetBP ?? 0 },
            set: { newValue in
                if let target = existing(assetClass) {
                    target.targetBP = newValue
                } else {
                    let target = AllocationTarget(assetClass: assetClass,
                                                  targetBP: newValue, member: member)
                    var list = member.allocationTargets ?? []
                    list.append(target)
                    member.allocationTargets = list
                }
            }
        )
    }

    private func existing(_ assetClass: AssetClass) -> AllocationTarget? {
        (member.allocationTargets ?? []).first { $0.assetClass == assetClass }
    }

    // MARK: - 2층 · 종목

    @ViewBuilder
    private func holdingRows(_ assetClass: AssetClass) -> some View {
        let slices = member.holdingSlices(in: assetClass, tolerance: tolerance)
        ForEach(holdings(in: assetClass)) { holding in
            @Bindable var holding = holding
            let slice = slices.first {
                $0.label == (holding.name.isEmpty ? "이름 없음" : holding.name)
            }
            HStack(spacing: 8) {
                Text(holding.name.isEmpty ? "이름 없음" : holding.name)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.bodyText)
                if let slice { DriftBadge(status: slice.status) }
                Spacer()
                actualAndTarget(slice)
                Stepper("", value: Binding(
                    get: { holding.targetWeightBP ?? 0 },
                    set: { holding.targetWeightBP = $0 }
                ), in: 0...10_000, step: 250)
                .labelsHidden()
            }
            .padding(.leading, 16)
        }

        HStack {
            Text("\(assetClass.label) 안에서 합계")
                .font(.system(size: 10))
                .foregroundStyle(Color.faint)
            Spacer()
            total(of: slices, targets: holdingTargetSum(assetClass))
        }
        .padding(.leading, 16)
    }

    private func holdings(in assetClass: AssetClass) -> [Holding] {
        member.sortedAccounts
            .filter { !$0.isArchived && !$0.kind.isLiability }
            .flatMap(\.sortedHoldings)
            .filter { $0.assetClass == assetClass && $0.valueMinor != 0 }
    }

    private func holdingTargetSum(_ assetClass: AssetClass) -> Int {
        holdings(in: assetClass).reduce(0) { $0 + ($1.targetWeightBP ?? 0) }
    }

    // MARK: - 부품

    @ViewBuilder
    private func actualAndTarget(_ slice: Allocation.Slice?) -> some View {
        if let slice {
            HStack(spacing: 3) {
                Text("\(PercentFormatter.oneDecimal(slice.actual))%")
                    .font(.figure(12, weight: .medium))
                    .foregroundStyle(Color.ink)
                if let target = slice.target {
                    Text("/ \(PercentFormatter.oneDecimal(target))%")
                        .font(.figure(10))
                        .foregroundStyle(Color.faint)
                }
            }
        }
    }

    /// 합계는 늘 보인다. 100%가 아니면 눈에 띄게 적되 막지는 않는다.
    private func total(of slices: [Allocation.Slice], targets sum: Int) -> some View {
        let isHundred = sum == 10_000
        return Text("목표 합 \(PercentFormatter.oneDecimal(Decimal(sum) / 10_000))%")
            .font(.figure(10, weight: isHundred ? .regular : .semibold))
            .foregroundStyle(isHundred ? Color.faint : Color.loss)
    }
}

/// 목표에서 벗어났는지를 한 글자로. 주간 점검·자산 탭·목표 화면이 함께 쓴다.
struct DriftBadge: View {
    let status: Allocation.DriftStatus

    var body: some View {
        if status != .onTrack {
            StatusBadge(text: status.label,
                        foreground: foreground,
                        background: background)
        }
    }

    private var foreground: Color {
        switch status {
        case .act: return .loss
        case .watch: return .daughter
        case .noTarget: return .muted
        case .onTrack: return .gain
        }
    }

    private var background: Color {
        switch status {
        case .act: return .lossSoft
        case .watch: return .alertSoft
        case .noTarget: return .neutralSoft
        case .onTrack: return .gainSoft
        }
    }
}
