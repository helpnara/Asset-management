import SwiftData
import SwiftUI

/// 1페이지 인쇄물에만 쓰이는 글귀들 (docs/08-feedback.md 21번).
///
/// **계획 화면에서 옮겨 왔다.** 계획은 한 번 세우고 계속 다듬는 것이라 그
/// 화면에는 언제 세웠고 언제 갱신했는지만 있으면 된다. 이 셋은 자주 안
/// 건드리는 값이고 계산에도 안 쓰이므로 인쇄물 쪽에 두는 편이 맞다.
struct OnePagerSettingsView: View {
    @Query private var plans: [Plan]

    var body: some View {
        Form {
            if let plan = plans.first {
                @Bindable var plan = plan
                Section {
                    TextField("우리 가족 노후자금 준비", text: $plan.title)
                } header: {
                    Text("문서 제목")
                } footer: {
                    Text("1페이지 맨 위와 PDF 파일 이름에 쓰입니다. **앱 이름(`느린 부자의 기록`)과는 다른 값**입니다 — 이건 문서의 제목입니다.")
                }

                Section {
                    TextField("2026.08 기준 · 이사 후 자산", text: $plan.asOfNote)
                } header: {
                    Text("기준 시점")
                } footer: {
                    Text("같은 자산을 두 번 세지 않기 위한 선언입니다.")
                }

                Section {
                    TextField("계획은 끝났다. 이제는 시간이 일한다.",
                              text: $plan.declaration, axis: .vertical)
                        .lineLimit(1...3)
                } header: {
                    Text("맨 밑 한 줄")
                } footer: {
                    Text("1페이지 맨 아래에 들어갑니다. 셋 다 인쇄물에만 쓰이고 계산은 건드리지 않습니다.")
                }
            } else {
                Text("계획을 먼저 만드세요")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.muted)
            }
        }
        .navigationTitle("1페이지 문서")
        .navigationBarTitleDisplayMode(.inline)
        // 여기서 고친 것도 계획의 수정 시각에 남는다.
        .onChange(of: plans.first?.editFingerprint) { previous, _ in
            guard previous != nil else { return }
            plans.first?.touch()
        }
    }
}
