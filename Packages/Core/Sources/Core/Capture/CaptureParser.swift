import Foundation

/// **증권사 보유 화면 캡처에서 종목 · 평가금액을 고른다** (docs/25 J3, 11-20 사용자: *"착수하자. 시험 화면 만들어줘"*).
///
/// 글자 인식(Vision)은 앱 쪽 일이고, 여기는 **읽은 글자 줄에서 무엇이 무엇인지** 만 정한다 — 그래서
/// 리눅스에서도 시험된다. 화면 배치를 미리 알지 않는다(증권사마다 다르다):
/// 1. 맨 위에서 가장 큰 글씨의 금액 = 계좌 총액
/// 2. 숫자가 아닌 왼쪽 줄 = 종목 이름 (두 줄로 꺾인 이름은 붙인다)
/// 3. 이름 아래 · 다음 이름 전에서 평가금액 — `평가금액` 이름표가 있으면 그 줄, 없으면 가장 큰 글씨
///    (같으면 큰 값). 부호(+ −)가 붙은 손익 · % · 주 · 매입 · 원금 · 현재가 는 뺀다
/// 4. **검산** — 읽은 금액의 합 = 계좌 총액. 맞지 않으면 그 장은 사람이 봐야 한다
///
/// 규칙은 `Tools/ocr-sim/score.py` 와 같다 — 가상 캡처 9장으로 다듬었다.
public enum CaptureParser {

    /// 글자 한 줄. 좌표는 그림 크기에 대한 비율(0~1), **위에서부터**.
    public struct Line: Sendable, Hashable {
        public let text: String
        public let x: Double
        public let top: Double
        public let width: Double
        public let height: Double

        public init(text: String, x: Double, top: Double, width: Double, height: Double) {
            self.text = text
            self.x = x
            self.top = top
            self.width = width
            self.height = height
        }
    }

    public struct Item: Sendable, Hashable {
        public let name: String
        /// 평가금액(원). 못 고르면 nil.
        public let valueMinor: Int?
    }

    public struct Result: Sendable, Hashable {
        /// 계좌를 알아볼 줄(종류 · 끝자리) — 있으면.
        public let accountLine: String?
        public let totalMinor: Int?
        public let items: [Item]

        public var sumMinor: Int { items.reduce(0) { $0 + ($1.valueMinor ?? 0) } }
        /// 총액이 없으면 nil — 검산할 수 없다.
        public var isBalanced: Bool? {
            guard let totalMinor else { return nil }
            return totalMinor == sumMinor && items.allSatisfy { $0.valueMinor != nil }
        }
    }

    static let labels: Set<String> = ["평가금액", "평가액", "매입금액", "수익률", "투자원금", "종목명", "잔고", "체결",
                                      "손익", "보유", "주문", "현재가", "평균단가", "수량"]
    /// 이 말 바로 뒤의 숫자는 평가금액이 아니다.
    static let notValuePrefixes = ["매입", "원금", "손익", "평균", "단가", "현재가", "매수", "평단"]

    /// 그 줄에서 평가금액 후보가 될 금액(원).
    public static func amounts(in text: String) -> [Int] {
        // 정규식은 그 자리에서 만든다 — 정적 값으로 두면 `NSRegularExpression` 이 Sendable 이 아니라 Swift 6 이 막는다.
        guard let number = try? NSRegularExpression(pattern: #"[+\-−]?\d{1,3}(?:,\d{3})+(?:원)?"#) else { return [] }
        let ns = text as NSString
        var out: [Int] = []
        for match in number.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            if let first = token.first, "+-−".contains(first) { continue }
            let afterStart = match.range.location + match.range.length
            let after = ns.substring(with: NSRange(location: afterStart, length: min(2, ns.length - afterStart)))
            if after.hasPrefix("주") || after.hasPrefix("%") || after.hasPrefix("(") { continue }
            let beforeStart = max(0, match.range.location - 6)
            let before = ns.substring(with: NSRange(location: beforeStart, length: match.range.location - beforeStart))
            if notValuePrefixes.contains(where: { before.contains($0) }) { continue }
            let digits = token.filter(\.isNumber)
            if let value = Int(digits) { out.append(value) }
        }
        return out
    }

    static func isName(_ line: Line) -> Bool {
        let text = line.text.trimmingCharacters(in: .whitespaces)
        guard line.x < 0.5, !labels.contains(text) else { return false }
        guard text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return false }
        // 숫자 묶음(1,234)이 든 줄은 이름이 아니다 — 매입 … · 투자원금 … · 수량 줄
        if text.range(of: #"\d,\d{3}"#, options: .regularExpression) != nil { return false }
        if text.contains("****") || text.hasPrefix("총 ") || text.contains("평가손익") { return false }
        return true
    }

    public static func parse(_ lines: [Line]) -> Result {
        let rows = lines.sorted { ($0.top, $0.x) < ($1.top, $1.x) }
        // 1) 계좌 총액 — 위쪽 30% 안에서 가장 큰 글씨의 금액
        let head = rows.filter { $0.top < 0.30 && !amounts(in: $0.text).isEmpty }
        let totalLine = head.max { $0.height < $1.height }
        let total = totalLine.flatMap { amounts(in: $0.text).first }
        let accountLine = rows.first { $0.top < (totalLine?.top ?? 0.3) && $0.text.contains("*") }?.text
            ?? totalLine.flatMap { t in rows.last { $0.top < t.top && isName($0) } }?.text
        let bodyStart = totalLine.map { $0.top + $0.height } ?? -1
        let body = rows.filter { $0.top > bodyStart }

        // 2) 이름 — 두 줄로 꺾인 것은 붙인다(바로 아래 · 같은 왼쪽 · 숫자 없음)
        var names: [Line] = []
        for line in body where isName(line) {
            if let previous = names.last,
               abs(line.x - previous.x) < 0.02,
               line.top - (previous.top + previous.height) > 0,
               line.top - (previous.top + previous.height) < previous.height * 0.9 {
                names[names.count - 1] = Line(text: previous.text + " " + line.text, x: previous.x, top: previous.top,
                                              width: max(previous.width, line.width),
                                              height: line.top + line.height - previous.top)
                continue
            }
            names.append(line)
        }

        // 3) 이름마다 평가금액
        var items: [Item] = []
        for (index, name) in names.enumerated() {
            let low = name.top - name.height * 0.6
            let high = index + 1 < names.count ? names[index + 1].top - names[index + 1].height * 0.6 : 1.0
            let band = body.filter { $0.top >= low && $0.top < high && $0 != name }
            var candidates: [(line: Line, value: Int)] = band.flatMap { line in
                line.x > 0.25 ? amounts(in: line.text).map { (line, $0) } : []
            }
            if let label = band.first(where: { ["평가금액", "평가액"].contains($0.text.trimmingCharacters(in: .whitespaces)) }) {
                let center = label.top + label.height / 2
                candidates.sort { abs($0.line.top + $0.line.height / 2 - center) < abs($1.line.top + $1.line.height / 2 - center) }
            } else {
                candidates.sort { ($0.line.height, $0.value) > ($1.line.height, $1.value) }
            }
            items.append(Item(name: name.text, valueMinor: candidates.first?.value))
        }
        return Result(accountLine: accountLine, totalMinor: total, items: items)
    }

    // MARK: - 이름 맞추기

    /// 비교용으로 다듬는다 — 빈칸 · 말줄임 · 괄호 앞뒤 공백을 걷는다.
    static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "...", with: "…")
            .replacingOccurrences(of: "…", with: "")
            .filter { !$0.isWhitespace }
            .lowercased()
    }

    /// 0~1. 편집 거리 기준.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a), y = Array(b)
        if x.isEmpty && y.isEmpty { return 1 }
        if x.isEmpty || y.isEmpty { return 0 }
        var previous = Array(0...y.count)
        for i in 1...x.count {
            var current = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[y.count]) / Double(max(x.count, y.count))
    }

    /// 읽은 이름을 앱 종목 이름 가운데 하나와 짝짓는다. **잘린 이름(…)은 앞부분이 맞는 하나**,
    /// 아니면 가장 비슷한 것. 0.6 아래면 짝이 없다고 본다.
    public static func match(_ read: String, among candidates: [String]) -> (index: Int, score: Double)? {
        let clean = normalized(read)
        guard !clean.isEmpty else { return nil }
        let prefixLength = max(4, clean.count - 1)
        let prefix = String(clean.prefix(prefixLength))
        let prefixed = candidates.indices.filter { normalized(candidates[$0]).hasPrefix(prefix) }
        if prefixed.count == 1 { return (index: prefixed[0], score: 1) }
        let scored = candidates.indices.map { (index: $0, score: similarity(clean, normalized(candidates[$0]))) }
        guard let best = scored.max(by: { $0.score < $1.score }), best.score >= 0.6 else { return nil }
        return best
    }
}
