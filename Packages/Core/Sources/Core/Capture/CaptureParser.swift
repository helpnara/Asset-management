import Foundation

/// **증권사 보유 화면 캡처에서 종목 · 평가금액을 고른다** (docs/25 J3, 11-20 사용자: *"착수하자. 시험 화면 만들어줘"*).
///
/// 글자 인식(Vision)은 앱 쪽 일이고, 여기는 **읽은 글자 줄에서 무엇이 무엇인지** 만 정한다 — 그래서
/// 리눅스에서도 시험된다. 화면 배치를 미리 알지 않는다(증권사마다 다르다):
/// 0. **표 머리줄** — `평가금액` 과 같은 줄이 모두 이름표(셋 이상)면 표다. 그 열(위아래로 쌓인 칸이면 몇째 단인지)을 기억한다
/// 1. 계좌 총액 — 표면 머리줄 위 `평가금액` 이름표 오른쪽 금액, 아니면 맨 위에서 가장 큰 글씨의 금액
/// 2. 숫자가 아닌 왼쪽 줄 = 종목 이름 (두 줄로 꺾인 이름은 붙이고, 같은 줄에 겹친 아이콘 글자는 버린다)
/// 3. 이름 아래 · 다음 이름 전에서 평가금액 — 표면 그 열, 아니면 `평가금액` 이름표 줄, 없으면 가장 큰 글씨
///    (같으면 큰 값). 부호(+ −)가 붙은 손익 · % · 주 · 소수 · 매입 · 원금 · 현재가 · 담보 는 뺀다.
///    **금액이 하나도 없는 이름은 종목이 아니다** (메뉴 · 탭 · 묶음 머리)
/// 4. **검산** — 읽은 금액의 합 = 계좌 총액(해외 종목 환산 반올림만큼 종목 수 × 1원 봐줌). 맞지 않으면 사람이 본다
///
/// 규칙은 `Tools/ocr-sim/parser.py` 와 줄 단위로 같다 — 가상 캡처 15장(실제 화면 두 배치를 본뜬 6장 포함)으로 다듬었다.
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

        var bottom: Double { top + height }
        var centerX: Double { x + width / 2 }
        var centerY: Double { top + height / 2 }
    }

    public struct Item: Sendable, Hashable {
        public let name: String
        /// 평가금액(원). 못 고르면 nil.
        public let valueMinor: Int?
    }

    public struct Result: Sendable, Hashable {
        /// 계좌를 알아볼 줄(종류 · 번호 · 이름) — 있으면.
        public let accountLine: String?
        public let totalMinor: Int?
        public let items: [Item]

        public var sumMinor: Int { items.reduce(0) { $0 + ($1.valueMinor ?? 0) } }
        /// 총액이 없으면 nil — 검산할 수 없다. 해외 종목은 원화 환산 반올림으로 몇 원 다를 수 있어 종목 수만큼(원) 봐준다.
        public var isBalanced: Bool? {
            guard let totalMinor else { return nil }
            guard !items.isEmpty, items.allSatisfy({ $0.valueMinor != nil }) else { return false }
            return abs(totalMinor - sumMinor) <= items.count
        }
    }

    static let labels: Set<String> = ["평가금액", "평가액", "평가금", "매입금액", "매입가", "매입단가", "수익률", "손익률", "투자원금",
                                      "종목명", "잔고", "체결", "손익", "평가손익", "보유", "보유수량", "주문", "주문가능", "현재가",
                                      "평균단가", "평단가", "수량", "매도가능"]
    static let valueLabels: Set<String> = ["평가금액", "평가액", "평가금"]
    static let totalLabels: Set<String> = ["평가금액", "평가액", "평가금", "총평가금액", "총평가액", "총평가", "평가금액합계", "평가합계"]
    /// 이 말 바로 뒤의 숫자는 평가금액이 아니다.
    static let notValuePrefixes = ["매입", "원금", "손익", "평균", "단가", "현재가", "매수", "평단", "담보", "환율", "예수금"]

    /// 이름표 비교용 — `수익률(%)` · `평가금액(원)` · 빈칸을 걷는다.
    static func label(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "(%)", with: "")
            .replacingOccurrences(of: "(원)", with: "")
            .replacingOccurrences(of: "%", with: "")
        out.removeAll { $0.isWhitespace }
        return out
    }

    static func sameRow(_ a: Line, _ b: Line) -> Bool {
        abs(a.centerY - b.centerY) < max(a.height, b.height) * 0.6
    }

    /// 그 줄에서 평가금액 후보가 될 금액(원)과 글자 자리.
    static func amountSpans(in text: String) -> [(value: Int, range: NSRange)] {
        // 정규식은 그 자리에서 만든다 — 정적 값으로 두면 `NSRegularExpression` 이 Sendable 이 아니라 Swift 6 이 막는다.
        guard let number = try? NSRegularExpression(pattern: #"[+\-−]?\d{1,3}(?:,\d{3})+(?:원)?"#) else { return [] }
        let ns = text as NSString
        var out: [(value: Int, range: NSRange)] = []
        for match in number.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            if let first = token.first, "+-−".contains(first) { continue }
            let afterStart = NSMaxRange(match.range)
            let after = ns.substring(with: NSRange(location: afterStart, length: min(2, ns.length - afterStart)))
            if after.hasPrefix("주") || after.hasPrefix("%") || after.hasPrefix("(") { continue }
            if after.range(of: #"^\.\d"#, options: .regularExpression) != nil { continue }   // 소수 — 환율 1,352.70
            let beforeStart = max(0, match.range.location - 6)
            let before = ns.substring(with: NSRange(location: beforeStart, length: match.range.location - beforeStart))
            if notValuePrefixes.contains(where: { before.contains($0) }) { continue }
            if let value = Int(token.filter(\.isNumber)) { out.append((value, match.range)) }
        }
        return out
    }

    /// 그 줄에서 평가금액 후보가 될 금액(원).
    public static func amounts(in text: String) -> [Int] {
        amountSpans(in: text).map(\.value)
    }

    /// 줄을 빈칸으로 나눈 낱말 — 자리는 글자 수 비율로 어림한다(텍스트 인식이 표의 칸을 붙여 읽을 때).
    static func words(_ line: Line) -> [Line] {
        guard let word = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
        let ns = line.text as NSString
        let count = Double(max(1, ns.length))
        return word.matches(in: line.text, range: NSRange(location: 0, length: ns.length)).map { match in
            Line(text: ns.substring(with: match.range),
                 x: line.x + line.width * Double(match.range.location) / count, top: line.top,
                 width: line.width * Double(match.range.length) / count, height: line.height)
        }
    }

    /// 금액과 그 자리(낱말 크기의 상자).
    struct Placed {
        let value: Int
        let box: Line
    }

    static func placed(_ line: Line) -> [Placed] {
        let count = Double(max(1, (line.text as NSString).length))
        return amountSpans(in: line.text).map { span in
            Placed(value: span.value,
                   box: Line(text: "", x: line.x + line.width * Double(span.range.location) / count, top: line.top,
                             width: line.width * Double(span.range.length) / count, height: line.height))
        }
    }

    static func isName(_ line: Line) -> Bool {
        let text = line.text.trimmingCharacters(in: .whitespaces)
        guard line.x < 0.5, !labels.contains(label(text)) else { return false }
        guard text.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return false }
        // 숫자 묶음(1,234)이 든 줄은 이름이 아니다 — 매입 … · 투자원금 … · 수량 줄
        if text.range(of: #"\d,\d{3}"#, options: .regularExpression) != nil { return false }
        if text.contains("****") || text.hasPrefix("총 ") || text.contains("평가손익") { return false }
        if text.range(of: #"\d{2,}-\d{2,}"#, options: .regularExpression) != nil { return false }   // 계좌 번호 줄
        // 숫자에 단위만 붙은 줄 — 0.123456주 · 652원
        if text.contains(where: \.isNumber),
           text.allSatisfy({ $0.isNumber || $0.isWhitespace || ".,+-−%()$주원좌개".contains($0) }) { return false }
        // 숫자 + 글자 한 자 — 단위를 잘못 읽어도(3.123456수) 이름이 아니다. 소수거나 세 자리 이상일 때만(3M 같은 이름은 남긴다)
        if text.range(of: #"^[+\-−]?\d[\d,.]*\s*[^\d\s]?$"#, options: .regularExpression) != nil,
           text.contains(".") || text.filter(\.isNumber).count >= 3 { return false }
        return true
    }

    /// 표의 평가금액 열.
    struct Column {
        /// 머리줄의 이름표 낱말들 — 금액이 어느 열인지 가장 가까운 이름표로 정한다.
        let block: [Line]
        let x: Double
        let tolerance: Double
        /// 한 칸에 위아래로 쌓인 이름표 가운데 `평가금액` 이 몇째 단인가(0 부터).
        let rank: Int
        /// 머리줄 아래 끝 — 여기부터 종목.
        let start: Double
        /// 머리줄 위 끝 — 계좌 총액은 이보다 위에서 찾는다.
        let top: Double

        func contains(_ box: Line) -> Bool {
            guard let nearest = block.min(by: { abs($0.centerX - box.centerX) < abs($1.centerX - box.centerX) }) else { return false }
            return abs(nearest.centerX - x) < tolerance
        }
    }

    public static func parse(_ lines: [Line]) -> Result {
        let rows = lines.sorted { ($0.top, $0.x) < ($1.top, $1.x) }
        let tokens = rows.flatMap(words).sorted { ($0.top, $0.x) < ($1.top, $1.x) }
        let amountsPlaced = rows.flatMap(placed)

        // 0) 표 머리줄 — `평가금액` 과 같은 줄이 모두 이름표(셋 이상)
        func labelRow(_ token: Line) -> Bool {
            tokens.filter { sameRow($0, token) }.allSatisfy { labels.contains(label($0.text)) }
        }
        var column: Column?
        if let header = tokens.first(where: { token in
            valueLabels.contains(label(token.text)) && tokens.filter { sameRow($0, token) }.count >= 3 && labelRow(token)
        }) {
            let block = tokens.filter {
                $0.top >= header.top - header.height * 0.5 && $0.top <= header.top + header.height * 3
                    && labels.contains(label($0.text)) && labelRow($0)
            }
            let tolerance = max(header.width * 0.5, 0.03)
            let stacked = block.filter { abs($0.centerX - header.centerX) < tolerance }
            column = Column(block: block, x: header.centerX, tolerance: tolerance,
                            rank: stacked.filter { $0.top < header.top - header.height * 0.3 }.count,
                            start: block.map(\.bottom).max() ?? header.bottom,
                            top: header.top - header.height * 0.5)
        }

        // 1) 계좌 총액 — 표가 있으면 머리줄 위 `평가금액` 같은 이름표 오른쪽의 금액, 없으면 위쪽 30% 의 가장 큰 글씨
        var total: Int?
        var totalLine: Line?
        if let column {
            for token in tokens where token.top < column.top && totalLabels.contains(label(token.text)) {
                let right = amountsPlaced.filter { sameRow($0.box, token) && $0.box.x >= token.x + token.width - 0.01 }
                if let nearest = right.min(by: { $0.box.x < $1.box.x }) {
                    total = nearest.value
                    break
                }
            }
        }
        if total == nil {
            let limit = min(0.30, column?.top ?? 0.30)
            if let line = rows.filter({ $0.top < limit && !amounts(in: $0.text).isEmpty }).max(by: { $0.height < $1.height }) {
                totalLine = line
                total = amounts(in: line.text).first
            }
        }
        let start = column?.start ?? totalLine?.bottom ?? -1
        let edge = column?.top ?? totalLine?.top ?? 0.30
        var accountLine = rows.first {
            $0.top < edge && ($0.text.contains("*") || $0.text.range(of: #"\d{2,}-\d{2,}"#, options: .regularExpression) != nil)
        }?.text
        if accountLine == nil, let totalLine {
            accountLine = rows.last { $0.top < totalLine.top && isName($0) }?.text
        }
        let body = rows.filter { $0.top > start }

        // 2) 이름 — 두 줄로 꺾인 것은 붙이고(바로 아래 · 같은 왼쪽), 같은 줄에 겹친 것(아이콘 안 글자)은 큰 글씨 하나만
        var names: [Line] = []
        for line in body where isName(line) {
            if let previous = names.last {
                let gap = line.top - previous.bottom
                if abs(line.x - previous.x) < 0.02, gap > 0, gap < previous.height * 0.9 {
                    names[names.count - 1] = Line(text: previous.text + " " + line.text, x: previous.x, top: previous.top,
                                                  width: max(previous.width, line.width),
                                                  height: line.bottom - previous.top)
                    continue
                }
                if sameRow(line, previous) {
                    if line.height > previous.height { names[names.count - 1] = line }
                    continue
                }
            }
            names.append(line)
        }

        // 3) 이름마다 평가금액. 금액이 하나도 없는 이름(메뉴 · 탭 · 묶음 머리)은 종목이 아니다
        var items: [Item] = []
        for (index, name) in names.enumerated() {
            let low = name.top - name.height * 0.6
            let high = index + 1 < names.count ? names[index + 1].top - names[index + 1].height * 0.6 : 1.0
            if let column {
                let candidates = amountsPlaced
                    .filter { $0.box.top >= low && $0.box.top < high && column.contains($0.box) }
                    .sorted { $0.box.top < $1.box.top }
                guard !candidates.isEmpty else { continue }
                items.append(Item(name: name.text,
                                  valueMinor: candidates.count > column.rank ? candidates[column.rank].value : nil))
            } else {
                let band = body.filter { $0.top >= low && $0.top < high && $0 != name }
                var candidates: [(line: Line, value: Int)] = band.flatMap { line in
                    line.x > 0.25 ? amounts(in: line.text).map { (line, $0) } : []
                }
                guard !candidates.isEmpty else { continue }
                if let mark = band.first(where: { valueLabels.contains(label($0.text)) }) {
                    candidates.sort { abs($0.line.centerY - mark.centerY) < abs($1.line.centerY - mark.centerY) }
                } else {
                    candidates.sort { ($0.line.height, $0.value) > ($1.line.height, $1.value) }
                }
                items.append(Item(name: name.text, valueMinor: candidates.first?.value))
            }
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
