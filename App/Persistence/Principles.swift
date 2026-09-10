import Foundation
import CoreData

/// 운용 원칙 — 1페이지 D블록.
///
/// 원본 계획서에서 가장 사람 냄새가 나는 부분이다. "하락장에도 멈추지 않는다"
/// 같은 문장은 앱이 지어낼 수 없다. 그래서 **담을 곳만 만들고 문장은 사용자가
/// 쓴다** (docs/08-feedback.md 10번).
///
/// 자동 점검이 되는 것과 안 되는 것이 섞여 있다. 되는 것은 자산 진단이
/// 이미 여섯 가지를 보고 있으므로, 여기서는 **글로 남기는 몫**만 맡는다.
extension Principle {
    convenience init(context: NSManagedObjectContext, order: Int = 1, title: String = "", detail: String = "") {
        self.init(context: context)
        self.order = order
        self.title = title
        self.detail = detail
    }
}

/// 사용자가 준 기본 원칙 열여섯 (docs/08-feedback.md 24번).
///
/// **원문 그대로다.** 앱이 문장을 다듬지 않는다 — 강의에서 듣고 적어 온 말이
/// 앱의 말로 바뀌면 그 순간 남의 문장이 된다. 넣은 뒤에는 고치고 지울 수 있다.
///
/// `detail` 은 비워 둔다. 열여섯이 전부 한 줄짜리 문장이라 설명을 지어 붙이면
/// 역시 앱의 말이 된다. 필요하면 직접 적으면 된다.
///
/// **첫 실행 때 자동으로 심지 않는다.** 그러면 이미 쓰고 있는 사람에게는 영영
/// 오지 않는다. 운용 원칙 화면의 `기본 원칙 넣기` 버튼이 채운다.
enum DefaultPrinciples {
    static let titles: [String] = [
        "시간에 투자하라",
        "빚내서 투자하지 마라",
        "여유자금으로 장기 투자하라",
        "주가보다 기업을 보라",
        "하락을 두려워하지 마라",
        "남을 따라 투자하지 마라",
        "ETF를 꾸준히 모아라",
        "ISA·연금저축·퇴직연금을 활용하라",
        "소비보다 자산을 먼저 만들어라",
        "일찍 시작하고 오래 투자하라",
        "복리는 시간과 함께 커진다",
        "노후 준비는 지금부터 시작하라",
        "부동산에 자산을 과도하게 집중하지 마라",
        "돈이 일하게 만들어라",
        "자녀에게 점수보다 금융과 문제해결 능력을 가르쳐라",
        "투자는 돈을 버는 기술이 아니라 삶을 설계하는 철학이다"
    ]

    /// 이미 적어 둔 것과 겹치지 않게 **빠진 것만** 고른다.
    /// 두 번 눌러도 열여섯이 서른둘이 되지 않는다.
    static func missing(from existing: [Principle]) -> [String] {
        let have = Set(existing.map { normalized($0.title) })
        return titles.filter { !have.contains(normalized($0)) }
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// 무엇이 언제 어떻게 바뀌었는지.
///
/// 가족 공유(13번)를 붙이면 "누가" 가 참가자 이름이 되지만, **공유가 없어도
/// 쓸모가 있다** — 지난주에 내가 무엇을 고쳤는지 돌아볼 수 있다.
/// 스키마를 바꾸는 김에 지금 넣어 둔다. 나중에 넣으면 배포가 한 번 더 필요하다.
///
/// **전부 기록하지 않는다.** 주간 점검 입력 · 계좌와 종목 추가·삭제 ·
/// 계획 값 변경 셋만 남긴다. 모든 필드를 남기면 금세 쓸모없이 길어진다.
extension ChangeLog {
    convenience init(context: NSManagedObjectContext, kind: ChangeKind = .other, subject: String = "", summary: String = "", actor: String = "") {
        self.init(context: context)
        self.kindRaw = kind.rawValue
        self.subject = subject
        self.summary = summary
        self.actor = actor
    }
}

enum ChangeKind: String, Codable, Sendable, CaseIterable {
    case weeklyEntry    // 주간 점검 입력
    case structure      // 계좌 · 종목 추가와 삭제
    case planValue      // 계획 값 변경
    /// 선을 넘긴 주 — 억 단위 · 두 배 · 목표 · 연속 기록 (88번).
    case milestone
    case other

    var label: String {
        switch self {
        case .weeklyEntry: return "주간 점검"
        case .structure: return "구성 변경"
        case .planValue: return "계획 변경"
        case .milestone: return "축하"
        case .other: return "기타"
        }
    }
}

extension ChangeLog {
    var kind: ChangeKind { ChangeKind(rawValue: kindRaw) ?? .other }
}
