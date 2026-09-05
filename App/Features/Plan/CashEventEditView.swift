import Core
import SwiftData
import SwiftUI

struct CashEventEditView: View {
    @Bindable var event: CashEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    /// 화면에서는 절댓값을 다루고 방향은 따로 고른다.
    /// 마이너스 부호를 숫자패드로 치게 하면 실수가 잦다.
    @State private var isInflow = true
    @State private var magnitude = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름 (퇴직금 · 전세보증금 전환 …)", text: $event.label)
                    DatePicker("시점", selection: $event.date, displayedComponents: .date)
                }

                Section {
                    Picker("방향", selection: $isInflow) {
                        Text("유입").tag(true)
                        Text("유출").tag(false)
                    }
                    .pickerStyle(.segmented)
                    MoneyField(title: "금액", minorUnits: $magnitude)
                }

                Section {
                    Toggle("이미 현재 잔고에 반영됨", isOn: $event.isAlreadyReflected)
                } footer: {
                    Text("이미 자산에 넣어둔 목돈이라면 켜세요. 예측에서 빼야 두 번 세지 않습니다.")
                }

                Section("메모") {
                    TextField("메모", text: $event.note, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .navigationTitle("목돈 이벤트")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("삭제", role: .destructive) {
                        context.delete(event)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        event.amountMinor = isInflow ? magnitude : -magnitude
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                isInflow = event.amountMinor >= 0
                magnitude = abs(event.amountMinor)
            }
            .onChange(of: magnitude) { _, _ in
                event.amountMinor = isInflow ? magnitude : -magnitude
            }
            .onChange(of: isInflow) { _, _ in
                event.amountMinor = isInflow ? magnitude : -magnitude
            }
        }
    }
}
