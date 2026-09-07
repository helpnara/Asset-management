import Core
import SwiftData
import SwiftUI

/// 가족 전체 자산을 세 가지로 갈라 본다 (docs/08-feedback.md 15번).
///
/// 1. **구성원** — 각자의 자산이 가족 안에서 몇 %인가. 목표는 없다
/// 2. **지역** — 미국과 한국의 비중. 목표를 적을 수 있다
/// 3. **자산군** — 부동산 · 주식 · 채권 · 금 · 연금 …. 목표를 적을 수 있다
///
/// 2와 3은 **계좌 구조를 가로지르는 질문**이다. 계좌 안 종목 목표를 아무리 잘
/// 세워도 "우리 집 돈에서 미국이 몇 %인가" 에는 답이 안 나온다. 그래서 따로 둔다.
struct FamilyAllocationView: View {
    @Query(sort: \Member.sortIndex) private var members: [Member]
    @Query private var plans: [Plan]
    @Query private var targets: [FamilyTarget]
    @Environment(\.modelContext) private var context

    private var tolerance: Allocation.Tolerance {
        plans.first?.driftTolerance ?? Allocation.Tolerance()
    }

    var body: some View {
        List {
            Section {
                ForEach(FamilyAllocation.memberSlices(members)) { slice in
                    HStack {
                        Text(slice.label)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.bodyText)
                        Spacer()
                        WeightLabel(slice: slice, showsStatus: false)
                    }
                }
            } header: {
                HStack {
                    Text("구성원")
                    Spacer()
                    Text(Won.abbreviated(familyTotal, suffix: "원"))
                        .font(.figure(11, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .textCase(nil)
            } footer: {
                Text("각자의 자산이 가족 안에서 차지하는 몫입니다. **목표를 두지 않습니다** — 누가 얼마를 버는지가 정하는 값이라 비율로 고를 수 있는 것이 아닙니다.")
            }

            dimensionSection(.region)
            dimensionSection(.assetClass)
        }
        .navigationTitle("가족 자산 배분")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if familyTotal.minorUnits == 0 {
                Text("먼저 자산을 등록하세요")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    private var familyTotal: Money {
        Money(minorUnits: members.reduce(0) { $0 + $1.assetTotalMinor }, currency: .krw)
    }

    @ViewBuilder
    private func dimensionSection(_ dimension: FamilyTarget.Dimension) -> some View {
        let slices = FamilyAllocation.slices(members, dimension: dimension,
                                             targets: targets, tolerance: tolerance)
        Section {
            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    Text(slice.label)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.bodyText)
                    Spacer(minLength: 6)
                    WeightLabel(slice: slice)
                    Stepper("", value: binding(dimension, key: key(for: slice, in: dimension)),
                            in: 0...10_000, step: 250)
                        .labelsHidden()
                }
            }
        } header: {
            HStack {
                Text(dimension.label)
                Spacer()
                sumLabel(dimension)
            }
            .textCase(nil)
        } footer: {
            Text(dimension.footnote)
        }
    }

    /// 화면은 라벨을 보여주지만 저장은 rawValue 로 한다. 라벨에서 키를 되찾는다.
    private func key(for slice: Allocation.Slice, in dimension: FamilyTarget.Dimension) -> String {
        FamilyAllocation.usedKeys(members, dimension: dimension)
            .first { FamilyAllocation.label(forKey: $0, dimension: dimension) == slice.label }
            ?? slice.label
    }

    private func sumLabel(_ dimension: FamilyTarget.Dimension) -> some View {
        let sum = FamilyAllocation.targetSumBP(targets, dimension: dimension)
        // 아직 하나도 안 적었으면 다그치지 않는다. 목표는 선택이다.
        let tone: Color = sum == 0 ? .faint : (sum == 10_000 ? .gain : .loss)
        return Text(sum == 0 ? "목표 없음"
                    : "목표 합 \(PercentFormatter.oneDecimal(Decimal(sum) / 10_000))%")
            .font(.figure(10, weight: sum == 10_000 || sum == 0 ? .regular : .semibold))
            .foregroundStyle(tone)
    }

    private func binding(_ dimension: FamilyTarget.Dimension, key: String) -> Binding<Int> {
        Binding(
            get: { existing(dimension, key: key)?.targetBP ?? 0 },
            set: { newValue in
                if let target = existing(dimension, key: key) {
                    target.targetBP = newValue
                } else {
                    context.insert(FamilyTarget(dimension: dimension, key: key, targetBP: newValue))
                }
            }
        )
    }

    private func existing(_ dimension: FamilyTarget.Dimension, key: String) -> FamilyTarget? {
        targets.first { $0.dimension == dimension && $0.key == key }
    }
}
