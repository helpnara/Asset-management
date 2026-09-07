import Core
import SwiftData
import SwiftUI

/// 진단 기준. **전부 사용자가 정한다.**
///
/// 기본값은 널리 쓰이는 수치일 뿐 정답이 아니다. 4% 규칙도, 부동산 35%도,
/// 미국 50%도 마찬가지다. 앱이 정답을 아는 척하면 사용자는 자기 기준을
/// 세우지 못하고, 그러면 규칙이 자기 것이 되지 않는다.
struct DiagnosticsCriteriaView: View {
    @Bindable var plan: Plan
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyField(title: "은퇴 후 월 생활비", minorUnits: $plan.monthlySpendingMinor)
                    percentRow("인출률", $plan.withdrawalRateBP, range: 200...800, step: 25)
                } header: {
                    Text("은퇴 필요 자금")
                } footer: {
                    if let required = Diagnostics.requiredNestEgg(
                        monthlySpending: plan.monthlySpending,
                        withdrawalRate: plan.withdrawalRate) {
                        Text("필요 자금 \(Won.abbreviated(required, suffix: "원")) — 연 생활비를 인출률로 나눈 값입니다. 4%면 25배, 3.5%면 약 28.6배가 됩니다.")
                    } else {
                        Text("월 생활비를 넣으면 필요 자금을 계산합니다. 지금 쓰는 생활비에서 출퇴근·교육비를 빼고 의료비를 더하면 대략 맞습니다.")
                    }
                }

                Section {
                    MoneyField(title: "세후 월 소득", minorUnits: $plan.monthlyIncomeMinor)
                    percentRow("최소 저축률", $plan.savingsFloorBP, range: 0...5_000, step: 100)
                } header: {
                    Text("선저축")
                } footer: {
                    Text("소득은 저축률 계산에만 쓰고 다른 화면에는 나오지 않습니다. 쓰고 남은 돈을 모으면 남지 않습니다 — 월급날 먼저 빠져나가게 두세요.")
                }

                Section {
                    percentRow("부동산 · 전월세보증금 상한", $plan.illiquidCapBP,
                               range: 0...10_000, step: 100)
                } header: {
                    Text("부동산 비중")
                } footer: {
                    Text("부동산은 팔지 않으면 생활비로 쓸 수 없습니다. 비중이 크면 자산은 많은데 쓸 돈이 없는 노후가 됩니다. **기본 35%**입니다.")
                }

                Section {
                    percentRow("미국 목표 비중", $plan.usTargetBP, range: 0...10_000, step: 100)
                    percentRow("허용 오차", $plan.mixToleranceBP, range: 100...2_000, step: 100)
                } header: {
                    Text("국가 배분")
                } footer: {
                    Text("투자자산 기준이고 **기본은 미국 50 · 한국 50**입니다. 나머지가 전부 한국이라고 보지 않습니다 — 그 외 국가도 따로 셉니다. 목표에서 허용 오차만큼 벗어나도 조치로 보지 않습니다.")
                }

                // 계좌 안 종목이 목표에서 얼마나 벗어나면 말해 줄지
                // (docs/08-feedback.md 20번).
                Section {
                    percentRow("목표 비중 허용 오차", $plan.driftToleranceBP,
                               range: 100...2_000, step: 100)
                } header: {
                    Text("목표 비중")
                } footer: {
                    Text("계좌 안 종목이 목표에서 이만큼 벗어나면 **초과**·**부족**으로 알립니다. **기본 ±3%p** — 목표 20%인 종목은 17~23% 안이면 조용합니다. 좁게 잡을수록 자주 알립니다.")
                }

                Section {
                    Text("계좌별 연간 한도와 올해 납입액은 자산 탭에서 계좌를 열어 넣습니다. IRP · 연금저축 · ISA 계좌에만 나타납니다.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.muted)
                } header: {
                    Text("세제혜택 계좌")
                } footer: {
                    Text("이 앱은 세법을 따라가지 않습니다. 한도가 바뀌면 직접 고치세요 — 앱에 숫자를 박아 두면 세법이 바뀐 뒤 조용히 틀린 조언을 하게 됩니다.")
                }
            }
            .onChange(of: plan.editFingerprint) { previous, _ in
                guard !previous.isEmpty else { return }
                plan.touch()
            }
            .navigationTitle("진단 기준")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func percentRow(_ title: String, _ value: Binding<Int>,
                            range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                // 1%p 단위로 움직이는 값에 소수점을 붙이면 `35.0%` 가 된다.
                Text(step % 100 == 0
                     ? "\(PercentFormatter.integer(Decimal(value.wrappedValue) / 10_000))%"
                     : "\(PercentFormatter.oneDecimal(Decimal(value.wrappedValue) / 10_000))%")
                    .font(.figure(14, weight: .medium))
                    .foregroundStyle(Color.ink)
            }
        }
    }
}
