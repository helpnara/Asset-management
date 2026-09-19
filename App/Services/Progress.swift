import Foundation
import Observation

/// **앱 전체의 "지금 돌고 있는 일" 목록** (docs/08-feedback.md 169번).
///
/// 진행 상황 표시가 열두 자리에 제각각이었다 — 화면마다 띠를 붙이고, 손잡이
/// 옆에 회전 아이콘을 끼우고, 버튼 안에 아이콘을 넣고. 모양이 제각각인 것도
/// 문제지만, 끼어드는 아이콘과 붙었다 떨어지는 띠가 **본문을 밀어** 화면이
/// 들썩였다.
///
/// 이제 일을 시작하는 쪽은 여기에 이름만 올리고(`begin`), 끝나면 내린다(`end`).
/// 띠는 `StatusBand` 한 장이 `RootView` 에서 이 목록을 읽어 그린다. 화면은
/// 띠를 모른다 — `.reportsProgress("반영 중", when:)` 만 붙인다.
@MainActor
@Observable
final class Progress {
    static let shared = Progress()

    struct Job: Identifiable, Equatable {
        let id: UUID
        let label: String
    }

    private(set) var jobs: [Job] = []

    /// 띠에 적을 글. 가장 최근에 시작한 일이다.
    var label: String? { jobs.last?.label }
    var isActive: Bool { !jobs.isEmpty }

    private init() {}

    @discardableResult
    func begin(_ label: String) -> UUID {
        let id = UUID()
        jobs.append(Job(id: id, label: label))
        return id
    }

    func end(_ id: UUID) {
        jobs.removeAll { $0.id == id }
    }
}
