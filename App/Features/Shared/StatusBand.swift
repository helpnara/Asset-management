import SwiftUI

/// **진행 상황 띠 — 앱에 한 가지 모양** (docs/08-feedback.md 169번).
///
/// 166번의 `반영 중` 띠를 이어받되, 화면마다 붙이던 것을 `RootView` 의 탭
/// 뿌리 한 자리로 옮겼다. **`safeAreaInset` 이 아니라 `overlay` 다** — 안전
/// 영역을 밀면 띠가 뜨고 사라질 때마다 본문 높이가 바뀌어 목록이 들썩인다.
/// 겹쳐 올리면 본문은 그대로다.
///
/// 문구는 하는 일 하나 — `반영 중` · `그리는 중`. 부탁은 안 적는다.
struct StatusBand: View {
    let text: String
    var spinning = true
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if spinning {
                ProgressView().controlSize(.small)
            } else if let icon {
                Image(systemName: icon)
                    .font(.scaled(11, weight: .medium))
                    .foregroundStyle(Color.ink)
            }
            Text(text)
                .font(.scaled(12, weight: .medium))
                .foregroundStyle(Color.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.surface)
        .overlay(Rectangle().fill(Color.rule).frame(height: 1), alignment: .top)
    }
}

/// 탭 뿌리에 한 번 붙인다. `Progress.shared` 에 일이 있으면 아래에 띠를 겹친다.
private struct StatusBandHost: ViewModifier {
    @State private var progress = Progress.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let label = progress.label {
                    StatusBand(text: label)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: progress.label)
    }
}

/// 화면이 "지금 이 일을 하고 있다" 고 목록에 올리는 방법. 플래그가 참인 동안
/// 올라가 있고, 거짓이 되거나 화면이 사라지면 내려간다.
private struct ProgressReporter: ViewModifier {
    let label: String
    let isActive: Bool
    @State private var token: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear { sync(isActive) }
            .onChange(of: isActive) { _, active in sync(active) }
            .onDisappear { sync(false) }
    }

    private func sync(_ active: Bool) {
        if active {
            if token == nil { token = Progress.shared.begin(label) }
        } else if let token {
            Progress.shared.end(token)
            self.token = nil
        }
    }
}

extension View {
    /// 탭 뿌리 · 시트 뿌리에 한 번.
    func statusBand() -> some View {
        modifier(StatusBandHost())
    }

    /// `isActive` 가 참인 동안 띠에 `label` 을 올린다.
    func reportsProgress(_ label: String, when isActive: Bool) -> some View {
        modifier(ProgressReporter(label: label, isActive: isActive))
    }
}
