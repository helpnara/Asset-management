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

/// 사용자가 준 기본 원칙 스물여섯 (docs/08-feedback.md 24번 → 211번).
///
/// **원문 그대로다.** 앱이 문장을 다듬지 않는다 — 강의에서 듣고 적어 온 말이
/// 앱의 말로 바뀌면 그 순간 남의 문장이 된다. 넣은 뒤에는 고치고 지울 수 있다.
/// 고친 것은 사용자가 "고쳐 달라" 고 한 오타 두 곳뿐이다(18번 `인생에서` · 24번 `라이프스타일`, 2026-11-01).
///
/// **설명(`detail`)도 사용자의 말이다** (211번). 처음 열여섯은 설명 없이 제목만 넣었다 — 설명을
/// 지어 붙이면 앱의 말이 되므로. 2026-11-01 사용자가 자기 기기의 스물여섯 개를 설명까지 그대로
/// 기본값으로 달라고 해서, 그 설명을 옮긴다. 설명이 없는 원칙은 빈 칸이다.
///
/// **첫 실행 때 자동으로 심지 않는다.** 그러면 이미 쓰고 있는 사람에게는 영영
/// 오지 않는다. 운용 원칙 화면의 `기본 원칙 넣기` 버튼이 채운다.
enum DefaultPrinciples {
    struct Item: Hashable {
        let title: String
        var detail: String = ""
    }

    static let items: [Item] = [
        Item(title: "주식투자하는 유일한 이유는 노후준비하기 위함이다."),
        Item(title: "시간에 투자하라"),
        Item(title: "빚내서 투자하지 마라", detail: "변동성에 버틸 수가 없다."),
        Item(title: "여유자금으로 장기 투자하라",
             detail: "자금의 성격이 매우 중요하다. 전월세 자금, 대출금 등은 투자금으로 쓰면 안된다."),
        Item(title: "주가보다 기업을 보라", detail: "변동성보다는 펀더멘탈에 관심을 가지자"),
        Item(title: "하락을 두려워하지 마라",
             detail: "변동성 즉, 시장에 투자한 것이 아니라 동업하고자 하는 기업에 투자한 것이다. 믿고 기다릴 수 있어야 한다. 내가 투자한 기업이 어제와 오늘 바뀌었는가?"),
        Item(title: "남을 따라 투자하지 마라"),
        Item(title: "ETF를 꾸준히 모아라", detail: "가격보다는 몇주를 가지고 있는지에 집중하라. 모아가는 것이다."),
        Item(title: "ISA·연금저축·퇴직연금을 활용하라"),
        Item(title: "소비보다 자산을 먼저 만들어라"),
        Item(title: "일찍 시작하고 오래 투자하라"),
        Item(title: "복리는 시간과 함께 커진다"),
        Item(title: "노후 준비는 지금부터 시작하라"),
        Item(title: "부동산에 자산을 과도하게 집중하지 마라"),
        Item(title: "돈(자본, 자산)이 일하게 만들어라", detail: "왜 내 노동이 일을하냐?"),
        Item(title: "자녀에게 점수보다 금융과 문제해결 능력을 가르쳐라"),
        Item(title: "투자는 돈을 버는 기술이 아니라 삶을 설계하는 철학이다"),
        Item(title: "오늘이 내 남은 인생에서 가장 젊은 날이다",
             detail: "지금 당장 투자를 시작해라. 시간이 복리의 마법을 선물해줄 것이다"),
        Item(title: "심플하게 살자! 경우의 수를 줄이자!", detail: "투자 방향, 종목 수 등 단순해야 관리가 가능하다."),
        Item(title: "No market timing, fully invested!", detail: "자꾸 가격을 맞추려고 하지마라."),
        Item(title: "주식은 철학이고 훈련이고 라이프스타일이다"),
        Item(title: "아이들에게 사교육비(30조원)보다는 투자를!", detail: "창업하는 분위기 조성, 아이들도 부자가 될 수 있게~"),
        Item(title: "집 마련에 집착하지 마라",
             detail: "전월세가 문제가 아니다. 전월세가 자가 대비 적절한지를 판단할 수 있어야 한다. 5% 규칙!"),
        Item(title: "부자처럼 보이려고 하지 말고 진짜 부자가 되어라.", detail: "그만큼 라이프스타일 습관이 중요하다."),
        Item(title: "투자하기 가장 좋은 날은 어제께다.", detail: "미루지 말자! 타이밍을 맞추려고 하지 말자! 습관이다!"),
        Item(title: "주식 투자는 그 회사의 주인이 되는 것이다."),
    ]

    /// 이미 적어 둔 것과 겹치지 않게 **빠진 것만** 고른다 — 제목으로 견준다.
    /// 두 번 눌러도 스물여섯이 쉰둘이 되지 않는다.
    static func missing(from existing: [Principle]) -> [Item] {
        let have = Set(existing.map { normalized($0.title) })
        return items.filter { !have.contains(normalized($0.title)) }
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
    /// 자산 탭에서 평가액을 직접 고쳤다 (111번). 주간 점검 밖의 값 변경.
    case valueEdit
    case other

    var label: String {
        switch self {
        case .weeklyEntry: return "주간 점검"
        case .structure: return "구성 변경"
        case .planValue: return "계획 변경"
        case .milestone: return "축하"
        case .valueEdit: return "값 변경"
        case .other: return "기타"
        }
    }
}

extension ChangeLog {
    var kind: ChangeKind { ChangeKind(rawValue: kindRaw) ?? .other }
}
