import SwiftUI

/// 당겨서 새로고침 + 결과 한 줄 (docs/08-feedback.md 73번).
///
/// 메일 앱처럼 위에서 아래로 당기면 `SyncRefresh.run()` 이 돌고, 끝나면
/// "마지막 가져오기 N초 전 · 내보내기 N초 전" 이 화면 위에 잠깐 떴다 사라진다.
/// 스피너가 도는 동안 실제로 하는 일은 저장 · 상태 재판정이다.
extension View {
    func syncRefreshable(note: Binding<String?>) -> some View {
        self
            .refreshable {
                let text = await SyncRefresh.run()
                note.wrappedValue = text
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    if note.wrappedValue == text { note.wrappedValue = nil }
                }
            }
            .overlay(alignment: .top) {
                if let text = note.wrappedValue {
                    Text(text)
                        .font(.figure(11))
                        .foregroundStyle(Color.bodyText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.raised, in: Capsule())
                        .overlay(Capsule().stroke(Color.rule, lineWidth: 1))
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: note.wrappedValue)
    }
}
