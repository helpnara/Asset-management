import Core
import CoreData
import SwiftUI

/// 은퇴 후 소득 하나. 국민연금 · 퇴직연금 · 개인연금 · 임대소득.
struct IncomeStreamEditView: View {
    @ObservedObject var stream: IncomeStream
    /// 방금 만든 것인가 — 취소하면 지운다 (104번).
    var isNew = false
    @State private var snapshot: EditSnapshot?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var hasEnd: Bool
    /// 국민연금 추정기 (D3).
    @State private var isEstimatingPension = false

    init(stream: IncomeStream, isNew: Bool = false) {
        self.stream = stream
        self.isNew = isNew
        _hasEnd = State(initialValue: stream.endYear > 0)
    }

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름 (국민연금 · 퇴직연금 …)", text: $stream.label)
                    MoneyField(title: "월 수령액", minorUnits: $stream.monthlyAmountMinor)
                } footer: {
                    // 여기를 액면가로 적으면 30년 뒤 계산이 통째로 틀린다.
                    Text("**오늘 돈 기준**으로 적으세요. \"65세부터 월 150만원\"의 150만원은 지금 물가로 말한 것이지 그때의 액면가가 아닙니다.")
                }

                Section {
                    Button {
                        isEstimatingPension = true
                    } label: {
                        Label("국민연금 얼마나 받을까 — 추정해서 채우기", systemImage: "function")
                    }
                } footer: {
                    Text("가입 기간과 평균 소득으로 근사합니다. 모르면 0 으로 두고, 공단에서 확인한 값을 알게 되면 그때 고치세요.")
                }

                Section {
                    Stepper(value: $stream.startYear, in: currentYear...(currentYear + 60)) {
                        Text(verbatim: "\(stream.startYear)년부터")
                    }
                    Toggle("끝나는 해가 있다", isOn: $hasEnd)
                    if hasEnd {
                        Stepper(value: endYear, in: stream.startYear...(currentYear + 80)) {
                            Text(verbatim: "\(max(stream.endYear, stream.startYear))년까지")
                        }
                    }
                } header: {
                    Text("받는 기간")
                } footer: {
                    Text(hasEnd
                         ? "확정 기간형입니다. 그 뒤로는 생활비를 자산에서 다 꺼내야 합니다."
                         : "종신입니다. 국민연금이 여기 해당합니다.")
                }

                Section {
                    Toggle("물가에 연동된다", isOn: $stream.isInflationLinked)
                } footer: {
                    // 이 토글 하나가 30년 뒤 결과를 절반으로 가른다.
                    Text(stream.isInflationLinked
                         ? "해마다 물가만큼 오릅니다. 국민연금이 그렇습니다."
                         : "액면가가 고정입니다. 물가가 오르는 만큼 실제 구매력은 계속 줄어듭니다 — 30년이면 절반 아래로 내려갑니다.")
                }

                if !isNew {
                    Section {
                        DeleteButton("\(stream.label.isEmpty ? "이 수입" : stream.label) 을(를) 삭제할까요?",
                                     consequence: "은퇴 후 이 수입이 궤적에서 빠집니다. 되돌릴 수 없습니다.") {
                            context.delete(stream)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("은퇴 후 소득")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { if snapshot == nil { snapshot = EditSnapshot(of: stream) } }
            .onChange(of: hasEnd) { _, on in
                stream.endYear = on ? max(stream.endYear, stream.startYear + 10) : 0
            }
            .sheet(isPresented: $isEstimatingPension, onDismiss: { hasEnd = stream.endYear > 0 }) {
                NationalPensionEstimatorView(stream: stream)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { cancel() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    /// 종신이면 0으로 저장하므로 Stepper 에는 시작 연도를 바닥으로 깐 값을 보여준다.
    private var endYear: Binding<Int> {
        Binding(
            get: { max(stream.endYear, stream.startYear) },
            set: { stream.endYear = $0 }
        )
    }

    private func cancel() {
        if isNew { context.delete(stream) } else { snapshot?.restore(to: stream) }
        dismiss()
    }
}
