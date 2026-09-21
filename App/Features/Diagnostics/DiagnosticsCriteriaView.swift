import Core
import CoreData
import SwiftUI

/// 진단 기준. **전부 사용자가 정한다.**
///
/// 기본값은 널리 쓰이는 수치일 뿐 정답이 아니다. 4% 규칙도, 부동산 35%도,
/// 미국 50%도 마찬가지다. 앱이 정답을 아는 척하면 사용자는 자기 기준을
/// 세우지 못하고, 그러면 규칙이 자기 것이 되지 않는다.
struct DiagnosticsCriteriaView: View {
    @ObservedObject var plan: Plan
    @Environment(\.dismiss) private var dismiss
    /// 미국 목표 줄을 누르면 가족 자산 배분을 이 시트 안에서 민다 (171번).
    /// `NavigationLink` 는 시트 안 `Form` 에서 눌러도 안 열렸다 (빌드 97 8번).
    @State private var showsAllocation = false

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
                        extraAnnual: plan.extraAnnualSpending,
                        withdrawalRate: plan.withdrawalRate) {
                        // 계획 탭의 목표 금액 자동 계산과 **같은 숫자**다 (154번).
                        Text("필요 자금 \(Won.abbreviated(required, suffix: "원")) — 은퇴 뒤 한 해에 쓸 돈(월 생활비 × 12 + 연 취미 · 여행 + 연 병원비)을 인출률로 나눈 값입니다. 4%면 25배, 3.5%면 약 28.6배가 됩니다.")
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
                    Text("구성원 편집에 월급·기타 수입을 적은 사람이 하나라도 있으면 그 합계를 쓰고 이 칸은 무시합니다. 아무도 안 적었을 때만 이 한 칸을 씁니다. 저축률 계산에만 쓰고 다른 화면에는 나오지 않습니다.")
                }

                Section {
                    percentRow("부동산 · 전월세보증금 상한", $plan.illiquidCapBP,
                               range: 0...10_000, step: 100)
                } header: {
                    Text("부동산 비중")
                } footer: {
                    Text("부동산은 팔지 않으면 생활비로 쓸 수 없습니다. 비중이 크면 자산은 많은데 쓸 돈이 없는 노후가 됩니다. 기본은 35% 입니다.")
                }

                Section {
                    // 미국 목표는 한 군데다 (A4). 가족 자산 배분에 적혀 있으면 그것을
                    // 읽고 여기서는 안 고친다 — 두 화면이 다른 값을 말하지 않게.
                    if let bp = plan.familyUSTargetBP {
                        // **줄을 누르면 가족 자산 배분이 열린다** (171번). 원본은 거기
                        // 하나다 — 지역 목표는 한국 · 미국 · 그 외가 합쳐 100 이라
                        // 여기서 미국만 고칠 수 없다. 대신 찾아가는 길을 한 번으로.
                        Button {
                            showsAllocation = true
                        } label: {
                            HStack {
                                Text("미국 목표 비중")
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Text("\(PercentFormatter.integer(Decimal(bp) / 10_000))% · 가족 자산 배분")
                                    .font(.figure(13))
                                    .foregroundStyle(Color.muted)
                                Image(systemName: "chevron.right")
                                    .font(.scaled(11, weight: .semibold))
                                    .foregroundStyle(Color.faint)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        percentRow("미국 목표 비중", $plan.usTargetBP, range: 0...10_000, step: 100)
                    }
                    // 허용 오차는 아래 `목표 비중 허용 오차` 하나를 같이 쓴다 (173번).
                } header: {
                    Text("국가 배분")
                } footer: {
                    // 바닥글은 설명이라 굵은 글씨를 쓰지 않는다 (174번).
                    Text(plan.familyUSTargetBP != nil
                         ? "미국 목표는 가족 자산 배분의 지역 목표입니다 — 한국 · 미국 · 그 외가 합쳐 100% 라 거기서 함께 정합니다. 줄을 누르면 그 화면이 열립니다. 허용 오차는 아래 목표 비중 허용 오차를 같이 씁니다."
                         : "투자자산 기준이고 기본은 미국 50 · 한국 50입니다. 가족 자산 배분에서 지역 목표를 적으면 그 값을 씁니다. 나머지가 전부 한국이라고 보지 않습니다 — 그 외 국가도 따로 셉니다. 허용 오차는 아래 목표 비중 허용 오차를 같이 씁니다.")
                }

                // 계좌 안 종목이 목표에서 얼마나 벗어나면 말해 줄지
                // (docs/08-feedback.md 20번).
                Section {
                    percentRow("목표 비중 허용 오차", $plan.driftToleranceBP,
                               range: 100...2_000, step: 100)
                } header: {
                    Text("목표 비중")
                } footer: {
                    Text("계좌 안 종목이 목표에서 이만큼 벗어나면 초과·부족으로 알립니다. 기본 ±3%p — 목표 20%인 종목은 17~23% 안이면 조용합니다. 좁게 잡을수록 자주 알립니다.")
                }

                // **한 주제는 한 구역** (176번). 예전에는 이 화면에 세제혜택 계좌가
                // 두 구역으로 갈라져 있었다 — 여기 안내 한 줄, 맨 아래 채우는 순서.
                // 그 사이에 `볼 규칙` 일곱 줄이 끼어 맨 아래 것이 외따로 떠 보였고,
                // 세법 고지도 두 번 적혀 있었다. 하나로 합친다.
                Section {
                    Text("계좌별 연간 한도와 올해 납입액은 자산 탭에서 계좌를 열어 넣습니다. IRP · 연금저축 · ISA 계좌에만 나타납니다.")
                        .font(.scaled(12))
                        .foregroundStyle(Color.muted)
                    // 채우는 순서. 예전에는 상수였고 주석에 "설정에서 고칠 수
                    // 있어야 한다" 고 적혀 있었다 (47번). 진단을 끄면 함께 숨는다.
                    if plan.enabledDiagnoses.contains(.taxAdvantagedOrder) {
                        ForEach(plan.contributionOrder, id: \.self) { kind in
                            HStack {
                                Text(kind.label)
                                Spacer()
                                Text(verbatim: "\((plan.contributionOrder.firstIndex(of: kind) ?? 0) + 1)")
                                    .font(.figure(13))
                                    .foregroundStyle(Color.faint)
                            }
                        }
                        .onMove { offsets, destination in
                            var order = plan.contributionOrder
                            order.move(fromOffsets: offsets, toOffset: destination)
                            plan.contributionOrder = order
                        }
                    }
                } header: {
                    Text("세제혜택 계좌")
                } footer: {
                    Text(plan.enabledDiagnoses.contains(.taxAdvantagedOrder)
                         ? "끌어서 채우는 순서를 바꿉니다. 진단이 \"다음 적립은 어디로\" 를 이 순서로 답합니다. 이 앱은 세법을 따라가지 않습니다 — 한도도 순서도 바뀌면 직접 고치세요."
                         : "이 앱은 세법을 따라가지 않습니다. 한도가 바뀌면 직접 고치세요 — 앱에 숫자를 박아 두면 세법이 바뀐 뒤 조용히 틀린 조언을 하게 됩니다.")
                }
                // **어떤 규칙을 볼지도 사용자가 정한다** (docs/08-feedback.md 47번).
                // 쓰지 않는 규칙이 늘 `조치` 로 떠 있으면 나머지 여섯까지 같이
                // 무시하게 된다 — 그게 진단 화면이 죽는 방식이다.
                Section {
                    ForEach(DiagnosisKind.allCases) { kind in
                        Toggle(kind.title, isOn: binding(for: kind))
                            .font(.scaled(14))
                    }
                } header: {
                    Text("볼 규칙")
                } footer: {
                    Text("끈 규칙은 진단 화면과 현황판 요약에서 빠집니다. 나중에 다시 켜면 그대로 돌아옵니다 — 기준값은 지워지지 않습니다.")
                }

            }
            .environment(\.editMode, .constant(.active))
            .onChange(of: plan.editFingerprint) { previous, _ in
                guard !previous.isEmpty else { return }
                plan.touch()
            }
            // 넓은 화면에서 라벨과 값이 양 끝으로 벌어지지 않게 (161번).
            .readableWidth()
            .navigationTitle("진단 기준")
            .navigationDestination(isPresented: $showsAllocation) { FamilyAllocationView() }
            .navigationBarTitleDisplayMode(.inline)
            // 금액 칸의 `만 · 억 · 완료` 띠 (152번 3-1).
            .moneyKeyboardBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    /// 규칙 하나의 켜짐. 계획의 `enabledDiagnoses` 를 그대로 읽고 쓴다.
    private func binding(for kind: DiagnosisKind) -> Binding<Bool> {
        Binding(
            get: { plan.enabledDiagnoses.contains(kind) },
            set: { on in
                var kinds = plan.enabledDiagnoses
                if on { kinds.insert(kind) } else { kinds.remove(kind) }
                // 전부 끄면 진단 화면이 통째로 비어 고장 난 것처럼 보인다.
                // 마지막 하나는 못 끄게 한다.
                guard !kinds.isEmpty else { return }
                plan.enabledDiagnoses = kinds
            }
        )
    }

    private func percentRow(_ title: String, _ value: Binding<Int>,
                            range: ClosedRange<Int>, step: Int) -> some View {
        // 계획 탭 · 계좌 편집과 같은 부품이다 (166번) — 누르는 즉시 숫자만.
        PercentStepper(title: title, basisPoints: value, range: range, step: step)
    }
}
