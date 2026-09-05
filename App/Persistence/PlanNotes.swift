import Core
import Foundation
import SwiftData

/// 사용자가 직접 찍는 마일스톤.
///
/// 자동 판정(수익 > 적립금 · 자산 2배 · 목표 달성)만으로는 담기지 않는 것들이 있다.
/// "아이 대학 입학", "전세 만기", "차 교체" 같은 것들. 금액이 아니라 **연도에
/// 이름을 붙이는 일**이라 사용자만 할 수 있다.
@Model
final class UserMilestone {
    var id: UUID = UUID()
    var year: Int = Calendar.current.component(.year, from: .now) + 5
    var label: String = ""
    var note: String = ""
    var sortIndex: Int = 0

    init(year: Int? = nil, label: String = "", sortIndex: Int = 0) {
        self.year = year ?? (Calendar.current.component(.year, from: .now) + 5)
        self.label = label
        self.sortIndex = sortIndex
    }
}

/// 유의사항 · 할 일.
///
/// 1페이지 아래쪽의 `※ 주석` 과 `연간 한도` 메모가 여기로 온다.
/// 기한이 있으면 그날 아침에 한 번 부른다 — 매주 점검과 섞이지 않게 따로 건다.
@Model
final class TodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var detail: String = ""
    var categoryRaw: String = TodoCategory.note.rawValue
    /// 기한. nil 이면 기한 없는 메모다.
    var dueDate: Date?
    var isDone: Bool = false
    /// 해마다 되돌아오는 항목인가 (연간 한도 채우기 등).
    var repeatsYearly: Bool = false
    var completedAt: Date?
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    init(title: String = "", category: TodoCategory = .note, sortIndex: Int = 0) {
        self.title = title
        self.categoryRaw = category.rawValue
        self.sortIndex = sortIndex
    }
}

enum TodoCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case tax          // 세금 · 규제
    case limit        // 연간 한도
    case deadline     // 기한
    case note         // 메모

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tax: return "세금 · 규제"
        case .limit: return "연간 한도"
        case .deadline: return "기한"
        case .note: return "메모"
        }
    }

    var symbol: String {
        switch self {
        case .tax: return "doc.text"
        case .limit: return "gauge.with.dots.needle.33percent"
        case .deadline: return "calendar.badge.exclamationmark"
        case .note: return "note.text"
        }
    }
}

extension TodoItem {
    var category: TodoCategory {
        get { TodoCategory(rawValue: categoryRaw) ?? .note }
        set { categoryRaw = newValue.rawValue }
    }

    /// 기한까지 남은 날. 기한이 없으면 nil, 지났으면 음수.
    var daysRemaining: Int? {
        guard let dueDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents([.day],
                                       from: calendar.startOfDay(for: .now),
                                       to: calendar.startOfDay(for: dueDate)).day
    }

    var isOverdue: Bool { (daysRemaining ?? 1) < 0 && !isDone }
}
