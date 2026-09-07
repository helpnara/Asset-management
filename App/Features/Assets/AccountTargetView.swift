import Core
import SwiftData
import SwiftUI

/// 한 계좌 안 종목의 목표 비중을 세우는 곳 (docs/08-feedback.md 15번).
///
/// **목표가 붙는 층은 여기 하나뿐이다.** 계좌마다 투자 목적과 규모가 다르므로
/// "이 계좌를 무엇으로 채울 것인가" 가 사람이 실제로 정하는 단위다. 그 위의
/// 두 층(가족→구성원, 구성원→계좌)은 급여와 납입 한도가 정하는 값이라
/// 비율로 고를 수 있는 것이 아니다.
///
/// **합은 100%여야 한다.** 아니어도 막지는 않지만 눈에 띄게 적는다.
struct AccountTargetView: View {
    let account: Account

    @Query private var plans: [Plan]

    private var tolerance: Allocation.Tolerance {
        plans.first?.driftTolerance ?? Allocation.Tolerance()
    }

    private var slices: [Allocation.Slice] {
        account.holdingSlices(tolerance: tolerance)
    }

    var body: some View {
        List {
            Section {
                ForEach(account.weightedHoldings) { holding in
                    @Bindable var holding = holding
                    let slice = slices.first { $0.label == holding.weightLabel }
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(holding.weightLabel)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.bodyText)
                            Text(Won.abbreviated(holding.value, suffix: "원"))
                                .font(.figure(10))
                                .foregroundStyle(Color.faint)
                        }
                        Spacer(minLength: 6)
                        if let slice { WeightLabel(slice: slice) }
                        Stepper("", value: Binding(
                            get: { holding.targetWeightBP ?? 0 },
                            set: { holding.targetWeightBP = $0 }
                        ), in: 0...10_000, step: 250)
                        .labelsHidden()
                    }
                }
            } header: {
                HStack {
                    Text("종목 목표")
                    Spacer()
                    targetSum
                }
                .textCase(nil)
            } footer: {
                Text("이 **계좌 안에서**의 비중입니다. 같은 종목을 다른 계좌에도 갖고 있다면 그쪽은 따로 셉니다 — 계좌마다 목적과 규모가 다르기 때문입니다.")
            }

            if !splitSuggestion.isEmpty {
                Section {
                    ForEach(splitSuggestion, id: \.label) { row in
                        HStack {
                            Text(row.label)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.bodyText)
                            Spacer()
                            Text(Won.abbreviated(row.amount, suffix: "원"))
                                .font(.figure(13, weight: .semibold))
                                .foregroundStyle(Color.ink)
                        }
                    }
                } header: {
                    Text("이번 달 적립을 이렇게 나누면").textCase(nil)
                } footer: {
                    Text("**파는 이야기는 하지 않습니다.** 매도는 세금과 수수료가 들고, 무엇을 팔지는 앱이 판단할 일이 아닙니다. 넣는 돈으로 맞춰 가면 목표에 가장 가까워집니다.")
                }
            }
        }
        .navigationTitle(account.weightLabel)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if account.weightedHoldings.isEmpty {
                Text("먼저 종목을 등록하세요")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.muted)
            }
        }
    }

    /// 합계는 늘 보인다. 100%가 아니면 눈에 띄게 적되 막지는 않는다.
    private var targetSum: some View {
        let sum = account.targetSumBP
        let isHundred = sum == 10_000
        return Text("목표 합 \(PercentFormatter.oneDecimal(Decimal(sum) / 10_000))%")
            .font(.figure(10, weight: isHundred ? .regular : .semibold))
            .foregroundStyle(isHundred ? Color.gain : Color.loss)
    }

    /// **팔지 않고 적립으로 맞춘다.** 이 계좌에 넣을 돈을 종목별로 얼마씩 나누면
    /// 목표에 가장 가까워지는지 계산한다.
    ///
    /// 이 계좌 몫의 적립액은 따로 적는 곳이 없으므로, 주인의 월 적립(본인 +
    /// 회사 매칭)을 **이 계좌가 그 사람 자산에서 차지하는 비중만큼** 잡는다.
    /// 어림이지만 "어느 쪽에 더 넣어야 하나" 라는 질문에는 충분하다.
    private var splitSuggestion: [(label: String, amount: Money)] {
        guard let owner = account.owner else { return [] }
        let monthly = owner.monthlyContributionMinor + owner.employerMatchMinor
        let ownerTotal = owner.assetTotalMinor
        guard monthly > 0, ownerTotal > 0, account.totalMinor > 0 else { return [] }
        // `Decimals` 는 Core 내부 타입이라 여기서 못 쓴다. 정수로 계산한다 —
        // 원 단위라 나눗셈 한 번의 버림은 1원이고, 어차피 어림잡는 값이다.
        let forThisAccount = monthly * account.totalMinor / ownerTotal
        guard forThisAccount > 0 else { return [] }
        return Allocation.contributionSplit(
            slices,
            contribution: Money(minorUnits: forThisAccount, currency: .krw)
        )
    }
}

/// `15/20% 주의` — 실제와 목표가 한 줄에 서고, 그 옆에 판정이 붙는다.
///
/// 조치·주의만 있을 때는 "어떤 상황인지 파악이 어렵다" 는 지적을 받았다.
/// 숫자가 먼저고 배지는 그 숫자를 요약할 뿐이다.
struct WeightLabel: View {
    let slice: Allocation.Slice
    /// 목표가 붙지 않는 층(가족→구성원, 구성원→계좌)에서는 배지를 달지 않는다.
    var showsStatus: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            Text(slice.comparisonLabel)
                .font(.figure(11.5, weight: .medium))
                .foregroundStyle(slice.target == nil ? Color.muted : Color.ink)
                .lineLimit(1)
                .fixedSize()
            if showsStatus { DriftBadge(status: slice.status) }
        }
    }
}

/// 목표 대비 상태 배지. `WeightLabel` 이 숫자와 함께 쓴다.
struct DriftBadge: View {
    let status: Allocation.DriftStatus

    var body: some View {
        if status != .onTrack {
            StatusBadge(text: status.label,
                        foreground: foreground,
                        background: background)
                .lineLimit(1)
                .fixedSize()
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
