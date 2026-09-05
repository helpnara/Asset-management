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


/// 사용자가 직접 넣는 환율. **외부에서 가져오지 않는다** (ADR-0005).
///
/// 시세와 같은 이유다. 매주 직접 적는 숫자가 이 앱의 기준이고, 환율도 그렇다.
/// 자동으로 갱신되면 지난주와 이번주 사이의 증감에 "내가 안 한 변화"가 섞인다.
@Model
final class ExchangeRate {
    var id: UUID = UUID()
    /// ISO 4217 코드. "USD", "JPY".
    var code: String = "USD"
    /// 이 통화 1단위가 몇 원인가. 1달러 = 1,380원이면 1380.
    ///
    /// 소수를 담아야 해서 스케일 정수를 쓴다 (100엔 = 900원이면 1엔 = 9.0원).
    /// 스케일 10⁴ — 0.0001원 단위까지. ADR-0003 의 정수 원칙 그대로다.
    var rateScaled: Int = 0
    var updatedAt: Date = Date.now

    init(code: String = "USD", rateScaled: Int = 0) {
        self.code = code
        self.rateScaled = rateScaled
    }
}

extension ExchangeRate {
    static let scale = 10_000

    var currency: CurrencyCode { CurrencyCode(code) }

    /// 1단위당 원. 0이면 아직 안 넣은 것이다.
    var rate: Decimal {
        get { Decimal(rateScaled) / Decimal(ExchangeRate.scale) }
        set {
            // `Decimals` 는 Core 안에만 있다(의도된 내부 유틸). 여기서는 같은 정책
            // (은행가 반올림)을 Foundation 으로 직접 쓴다.
            var input = newValue * Decimal(ExchangeRate.scale)
            var rounded = Decimal()
            NSDecimalRound(&rounded, &input, 0, .bankers)
            rateScaled = NSDecimalNumber(decimal: rounded).intValue
        }
    }

    var isSet: Bool { rateScaled > 0 }
}


/// 저장해 둔 What-if 시나리오.
///
/// 시뮬레이션 손잡이는 저장되지 않는다 — 그게 [계획에 반영]과 나눈 이유다.
/// 그런데 "월 500만 · 은퇴 5년 늦춤"처럼 마음에 든 조합을 다시 찾으려면
/// 손잡이를 처음부터 다시 돌려야 한다. 그 조합에 이름을 붙여 두는 것이 이것이다.
@Model
final class Scenario {
    var id: UUID = UUID()
    var name: String = ""
    var monthlyMinor: Int = 0
    var retirementYear: Int = Calendar.current.component(.year, from: .now) + 23
    var returnBP: Int = 800
    var volatilityBP: Int = 1_500
    /// 저장할 때의 은퇴 시점 예상. 목록에서 비교할 때 쓴다.
    var projectedMinor: Int = 0
    var createdAt: Date = Date.now

    init(name: String = "", monthlyMinor: Int = 0, retirementYear: Int = 0,
         returnBP: Int = 800, volatilityBP: Int = 1_500, projectedMinor: Int = 0) {
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


extension Array where Element == ExchangeRate {
    /// `Holding.position(rates:)` 이 받는 모양으로 납작하게 만든다.
    /// 값을 안 넣은 환율(0)은 빼서, 그 통화 종목이 합계에서 빠지게 한다.
    var lookup: [String: Decimal] {
        reduce(into: [:]) { result, rate in
            guard rate.isSet else { return }
            result[rate.code] = rate.rate
        }
    }
}
