import Foundation
import SwiftData

/// 운용 원칙 — 1페이지 D블록.
///
/// 원본 계획서에서 가장 사람 냄새가 나는 부분이다. "하락장에도 멈추지 않는다"
/// 같은 문장은 앱이 지어낼 수 없다. 그래서 **담을 곳만 만들고 문장은 사용자가
/// 쓴다** (docs/08-feedback.md 10번).
///
/// 자동 점검이 되는 것과 안 되는 것이 섞여 있다. 되는 것은 자산 진단이
/// 이미 여섯 가지를 보고 있으므로, 여기서는 **글로 남기는 몫**만 맡는다.
@Model
final class Principle {
    var id: UUID = UUID()
    /// 1페이지에 붙는 번호. 1부터.
    var order: Int = 1
    var title: String = ""
    var detail: String = ""
    /// 점검 주기 메모 — `분기 1회` 처럼 자유롭게 적는다.
    var reviewNote: String = ""
    var createdAt: Date = Date.now

    init(order: Int = 1, title: String = "", detail: String = "") {
        self.order = order
        self.title = title
        self.detail = detail
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
@Model
final class ChangeLog {
    var id: UUID = UUID()
    var at: Date = Date.now
    /// 누가. 공유 전에는 기기 이름, 공유 후에는 참가자 이름이 들어간다.
    var actor: String = ""
    var kindRaw: String = ChangeKind.other.rawValue
    /// 무엇을. `아빠 / ISA / TIGER 미국S&P500` 처럼 사람이 읽는 경로다.
    var subject: String = ""
    /// 어떻게. `2,850,199 → 2,910,000`
    var summary: String = ""

    init(kind: ChangeKind = .other, subject: String = "", summary: String = "", actor: String = "") {
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
    case other

    var label: String {
        switch self {
        case .weeklyEntry: return "주간 점검"
        case .structure: return "구성 변경"
        case .planValue: return "계획 변경"
        case .other: return "기타"
        }
    }
}

extension ChangeLog {
    var kind: ChangeKind { ChangeKind(rawValue: kindRaw) ?? .other }
}
