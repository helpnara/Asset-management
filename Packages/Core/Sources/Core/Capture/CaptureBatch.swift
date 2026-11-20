import Foundation

/// **캡처 여러 장 → 계좌별 묶음 → 앱 계좌 · 종목과 짝** (222번, docs/25 7~8 단계).
///
/// `CaptureParser` 가 한 장씩 읽은 결과를 받아:
/// 1. **묶는다** — 계좌 줄이나 총액이 있는 장이 새 묶음을 연다. 둘 다 없는 장(아래로 넘겨 찍은 장)은 앞 묶음에 붙는다
///    — 다만 그 장의 종목이 앞 묶음과 다른 계좌를 가리키면 따로 둔다. 겹쳐 찍힌 종목은 이름으로 하나만 남긴다.
/// 2. **계좌를 고른다** — 기억해 둔 표시(`captureKey`)가 같은 계좌 → 없으면 종목이 가장 많이 짝지어지는 계좌(하나일 때만).
///    고르지 못하면 nil — 사람이 고른다.
/// 3. **그 계좌 안에서만 짝짓는다** — 같은 종목이 여러 계좌에 있어도(같은 ETF 를 IRP · 연금저축에) 섞이지 않게.
///    기억해 둔 증권사 이름(`captureName`)이 먼저, 그다음 `CaptureParser.match`. 한 종목은 한 번만.
///
/// 관리 객체를 모른다 — 앱이 값(`AccountInfo`)으로 건넨다(CLAUDE.md, ADR-0002).
public enum CaptureBatch {

    public struct HoldingInfo: Sendable, Hashable {
        public let id: UUID
        public let name: String
        /// 증권사 캡처에 나오는 이름 — 앱 이름과 다를 때만, 아니면 빈 값.
        public let captureName: String

        public init(id: UUID, name: String, captureName: String) {
            self.id = id
            self.name = name
            self.captureName = captureName
        }
    }

    public struct AccountInfo: Sendable, Hashable {
        public let id: UUID
        /// 캡처에서 이 계좌를 알아보는 표시(`accountKey`) — 모르면 빈 값.
        public let captureKey: String
        public let holdings: [HoldingInfo]

        public init(id: UUID, captureKey: String, holdings: [HoldingInfo]) {
            self.id = id
            self.captureKey = captureKey
            self.holdings = holdings
        }
    }

    /// 한 계좌로 묶인 캡처 — 몇째 장들인지(0 부터)와 합친 읽기 결과.
    public struct Group: Sendable, Hashable {
        public let pages: [Int]
        public let result: CaptureParser.Result
    }

    /// 계좌 줄을 비교용 표시로 — 계좌 번호(숫자 8개 이상, `-` 섞여도)가 있으면 그 숫자만, 없으면 빈칸을 걷은 글자.
    /// 증권사가 같은 계좌를 늘 같은 줄로 보이므로 같음으로만 견준다.
    public static func accountKey(_ line: String?) -> String {
        guard let line, !line.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        var best = ""
        var run = ""
        for character in line + " " {
            if character.isNumber || character == "-" {
                run.append(character)
            } else {
                let digits = run.filter(\.isNumber)
                if digits.count >= 8, digits.count > best.count { best = digits }
                run = ""
            }
        }
        if !best.isEmpty { return best }
        return line.filter { !$0.isWhitespace }.lowercased()
    }

    /// 두 이름이 비교용으로 같은가 — 빈칸 · 말줄임 · 대소문자를 걷고. 같으면 증권사 이름을 따로 기억할 까닭이 없다.
    public static func isSameName(_ a: String, _ b: String) -> Bool {
        CaptureParser.normalized(a) == CaptureParser.normalized(b)
    }

    /// 읽은 종목마다 짝지은 앱 종목(`items` 와 같은 순서, 없으면 nil). **이 계좌의 종목 안에서만**, 한 종목은 한 번만.
    public static func pair(_ items: [CaptureParser.Item], with holdings: [HoldingInfo]) -> [UUID?] {
        var result = [UUID?](repeating: nil, count: items.count)
        var taken: Set<UUID> = []
        // 1) 기억해 둔 증권사 이름과 같은 것
        for (index, item) in items.enumerated() {
            let read = CaptureParser.normalized(item.name)
            if let holding = holdings.first(where: {
                !taken.contains($0.id) && !$0.captureName.isEmpty && CaptureParser.normalized($0.captureName) == read
            }) {
                result[index] = holding.id
                taken.insert(holding.id)
            }
        }
        // 2) 앱 이름과 맞추기 — 남은 종목 가운데서
        for (index, item) in items.enumerated() where result[index] == nil {
            let free = holdings.filter { !taken.contains($0.id) }
            guard let found = CaptureParser.match(item.name, among: free.map(\.name)) else { continue }
            result[index] = free[found.index].id
            taken.insert(free[found.index].id)
        }
        return result
    }

    /// 이 읽기 결과가 어느 계좌인가 — 기억해 둔 표시가 같은 계좌(하나일 때), 아니면 짝이 가장 많은 계좌(하나일 때). 모르면 nil.
    public static func suggestAccount(for result: CaptureParser.Result, among accounts: [AccountInfo]) -> UUID? {
        let key = accountKey(result.accountLine)
        if !key.isEmpty {
            let remembered = accounts.filter { $0.captureKey == key }
            if remembered.count == 1 { return remembered[0].id }
        }
        let scored = accounts.map { account in
            (id: account.id, count: pair(result.items, with: account.holdings).compactMap { $0 }.count)
        }
        guard let best = scored.max(by: { $0.count < $1.count }), best.count > 0,
              scored.filter({ $0.count == best.count }).count == 1 else { return nil }
        return best.id
    }

    /// 여러 장을 계좌별로 묶는다 — 위 1.
    public static func group(_ pages: [CaptureParser.Result], accounts: [AccountInfo]) -> [Group] {
        var groups: [(pages: [Int], results: [CaptureParser.Result])] = []
        for (index, page) in pages.enumerated() {
            let opensGroup = page.accountLine != nil || page.totalMinor != nil
            if !opensGroup, let last = groups.last {
                let mine = suggestAccount(for: page, among: accounts)
                let theirs = suggestAccount(for: merged(last.results), among: accounts)
                if mine == nil || theirs == nil || mine == theirs {
                    groups[groups.count - 1].pages.append(index)
                    groups[groups.count - 1].results.append(page)
                    continue
                }
            }
            groups.append((pages: [index], results: [page]))
        }
        return groups.map { Group(pages: $0.pages, result: merged($0.results)) }
    }

    /// 여러 장을 한 결과로 — 계좌 줄 · 총액 · 현금은 처음 나온 것, 종목은 이름이 같으면 처음 것만(겹쳐 찍힌 줄).
    static func merged(_ results: [CaptureParser.Result]) -> CaptureParser.Result {
        var seen: Set<String> = []
        var items: [CaptureParser.Item] = []
        for item in results.flatMap(\.items) where seen.insert(CaptureParser.normalized(item.name)).inserted {
            items.append(item)
        }
        return CaptureParser.Result(accountLine: results.lazy.compactMap(\.accountLine).first,
                                    totalMinor: results.lazy.compactMap(\.totalMinor).first,
                                    items: items,
                                    cashMinor: results.lazy.compactMap(\.cashMinor).first)
    }
}
