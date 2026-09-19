import Core
import Foundation
import CoreData

/// 사용자가 직접 찍는 마일스톤.
///
/// 자동 판정(수익 > 적립금 · 자산 2배 · 목표 달성)만으로는 담기지 않는 것들이 있다.
/// "아이 대학 입학", "전세 만기", "차 교체" 같은 것들. 금액이 아니라 **연도에
/// 이름을 붙이는 일**이라 사용자만 할 수 있다.
extension UserMilestone {
    convenience init(context: NSManagedObjectContext, year: Int? = nil, label: String = "", sortIndex: Int = 0, memberID: UUID? = nil) {
        self.init(context: context)
        self.memberID = memberID
        self.year = year ?? (Calendar.current.component(.year, from: .now) + 5)
        self.label = label
        self.sortIndex = sortIndex
    }
}

/// 챙길 것 (172번 — 예전 이름 `유의사항 · 할 일`).
///
/// 1페이지 아래쪽의 `※ 주석` 과 `연간 한도` 메모가 여기로 온다.
/// 기한이 있으면 그날 아침에 한 번 부른다 — 매주 점검과 섞이지 않게 따로 건다.
extension TodoItem {
    convenience init(context: NSManagedObjectContext, title: String = "", category: TodoCategory = .note, sortIndex: Int = 0) {
        self.init(context: context)
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
        case .note: return "기타"
        }
    }

    /// 꼬리표로 보일 것. `기타` 는 안 붙인다 — 붙일 말이 없다.
    var showsTag: Bool { self != .note }

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

    /// **시간으로 묶는다** (172번). 분류(세금 · 한도 …)로 묶으면 "언제까지" 가
    /// 안 보였다. 챙길 것은 언제가 먼저다.
    enum Bucket: String, CaseIterable, Identifiable {
        case overdue = "지난 것"
        case soon = "30일 안"
        case later = "그 뒤"
        case undated = "날짜 없음"
        var id: String { rawValue }
    }

    var bucket: Bucket {
        guard let days = daysRemaining else { return .undated }
        if days < 0 { return .overdue }
        if days <= 30 { return .soon }
        return .later
    }

    /// `3일 지남` · `오늘까지` · `102일 남음`. 날짜가 없으면 빈 글.
    var dueText: String {
        guard let days = daysRemaining else { return "" }
        if days < 0 { return "\(-days)일 지남" }
        if days == 0 { return "오늘까지" }
        return "\(days)일 남음"
    }
}


/// 저장해 둔 What-if 시나리오.
///
/// 시뮬레이션 손잡이는 저장되지 않는다 — 그게 [계획에 반영]과 나눈 이유다.
/// 그런데 "월 500만 · 은퇴 5년 늦춤"처럼 마음에 든 조합을 다시 찾으려면
/// 손잡이를 처음부터 다시 돌려야 한다. 그 조합에 이름을 붙여 두는 것이 이것이다.
extension Scenario {
    convenience init(context: NSManagedObjectContext, name: String = "", monthlyMinor: Int = 0, retirementYear: Int = 0,
         returnBP: Int = 800, volatilityBP: Int = 1_500, projectedMinor: Int = 0) {
        self.init(context: context)
        self.name = name
        self.monthlyMinor = monthlyMinor
        self.retirementYear = retirementYear > 0
            ? retirementYear
            : Calendar.current.component(.year, from: .now) + 23
        self.returnBP = returnBP
        self.volatilityBP = volatilityBP
        self.projectedMinor = projectedMinor
    }
}

extension Scenario {
    var projected: Money { Money(minorUnits: projectedMinor, currency: .krw) }
}
