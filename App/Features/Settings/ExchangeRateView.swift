import Core
import SwiftData
import SwiftUI

/// 환율 — 직접 넣는다.
///
/// 시세와 같은 이유로 외부에서 가져오지 않는다 (ADR-0005). 자동으로 갱신되면
/// 지난주와 이번주 사이의 증감에 **내가 안 한 변화**가 섞인다. 계획 대비 실적을
/// 체감하려고 손으로 적는 앱에서 그건 앞뒤가 안 맞는다.
struct ExchangeRateView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ExchangeRate.code) private var rates: [ExchangeRate]
    @Query private var holdings: [Holding]

    /// 실제로 쓰이고 있는 통화. 안 쓰는 통화의 환율을 물어볼 이유가 없다.
    private var usedCurrencies: [String] {
        Set(holdings.map(\.currencyCode)).subtracting(["KRW"]).sorted()
    }

    var body: some View {
        List {
            if usedCurrencies.isEmpty {
                Section {
                    Text("아직 원화가 아닌 종목이 없습니다.\n종목 화면에서 통화를 바꾸면 여기에 환율 칸이 생깁니다.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                }
            }

            ForEach(usedCurrencies, id: \.self) { code in
                Section {
                    rateRow(code)
                } header: {
                    Text(code)
                } footer: {
                    if let rate = rates.first(where: { $0.code == code }), rate.isSet {
                        Text("1 \(code) = \(KoreanAmountFormatter.grouped(rate.rateScaled / ExchangeRate.scale))원 기준. 마지막 수정 \(dateText(rate.updatedAt)).")
                    } else {
                        // 환율이 없으면 그 종목은 합계에서 통째로 빠진다.
                        // 1:1 로 넘기면 달러가 원으로 둔갑하므로 빼는 쪽이 옳다.
                        Text("**환율을 넣어야 합계에 들어갑니다.** 넣기 전까지 이 통화 종목은 총자산에서 빠집니다 — 1:1로 세면 달러가 원으로 둔갑하기 때문입니다.")
                    }
                }
            }
        }
        .navigationTitle("환율")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func rateRow(_ code: String) -> some View {
        let rate = rates.first { $0.code == code } ?? make(code)
        @Bindable var rate = rate
        HStack(spacing: 10) {
            Text(verbatim: "1 \(code) =")
                .foregroundStyle(Color.bodyText)
            Spacer(minLength: 12)
            TextField("0", text: text(for: rate))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.figure(17))
                .foregroundStyle(Color.ink)
            Text("원")
                .font(.system(size: 13))
                .foregroundStyle(Color.muted)
        }
    }

    /// 소수 둘째 자리까지 받는다. 1,380.5원 같은 값을 못 넣으면 매주 어긋난다.
    private func text(for rate: ExchangeRate) -> Binding<String> {
        Binding(
            get: {
                guard rate.isSet else { return "" }
                let whole = rate.rateScaled / ExchangeRate.scale
                let fraction = (rate.rateScaled % ExchangeRate.scale) / 100
                return fraction == 0
                    ? KoreanAmountFormatter.grouped(whole)
                    : KoreanAmountFormatter.grouped(whole) + String(format: ".%02d", fraction)
            },
            set: { input in
                let cleaned = input.filter { $0.isNumber || $0 == "." }
                let parts = cleaned.split(separator: ".", maxSplits: 1)
                let whole = Int(parts.first ?? "0") ?? 0
                let fractionText = parts.count > 1 ? String(parts[1].prefix(2)) : ""
                let fraction = Int(fractionText.padding(toLength: 2, withPad: "0", startingAt: 0)) ?? 0
                rate.rateScaled = whole * ExchangeRate.scale + fraction * 100
                rate.updatedAt = .now
            }
        )
    }

    private func make(_ code: String) -> ExchangeRate {
        let rate = ExchangeRate(code: code)
        context.insert(rate)
        return rate
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: date)
    }
}
