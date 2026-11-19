import Foundation

/// **이번 주 많이 움직인 종목** (docs/08-feedback.md 219번 E, 11-19 사용자).
///
/// 점검 완료 화면은 총 변화 하나만 말해서 "무엇이 움직였나" 를 알려면 자산 탭을
/// 종목마다 열어야 했다. 점검이 끝날 때 종목마다 그 주 값이 남으므로(`HoldingRecord`,
/// A3) 지난 점검의 값과 견줘 **오른 것 위 셋 · 내린 것 아래 셋** 을 고른다.
///
/// 부채 종목은 부르는 쪽에서 부호를 뒤집어 넘긴다 — 대출이 줄면 순자산이 는다.
/// 지난 기록에 없는 종목(새로 만든 것)은 빼고, 움직이지 않은 종목도 뺀다.
public enum WeeklyMovers {

    /// 견줄 한 종목. `value` 는 순자산 쪽 부호다(부채는 음수).
    public struct Entry: Sendable, Hashable {
        public let id: UUID
        public let name: String
        public let detail: String
        public let value: Money

        public init(id: UUID, name: String, detail: String, value: Money) {
            self.id = id
            self.name = name
            self.detail = detail
            self.value = value
        }
    }

    public struct Item: Sendable, Hashable, Identifiable {
        public let id: UUID
        public let name: String
        /// 계좌 이름 같은 보조 글.
        public let detail: String
        public let delta: Money
    }

    public struct Result: Sendable, Hashable {
        /// 많이 오른 순.
        public let gains: [Item]
        /// 많이 내린 순.
        public let losses: [Item]

        public var isEmpty: Bool { gains.isEmpty && losses.isEmpty }
    }

    /// `previous` 는 지난 점검의 종목별 값(같은 부호 규칙).
    /// 같은 크기면 이름 순으로 — 화면이 열 때마다 줄을 바꾸지 않게.
    public static func top(current: [Entry], previous: [UUID: Money], limit: Int = 3) -> Result {
        let items: [Item] = current.compactMap { entry in
            guard let before = previous[entry.id] else { return nil }
            let delta = entry.value - before
            guard !delta.isZero else { return nil }
            return Item(id: entry.id, name: entry.name, detail: entry.detail, delta: delta)
        }
        let limit = max(limit, 0)
        let gains = items
            .filter { $0.delta.minorUnits > 0 }
            .sorted { ($0.delta.minorUnits, $1.name) > ($1.delta.minorUnits, $0.name) }
        let losses = items
            .filter { $0.delta.minorUnits < 0 }
            .sorted { ($0.delta.minorUnits, $0.name) < ($1.delta.minorUnits, $1.name) }
        return Result(gains: Array(gains.prefix(limit)), losses: Array(losses.prefix(limit)))
    }
}
