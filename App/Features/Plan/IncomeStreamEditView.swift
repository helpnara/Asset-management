import Core
import SwiftData
import SwiftUI

/// 은퇴 후 소득 하나. 국민연금 · 퇴직연금 · 개인연금 · 임대소득.
struct IncomeStreamEditView: View {
    @Bindable var stream: IncomeStream
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var hasEnd: Bool

    init(stream: IncomeStream) {
        self.stream = stream
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
            }
            .navigationTitle("은퇴 후 소득")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: hasEnd) { _, on in
                stream.endYear = on ? max(stream.endYear, stream.startYear + 10) : 0
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DeleteButton("\(stream.title.isEmpty ? "이 수입" : stream.title) 을(를) 삭제할까요?",
                                 consequence: "은퇴 후 이 수입이 궤적에서 빠집니다. 되돌릴 수 없습니다.") {
                        context.delete(stream)
                        dismiss()
                    }
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
}
