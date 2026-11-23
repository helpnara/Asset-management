import Foundation

/// **캡처 여러 장 → 계좌별 묶음 → 앱 계좌 · 종목과 짝** (222번, docs/25 7~8 단계).
///
/// `CaptureParser` 가 한 장씩 읽은 결과를 받아:
/// 1. **묶는다** (226번 — `assemble`) — 같은 계좌 머리는 하나로, 머리 없는 장(아래로 넘겨 찍은 장)은 겹친 줄 ·
///    검산 · 종목 짝 증거로 계좌에 붙인다(고른 순서가 섞여도). 묶음마다 **글자 줄을 이어 붙여 한 번에 다시 읽는다**(`stitch`).
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
        /// 캡처의 계좌 줄과 견줄 글자 — 구성원 이름 · 계좌 이름 · 기관 · 계좌 종류(`textScore`).
        public let owner: String
        public let name: String
        public let institution: String
        public let kind: String

        public init(id: UUID, captureKey: String, holdings: [HoldingInfo],
                    owner: String = "", name: String = "", institution: String = "", kind: String = "") {
            self.id = id
            self.captureKey = captureKey
            self.holdings = holdings
            self.owner = owner
            self.name = name
            self.institution = institution
            self.kind = kind
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

    /// 글자만 남긴 비교용 — 빈칸 · 괄호 · `_` · `-` 를 걷는다(`[연금저축계좌(신)]` → `연금저축계좌신`).
    static func compact(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// **계좌 줄과 앱 계좌 글자가 얼마나 맞나** (11-21 사용자: *"계좌 이름이 나오면 유사한 계좌라면 선택이 가능하지 않을까 …
    /// 텍스트 매칭 기법을 활용하면"*). 계좌 이름이 줄에 들어 있으면 3(`[퇴직연금_개인IRP] 아빠 IRP` ⊃ `개인IRP`),
    /// 구성원 이름이 줄의 낱말과 같으면 2(`딸` — 한 글자라 낱말로만 견준다), 기관 2, 계좌 종류 1. 두 글자 아래는 안 본다.
    public static func textScore(_ line: String?, _ account: AccountInfo) -> Int {
        guard let line, !line.isEmpty else { return 0 }
        let hay = compact(line)
        let words = Set(line.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init))
        var score = 0
        let name = compact(account.name)
        if name.count >= 2, hay.contains(name) { score += 3 }
        let owner = compact(account.owner)
        if !owner.isEmpty, words.contains(owner) { score += 2 }
        let institution = compact(account.institution)
        if institution.count >= 2, hay.contains(institution) { score += 2 }
        let kind = compact(account.kind)
        if kind.count >= 2, hay.contains(kind), kind != name { score += 1 }
        return score
    }

    /// 이 캡처와 계좌가 얼마나 맞나 — (짝지어지는 종목 수, 계좌 줄 글자 점수). 앞이 먼저, 같으면 뒤로 가린다.
    public static func score(for result: CaptureParser.Result, _ account: AccountInfo) -> (pairs: Int, text: Int) {
        (pair(result.items, with: account.holdings).compactMap { $0 }.count, textScore(result.accountLine, account))
    }

    /// 이 읽기 결과가 어느 계좌인가 — 기억해 둔 표시가 같은 계좌(하나일 때), 아니면 **(짝 수, 계좌 줄 글자 점수)** 가
    /// 가장 큰 계좌(하나일 때). 짝이 하나도 없으면 계좌 이름이 줄에 든 것(점수 3 이상)만. 모르면 nil.
    /// 같은 ETF 를 IRP · 연금저축 둘 다 가지면 짝 수가 같다 — 그때 `[연금저축계좌(신)] 아빠 연금저축` 이 가린다.
    public static func suggestAccount(for result: CaptureParser.Result, among accounts: [AccountInfo]) -> UUID? {
        let key = accountKey(result.accountLine)
        if !key.isEmpty {
            let remembered = accounts.filter { $0.captureKey == key }
            if remembered.count == 1 { return remembered[0].id }
        }
        let scored = accounts.map { account in (id: account.id, score: score(for: result, account)) }
        guard let best = scored.max(by: { ($0.score.pairs, $0.score.text) < ($1.score.pairs, $1.score.text) }),
              best.score.pairs > 0 || best.score.text >= 3,
              scored.filter({ $0.score == best.score }).count == 1 else { return nil }
        return best.id
    }

    /// **여러 장을 계좌별로 묶고, 묶음마다 글자 줄을 이어 붙여 한 번에 읽는다** (226번) — 앱이 쓰는 길.
    ///
    /// 장마다 글자 줄(`CaptureParser.Line`, 고른 차례). 계좌마다 한 장일 수도, 여러 장일 수도, 순서가 섞였을 수도 있다.
    public static func group(_ pages: [[CaptureParser.Line]], accounts: [AccountInfo]) -> [Group] {
        assemble(pages.map { CaptureParser.parse($0) }, lines: pages, accounts: accounts)
    }

    /// 장마다 읽은 결과만으로 묶는다 — 줄이 없으니 겹침 · 이어 읽기는 빼고 같은 규칙으로.
    public static func group(_ pages: [CaptureParser.Result], accounts: [AccountInfo]) -> [Group] {
        assemble(pages, lines: nil, accounts: accounts)
    }

    /// 묶기 — `Tools/ocr-sim/batch.py` 의 `group` 과 같다.
    /// 1. **같은 계좌 머리는 하나로** — 계좌 표시(번호)가 같거나, 표시가 없으면 총액이 같은 머리 장(머리가 붙어 다니는 앱)
    /// 2. **머리 없는 장은 증거로 배정** — 겹친 줄 100 · 검산이 닫힘 50 / 이미 닫혔는데 새 종목 −50 ·
    ///    종목 짝 10 × 짝 / 다른 계좌를 가리킴 −100 · 고른 순서로 바로 뒤 1. 센 증거(50 이상)로 먼저 정하고 나머지를 본다.
    ///    한 묶음만 가장 높아야 붙인다. 못 붙인 장은 서로 겹치는 것끼리, 아니면 하나씩
    /// 3. **묶음마다 이어 붙여 다시 읽기**(`stitch`) — 표 머리줄이 첫 장에만 있어도 둘째 장의 열을 안다
    static func assemble(_ results: [CaptureParser.Result], lines: [[CaptureParser.Line]]?,
                         accounts: [AccountInfo]) -> [Group] {
        let isHead = results.map { $0.accountLine != nil || $0.totalMinor != nil }
        var groups: [(pages: [Int], key: String, loose: Bool)] = []

        // 1) 머리 장 — 같은 계좌면 하나로
        for (index, result) in results.enumerated() where isHead[index] {
            let key = accountKey(result.accountLine)
            if let found = groups.firstIndex(where: { group in
                let total = merged(group.pages.map { results[$0] }).totalMinor
                return (!key.isEmpty && key == group.key)
                    || (key.isEmpty && group.key.isEmpty && result.totalMinor != nil && result.totalMinor == total)
            }) {
                groups[found].pages.append(index)
            } else {
                groups.append((pages: [index], key: key, loose: false))
            }
        }

        // 두 장이 겹치나 — 점수를 매길 때마다 다시 묻게 되므로 한 번 잰 것은 기억한다
        var overlapMemo: [Int: Bool] = [:]
        func overlaps(_ a: Int, _ b: Int) -> Bool {
            guard let lines else { return false }
            let memoKey = min(a, b) * results.count + max(a, b)
            if let known = overlapMemo[memoKey] { return known }
            let found = shift(lines[a], lines[b]) != nil || shift(lines[b], lines[a]) != nil
            overlapMemo[memoKey] = found
            return found
        }

        func score(_ page: Int, _ members: [Int]) -> Int {
            var total = 0
            if members.contains(where: { overlaps($0, page) }) { total += 100 }
            let before = merged(members.map { results[$0] })
            let names = Set(before.items.map { CaptureParser.normalized($0.name) })
            let fresh = results[page].items.filter { !names.contains(CaptureParser.normalized($0.name)) }
            if before.totalMinor != nil, !fresh.isEmpty {
                let after = merged(members.map { results[$0] } + [results[page]])
                if after.isBalanced == true && before.isBalanced != true {
                    total += 50
                } else if before.isBalanced == true {
                    total -= 50
                }
            }
            if !accounts.isEmpty, let account = suggestAccount(for: before, among: accounts),
               let info = accounts.first(where: { $0.id == account }) {
                total += 10 * pair(results[page].items, with: info.holdings).compactMap { $0 }.count
                if let mine = suggestAccount(for: results[page], among: accounts), mine != account { total -= 100 }
            }
            if members.contains(page - 1) { total += 1 }
            return total
        }

        // 2) 머리 없는 장 — 증거 점수로
        var pending = results.indices.filter { !isHead[$0] }
        for strong in [true, false] {
            var changed = true
            while changed {
                changed = false
                for page in pending {
                    let scored = groups.indices.map { (score: score(page, groups[$0].pages), index: $0) }
                    guard let best = scored.map({ $0.score }).max(), best >= (strong ? 50 : 1) else { continue }
                    let ties = scored.filter { $0.score == best }
                    guard ties.count == 1 else { continue }
                    groups[ties[0].index].pages.append(page)
                    pending.removeAll { $0 == page }
                    changed = true
                }
                if !strong { break }
            }
        }
        for page in pending {
            if let found = groups.firstIndex(where: { group in group.loose && group.pages.contains { overlaps($0, page) } }) {
                groups[found].pages.append(page)
            } else {
                groups.append((pages: [page], key: "", loose: true))
            }
        }

        // 3) 묶음마다 이어 붙여 다시 읽기
        var out: [Group] = []
        for group in groups {
            let members = group.pages.sorted()
            if members.count == 1 {
                out.append(Group(pages: members, result: results[members[0]]))
                continue
            }
            guard let lines else {
                out.append(Group(pages: members, result: merged(members.map { results[$0] })))
                continue
            }
            let ordered = arrange(members, lines: lines, isHead: isHead)
            var starts: [Int: Double] = [:]
            for (position, page) in ordered.enumerated()
            where position > 0 && isHead[page] && results[page].accountLine != nil && results[page].totalMinor != nil {
                starts[position] = results[page].bodyTop
            }
            let read = CaptureParser.parse(stitch(ordered.map { lines[$0] }, starts: starts))
            let fallback = merged(ordered.map { results[$0] })
            var stitched = CaptureParser.Result(accountLine: read.accountLine ?? fallback.accountLine,
                                                totalMinor: read.totalMinor ?? fallback.totalMinor,
                                                items: read.items,
                                                cashMinor: read.cashMinor ?? fallback.cashMinor,
                                                feeMinor: read.feeMinor ?? fallback.feeMinor)
            stitched.bodyTop = read.bodyTop
            stitched.dollarAmounts = read.dollarAmounts
            // 이어 읽기가 검산을 못 맞추고 장마다 합친 것은 맞으면 그것을
            let result = fallback.isBalanced == true && stitched.isBalanced != true ? fallback : stitched
            out.append(Group(pages: members, result: result))
        }
        return out.sorted { $0.pages[0] < $1.pages[0] }
    }

    /// 묶음 안의 차례 — 머리 장이 맨 위, 그다음은 **앞 장 아래로 가장 조금 내려가 겹치는** 장을 따라간다
    /// (마지막 장이 끝에 맞춰 찍혀 둘 앞 장과도 겹칠 수 있다). 못 찾으면 고른 차례.
    static func arrange(_ members: [Int], lines: [[CaptureParser.Line]], isHead: [Bool]) -> [Int] {
        var chain = [members.first(where: { isHead[$0] }) ?? members[0]]
        var rest = members.filter { $0 != chain[0] }
        while !rest.isEmpty, let last = chain.last {
            let follows = rest.compactMap { page in shift(lines[last], lines[page]).map { (d: $0, page: page) } }
            let next = follows.min { $0.d < $1.d }?.page ?? rest[0]
            chain.append(next)
            rest.removeAll { $0 == next }
        }
        return chain
    }

    // MARK: - 이어 붙이기 (226번)

    /// 같은 줄로 볼 가로 어긋남 · 장마다 같은 자리로 볼 세로 어긋남 · 겹침 간격 묶음 폭 ·
    /// 앞 장 아래 끝에서 경계에 걸려 못 읽은 줄이 있을 수 있는 띠.
    static let sameX = 0.01, sameY = 0.006, shiftBand = 0.004, edge = 0.06

    static func key(_ text: String) -> String { text.filter { !$0.isWhitespace } }

    /// 두 장에서 **같은 자리에 같은 글자** — 상태 막대 · 탭 막대 · 붙어 다니는 머리.
    static func repeated(_ a: [CaptureParser.Line], _ b: [CaptureParser.Line]) -> (Set<Int>, Set<Int>) {
        var inA = Set<Int>(), inB = Set<Int>()
        let keysA = a.map { key($0.text) }, keysB = b.map { key($0.text) }   // 다듬기는 줄마다 한 번만
        for (i, x) in a.enumerated() {
            for (j, y) in b.enumerated()
            where keysA[i] == keysB[j] && abs(x.x - y.x) < sameX && abs(x.top - y.top) < sameY {
                inA.insert(i)
                inB.insert(j)
            }
        }
        return (inA, inB)
    }

    static func shift(_ a: [CaptureParser.Line], _ b: [CaptureParser.Line]) -> Double? {
        let (inA, inB) = repeated(a, b)
        return shift(a, b, inA, inB)
    }

    /// b 가 a 의 아래로 이어진 장이면 b 의 줄을 a 좌표로 옮길 세로 간격(> 0), 아니면 nil.
    ///
    /// a 의 아래쪽과 b 의 위쪽에 **같은 글자 · 같은 가로 자리 · 같은 글씨 크기**의 줄이 있으면 그 간격들이 한 값으로 모인다.
    /// 되풀이되는 이름표(`평가금액`)는 여러 간격에 흩어지므로 **서로 다른 글자 수**로 센다 — 둘 이상이거나,
    /// 두 장에서 한 번씩만 나오는 세 글자 이상의 줄 하나면 후보. 그리고 **겹친 띠 전체가 맞아야** 겹침이다 —
    /// 다른 계좌에 같은 ETF 가 있으면 그 이름 한 줄은 맞는다. 띠 안 줄의 절반 넘게 b 에 같은 자리 · 같은 글자로 있어야 한다.
    static func shift(_ a: [CaptureParser.Line], _ b: [CaptureParser.Line], _ inA: Set<Int>, _ inB: Set<Int>) -> Double? {
        let keysA = a.map { key($0.text) }, keysB = b.map { key($0.text) }   // 다듬기는 줄마다 한 번만
        var countA: [String: Int] = [:], countB: [String: Int] = [:]
        for text in keysA { countA[text, default: 0] += 1 }
        for text in keysB { countB[text, default: 0] += 1 }
        var votes: [(d: Double, key: String)] = []
        for (i, x) in a.enumerated() where !inA.contains(i) {
            let text = keysA[i]
            guard text.count >= 2 else { continue }
            for (j, y) in b.enumerated() where !inB.contains(j) && keysB[j] == text {
                guard abs(x.x - y.x) < sameX, abs(x.height - y.height) < sameY else { continue }
                let d = x.top - y.top
                if d > 0.02 { votes.append((d, text)) }
            }
        }
        var best: Double?
        var bestScore = 0
        for vote in votes {
            let near = Set(votes.filter { abs($0.d - vote.d) < shiftBand }.map { $0.key })
            let unique = near.contains { countA[$0] == 1 && countB[$0] == 1 && $0.count >= 3 }
            let score = near.count >= 2 ? near.count : (unique ? 1 : 0)
            if score > bestScore || (score == bestScore && score > 0 && best.map { vote.d < $0 } == true) {
                best = vote.d
                bestScore = score
            }
        }
        guard let center = best, bestScore > 0 else { return nil }
        // 모인 간격들의 가운데 값
        let near = votes.map { $0.d }.filter { abs($0 - center) < shiftBand }.sorted()
        let d = near[near.count / 2]
        let bTop = (b.indices.filter { !inB.contains($0) }.map { b[$0].top }.min() ?? 0) + d
        let aEnd = inA.filter { a[$0].top > 0.5 }.map { a[$0].top }.min() ?? 1
        let band = a.indices
            .filter { !inA.contains($0) && a[$0].top >= bTop - 1e-9 && a[$0].bottom <= aEnd + 1e-9 }
            .map { a[$0] }
        guard !band.isEmpty else { return nil }
        let hits = band.filter { x in
            let text = key(x.text)
            return b.indices.contains { j in
                keysB[j] == text && abs(b[j].x - x.x) < sameX && abs(b[j].top + d - x.top) < shiftBand
            }
        }.count
        return hits * 2 > band.count ? d : nil
    }

    /// 같은 줄(세로 가운데가 가깝고) 가로로 겹치는 줄이 있나 — 앞 장이 이미 읽은 자리.
    static func covered(_ line: CaptureParser.Line, _ others: [CaptureParser.Line]) -> Bool {
        others.contains { other in
            abs(other.centerY - line.centerY) < max(other.height, line.height) * 0.6
                && other.x < line.x + line.width && line.x < other.x + other.width
        }
    }

    static func moved(_ line: CaptureParser.Line, by offset: Double) -> CaptureParser.Line {
        CaptureParser.Line(text: line.text, x: line.x, top: line.top + offset, width: line.width, height: line.height)
    }

    /// **묶음 안의 장들(위에서 아래 차례)을 한 좌표계의 줄 목록으로** — 둘째 장부터:
    /// - 앞 장과 같은 자리의 줄(되풀이)은 버린다. 머리가 있던 장이면 그 머리(`starts` = 본문 시작)도 버린다
    /// - 겹치면 그 간격으로 옮기고, 앞 장이 이미 보인 자리는 버린다 — 다만 앞 장 아래 끝 띠에서 앞 장에 없던 줄
    ///   (경계에 걸려 못 읽은 줄)은 남긴다
    /// - 안 겹치면 앞 장의 내용 바로 아래에 잇는다
    /// - 앞 장 아래쪽의 되풀이 줄(탭 막대)은 이어진 문서 한가운데 남지 않게 뺀다
    static func stitch(_ pages: [[CaptureParser.Line]], starts: [Int: Double] = [:]) -> [CaptureParser.Line] {
        guard var previous = pages.first else { return [] }
        var out = previous
        var previousOffset = 0.0
        var previousSlots = Array(out.indices)   // out 안에서 앞 장 줄의 자리
        for (position, page) in pages.enumerated().dropFirst() {
            let (inA, inB) = repeated(previous, page)
            let bottomChrome = inA.filter { previous[$0].top > 0.5 }.map { previous[$0].top }.min() ?? 1
            var topChrome = inB.filter { page[$0].top < 0.5 }.map { page[$0].bottom }.max() ?? 0
            if let head = starts[position] { topChrome = max(topChrome, head) }
            let drop = Set(inA.filter { previous[$0].top > 0.5 }.map { previousSlots[$0] })
            let offset: Double
            let keep: [Int]
            if let d = shift(previous, page, inA, inB) {
                offset = previousOffset + d
                let cutoff = previousOffset + bottomChrome
                let seen = previous.indices.filter { !inA.contains($0) }.map { moved(previous[$0], by: previousOffset) }
                keep = page.indices.filter { j in
                    guard !inB.contains(j), page[j].top > topChrome - 1e-9 else { return false }
                    let line = moved(page[j], by: offset)
                    if line.top >= cutoff - 1e-9 { return true }
                    return line.top >= cutoff - edge && !covered(line, seen)
                }
            } else {
                offset = previousOffset + bottomChrome - topChrome
                keep = page.indices.filter { !inB.contains($0) && page[$0].top >= topChrome - 1e-9 }
            }
            out = out.indices.filter { !drop.contains($0) }.map { out[$0] }
            var slots = Array(repeating: -1, count: page.count)
            for j in keep {
                slots[j] = out.count
                out.append(moved(page[j], by: offset))
            }
            previousSlots = slots
            previous = page
            previousOffset = offset
        }
        return out
    }

    // MARK: - 검산 차이를 말로 (226번)

    /// 검산이 안 맞을 때 무엇일 법한가.
    public enum Gap: Sendable, Hashable {
        /// 금액을 못 고른 종목 수.
        case unread(Int)
        /// 총액보다 모자란 금액 — 아래로 넘긴 장이 빠졌을 수 있다.
        case missing(Int)
        /// 총액보다 많은 금액 — 같은 종목이 두 번 들어갔거나 다른 계좌 장이 섞였을 수 있다.
        case extra(Int)
        /// 여러 장 사이에 시세가 움직였을 만한 작은 차이(총액의 0.3% 안).
        case drift(Int)
        /// 총액이 합보다 작고 0.7% 안 — 팔 때 수수료 · 세금을 뺀 총액으로 보인다(227번).
        case fees(Int)
        /// 총액이 합보다 크고 10만 원 안 — 종목이 아닌 소액 예치금으로 보인다(227번).
        case deposit(Int)

        /// **그럴듯한 작은 차이** — 앱은 그 계좌의 종목이 캡처에 모두 있을 때만 이것을 근사 통과로 채운다.
        public var isExplainable: Bool {
            switch self {
            case .fees, .deposit: return true
            case .unread, .missing, .extra, .drift: return false
            }
        }
    }

    /// 수수료 · 세금으로 볼 비율 — 국내 매도세 약 0.2%(2026) · 해외 위탁 0.25~0.5% 를 넉넉히 덮는다(227번).
    public static let feeRate = 0.007
    /// 소액 예치금으로 볼 상한(원) — 11-23 사용자: *"소액 예치금 상한은 10만 원으로"*.
    public static let depositCap = 100_000

    /// 검산이 맞거나 총액이 없으면 nil.
    public static func gap(in result: CaptureParser.Result, pages: Int) -> Gap? {
        guard let total = result.totalMinor else { return nil }
        let unread = result.items.filter { $0.valueMinor == nil }.count
        if unread > 0 { return .unread(unread) }
        let expected = result.expectedSumMinor
        let difference = total - expected
        if abs(difference) <= result.items.count { return nil }
        // 화면에 적힌 현금 · 비용으로도 안 맞을 때 — 그럴듯한 작은 차이부터
        if difference < 0, Double(-difference) <= Double(expected) * feeRate { return .fees(-difference) }
        if difference > 0, difference <= depositCap { return .deposit(difference) }
        if pages > 1, Double(abs(difference)) <= Double(total) * 0.003 { return .drift(abs(difference)) }
        return difference > 0 ? .missing(difference) : .extra(-difference)
    }

    /// 여러 장을 한 결과로 — 계좌 줄 · 총액 · 현금은 처음 나온 것, 종목은 이름이 같으면 하나만(겹쳐 찍힌 줄) —
    /// 먼저 것이 금액을 못 골랐으면 금액이 있는 뒤의 것으로(장 경계에서 잘린 줄, 226번).
    static func merged(_ results: [CaptureParser.Result]) -> CaptureParser.Result {
        var seen: [String: Int] = [:]
        var items: [CaptureParser.Item] = []
        for item in results.flatMap(\.items) {
            let name = CaptureParser.normalized(item.name)
            if let index = seen[name] {
                if items[index].valueMinor == nil, item.valueMinor != nil { items[index] = item }
                continue
            }
            seen[name] = items.count
            items.append(item)
        }
        var result = CaptureParser.Result(accountLine: results.lazy.compactMap(\.accountLine).first,
                                          totalMinor: results.lazy.compactMap(\.totalMinor).first,
                                          items: items,
                                          cashMinor: results.lazy.compactMap(\.cashMinor).first,
                                          feeMinor: results.lazy.compactMap(\.feeMinor).first)
        result.dollarAmounts = results.reduce(0) { $0 + $1.dollarAmounts }
        return result
    }
}
