import CoreData
import Foundation

/// 종목을 왜 샀나 (186번). 쓰는 길은 `add(...)` 하나, 읽는 길은 `sortedNotes` 다.
extension Holding {

    /// **최신이 위.** 지금 생각이 먼저 읽혀야 한다.
    ///
    /// 관계에서 뽑으므로 가져오기(fetch)가 없다 — `sortedHoldings` 와 같은 꼴이다.
    /// 지운 것을 빼는 것도 같은 이유다 (178번): 지운 객체가 관계에 한 박자
    /// 남아 있어 빈 줄이 반짝 스친다.
    var sortedNotes: [HoldingNote] {
        (notes as? Set<HoldingNote> ?? []).filter { !$0.isDeleted }
            .sorted { ($0.at, $0.id.uuidString) > ($1.at, $1.id.uuidString) }
    }

    /// 목록 한 줄에 보여 줄 **가장 최근 이유**. 없으면 nil.
    ///
    /// 줄바꿈은 공백으로 편다 — 목록에서는 한 줄만 쓰는데, 줄바꿈이 남아
    /// 있으면 `Text` 가 첫 줄만 그리고 나머지를 버려서 문장이 잘린 것처럼
    /// 보인다.
    var latestNoteLine: String? {
        guard let body = sortedNotes.first?.body.trimmed, !body.isEmpty else { return nil }
        return body.replacingOccurrences(of: "\n", with: " ")
    }
}

extension HoldingNote {

    /// 한 줄 적는다. 빈 글은 안 남긴다.
    @MainActor
    @discardableResult
    static func add(_ body: String, to holding: Holding,
                    in context: NSManagedObjectContext) -> HoldingNote? {
        let text = body.trimmed
        guard !text.isEmpty else { return nil }
        let note = HoldingNote(context: context)
        note.body = text
        note.actor = ActorName.current
        note.holding = holding
        return note
    }

    /// `2026-09-24 · 아빠` — 목록의 머리말.
    var stamp: String {
        let day = Self.dayFormatter.string(from: at)
        return actor.isEmpty ? day : "\(day) · \(actor)"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d."
        return formatter
    }()
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
