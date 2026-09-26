import Core
import CoreData
import SwiftUI

struct CashEventEditView: View {
    @ObservedObject var event: CashEvent
    /// 방금 만든 것인가 — 취소하면 지운다 (104번).
    var isNew = false
    @State private var snapshot: EditSnapshot?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    /// 화면에서는 절댓값을 다루고 방향은 따로 고른다.
    /// 마이너스 부호를 숫자패드로 치게 하면 실수가 잦다.
    @State private var isInflow = true
    @State private var magnitude = 0

    var body: some View {
        // 지운 객체를 시트가 내려가며 한 번 더 그리다 죽지 않게 (189번).
        if event.isGone {
            Color.clear
        } else {
            editor
        }
    }

    @ViewBuilder private var editor: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("이름 (퇴직금 · 전월세보증금 전환 …)", text: $event.label)
                    DatePicker("시점", selection: date, displayedComponents: .date)
                }

                Section {
                    Picker("방향", selection: $isInflow) {
                        Text("유입").tag(true)
                        Text("유출").tag(false)
                    }
                    .pickerStyle(.segmented)
                    MoneyField(title: "금액", minorUnits: $magnitude)
                }

                // **토글은 앞으로의 날짜에만 보인다** (188번). 지난 날짜의 목돈은
                // 이미 적어 넣은 잔고에 들어 있으므로 앞으로의 궤적에서는 저절로
                // 빠지고, 계획선과 증감 분해에는 날짜대로 들어간다 — 켤 일이 없다.
                // 예전에는 "이미 자산에 넣어둔 목돈이라면 켜세요" 라고 해서, 켜면
                // 계획선에서 빠져 "계획보다 앞서 있습니다" 로 부풀려 보였다.
                if event.isUpcoming() {
                    Section {
                        Toggle("미리 받아 이미 자산에 넣어 둠", isOn: $event.isAlreadyReflected)
                    } footer: {
                        Text("날짜는 앞으로인데 돈은 벌써 계좌에 넣어 적어 둔 경우에만 켜세요. 예: 다음 달 전세금 전환분을 미리 받아 둔 것. 켜면 앞으로의 궤적에서 빠져 두 번 세지 않습니다.")
                    }
                } else {
                    Section {
                        Label("오늘이거나 지난 날짜입니다", systemImage: "clock.arrow.circlepath")
                            .font(.scaled(13))
                            .foregroundStyle(Color.muted)
                    } footer: {
                        Text("이미 적어 넣은 잔고에 들어 있으므로 앞으로의 궤적에서는 빠집니다. 대신 현황판의 증감 분해와 계획선에는 이 날짜에 들어갑니다 — 이 목돈이 수익으로 잘못 잡히지 않게 하는 것이 지난 목돈을 적는 이유입니다.")
                    }
                }

                Section("메모") {
                    TextField("메모", text: $event.note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if !isNew {
                    Section {
                        DeleteButton("\(event.label.isEmpty ? "이 이벤트" : event.label) 을(를) 삭제할까요?",
                                     consequence: "궤적에서 이 목돈이 빠집니다. 되돌릴 수 없습니다.") {
                            context.delete(event)
                            dismiss()
                        }
                    }
                }
            }
            // 넓은 화면에서 라벨과 값이 양 끝으로 벌어지지 않게 (161번).
            .readableWidth()
            .navigationTitle("목돈 이벤트")
            .navigationBarTitleDisplayMode(.inline)
            // 금액 칸의 `만 · 억 · 완료` 띠 (152번 3-1).
            .moneyKeyboardBar()
            .onAppear { if snapshot == nil { snapshot = EditSnapshot(of: event) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { cancel() }
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

    /// **`$event.date` 로 묶지 않는다** (189번 후속, 빌드 113). 날짜 칸은 연결을
    /// 제 손에 쥐고 있다가 화면이 닫힐 때 **본문과 따로** 다시 읽는다 — 본문 맨 위의
    /// `isGone` 가드를 거치지 않는다. 새로 만든 것을 `취소` 하면 지운 즉시 값이
    /// 비는데, 그 빈 날짜를 `Date` 로 바꾸다 죽었다. 읽는 자리에서 지웠는지 본다.
    private var date: Binding<Date> {
        Binding(get: { event.isGone ? .now : event.date },
                set: { if !event.isGone { event.date = $0 } })
    }

    private func cancel() {
        if isNew { context.delete(event) } else { snapshot?.restore(to: event) }
        dismiss()
    }
}
