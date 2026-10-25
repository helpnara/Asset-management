import Foundation

/// **그림 위 글씨 자리 정하기** (209번, 10-25 사용자: *"차트에 내용을 추가하면서 글자 겹침 여부를 체크하는
/// 로직을 만들던가 해서 … 로직을 지능화해서 더 보기 좋은 차트가 나올 수 있게 고민해줘"*).
///
/// 예전에는 글씨마다 제 표시(점 · 선) 옆에 **바로** 붙였다. 글씨끼리 서로를 모르니 가까운 인생 이벤트
/// 셋이 바닥 한 자리에 포개졌고, 목표 글씨는 오늘 세로선에 꿰였다. 글씨가 많아서가 아니라 놓을 때
/// 둘러보지 않아서였다. 이제는 **중요한 것부터 하나씩** 놓는다.
///
/// 1. 글씨마다 놓을 수 있는 자리 후보를 낸다 — 점은 위 · 비스듬히 위 · 옆 · 아래, 가로선은 선을 따라
///    여러 곳의 위아래, 인생 이벤트는 제 세로선 옆 바닥부터 한 줄씩 위로.
/// 2. **이미 놓인 글씨와 겹치는 후보는 버린다.** 겹침은 비용이 아니라 금지다.
/// 3. 남은 후보 중 그림(선 · 점)을 가장 덜 가리고 원래 자리에서 덜 벗어난 곳을 고른다.
/// 4. 놓을 곳이 하나도 없으면 그 글씨는 뺀다. 표시 자체(점선 · 점)는 남고, 순서가 중요도라 빠지는
///    것은 늘 덜 중요한 쪽이다.
///
/// 글씨 크기는 화면이 **실제로 잰 값**을 받는다 — 글자 수로 어림하지 않으니 큰 글씨 설정에서도 맞다.
/// 화면을 모르는 셈이라 `Core` 에 두고 시험한다(ADR-0002). 좌표는 화면 포인트, 왼쪽 위가 원점이다.
public enum LabelPlacement {

    /// 화면 위 네모.
    public struct Box: Hashable, Sendable {
        public var minX: Double
        public var minY: Double
        public var width: Double
        public var height: Double

        public init(minX: Double, minY: Double, width: Double, height: Double) {
            self.minX = minX
            self.minY = minY
            self.width = width
            self.height = height
        }

        public var maxX: Double { minX + width }
        public var maxY: Double { minY + height }

        /// 둘 사이를 `gap` 만큼 띄워도 닿는가.
        public func overlaps(_ other: Box, gap: Double = 0) -> Bool {
            minX < other.maxX + gap && other.minX < maxX + gap
                && minY < other.maxY + gap && other.minY < maxY + gap
        }

        public func contains(x: Double, y: Double) -> Bool {
            x >= minX && x <= maxX && y >= minY && y <= maxY
        }
    }

    /// 그림이 차지한 한 점 — 선을 몇 포인트마다 끊어 찍은 것. 글씨가 덮으면 `weight` 만큼 손해다.
    /// 실제 기록 선처럼 가리면 안 되는 것은 무겁게, 눈금 같은 점선은 가볍게 준다.
    public struct Ink: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var weight: Double

        public init(x: Double, y: Double, weight: Double) {
            self.x = x
            self.y = y
            self.weight = weight
        }
    }

    /// 글씨를 붙일 곳.
    public enum Anchor: Hashable, Sendable {
        /// 점 하나(마지막 기록 · 은퇴 · 목표 ◆ …) — 바로 위가 먼저, 다음 비스듬히 위 · 옆 · 아래, 끝으로 한 칸 더 위.
        case point(x: Double, y: Double)
        /// 가로선(목표) — 선을 따라 왼쪽부터 다섯 곳, 위가 먼저.
        case horizontal(y: Double)
        /// 세로선의 바닥(인생 이벤트) — 선 오른쪽이 먼저, 막히면 한 줄씩 위로 `lanes` 줄까지 쌓는다.
        case verticalBottom(x: Double, lanes: Int)
        /// 세로선의 위쪽(은퇴 · 고갈) — 위 · 3분의 1 · 3분의 2 높이, 오른쪽이 먼저.
        case verticalTop(x: Double)
    }

    /// 놓을 글씨 하나 — 어디에 붙는지와 잰 크기.
    public struct Request: Hashable, Sendable {
        public var anchor: Anchor
        public var width: Double
        public var height: Double

        public init(anchor: Anchor, width: Double, height: Double) {
            self.anchor = anchor
            self.width = width
            self.height = height
        }
    }

    /// 자리 후보와 그 자리를 덜 바라는 정도(작을수록 먼저).
    public struct Candidate: Hashable, Sendable {
        public var box: Box
        public var penalty: Double
    }

    /// 글씨와 글씨 사이에 꼭 비워 둘 틈.
    public static let gap: Double = 3
    /// 그림 밖으로 나가는 후보를 안으로 밀어 넣을 때, 민 거리 1포인트마다 매기는 손해.
    /// 조금 미는 것은 괜찮고, 많이 밀어 표시에서 멀어지면 다른 후보가 낫다.
    static let shiftCost: Double = 0.15
    /// 점과 글씨 사이 — 점 표시의 반지름보다 조금 크다.
    static let pointOffset: Double = 6

    /// 글씨들을 **받은 순서(= 중요한 순서)대로** 놓는다. 결과는 받은 순서 그대로이고,
    /// 놓을 곳이 없으면 `nil` 이다. 어떤 글씨도 `bounds` 를 벗어나거나 다른 글씨와 `gap` 안으로 닿지 않는다.
    public static func place(_ requests: [Request], in bounds: Box, ink: [Ink]) -> [Box?] {
        var placed: [Box] = []
        var result: [Box?] = []
        for request in requests {
            var best: (box: Box, cost: Double)?
            for candidate in candidates(for: request, in: bounds) {
                guard let box = fitted(candidate.box, in: bounds),
                      !placed.contains(where: { $0.overlaps(box, gap: gap) })
                else { continue }
                let shift = abs(box.minX - candidate.box.minX) + abs(box.minY - candidate.box.minY)
                let cost = candidate.penalty + shift * shiftCost + coverage(of: box, ink: ink)
                // 같은 값이면 먼저 낸 후보 — 후보 순서가 곧 바라는 순서다.
                if best == nil || cost < best!.cost {
                    best = (box, cost)
                }
            }
            if let best { placed.append(best.box) }
            result.append(best?.box)
        }
        return result
    }

    /// 자리 후보들 — 바라는 순서대로.
    static func candidates(for request: Request, in bounds: Box) -> [Candidate] {
        let w = request.width
        let h = request.height
        func at(_ x: Double, _ y: Double, _ penalty: Double) -> Candidate {
            Candidate(box: Box(minX: x, minY: y, width: w, height: h), penalty: penalty)
        }
        switch request.anchor {
        case let .point(x, y):
            let d = pointOffset
            let above = y - d - h
            let below = y + d
            let higher = y - d - 2 * h - 4
            return [
                at(x - w / 2, above, 0),
                at(x - w * 0.2, above, 1.5),
                at(x - w * 0.8, above, 1.5),
                at(x + d, y - h / 2, 2.5),
                at(x - d - w, y - h / 2, 2.5),
                at(x - w / 2, below, 3.5),
                at(x - w * 0.2, below, 4.5),
                at(x - w * 0.8, below, 4.5),
                at(x - w / 2, higher, 6),
                at(x - w * 0.2, higher, 7),
                at(x - w * 0.8, higher, 7),
            ]
        case let .horizontal(y):
            let inset = 4.0
            let room = bounds.width - 2 * inset - w
            return [0, 0.25, 0.5, 0.75, 1].flatMap { fraction -> [Candidate] in
                let x = bounds.minX + inset + fraction * room
                return [at(x, y - 2 - h, fraction * 3), at(x, y + 2, 1 + fraction * 3)]
            }
        case let .verticalBottom(x, lanes):
            return (0..<max(1, lanes)).flatMap { lane -> [Candidate] in
                let y = bounds.maxY - 2 - h - Double(lane) * (h + gap + 1)
                let penalty = Double(lane) * 4
                return [at(x + 3, y, penalty), at(x - 3 - w, y, penalty + 1.5)]
            }
        case let .verticalTop(x):
            let heights = [bounds.minY + 2,
                           bounds.minY + bounds.height / 3 - h / 2,
                           bounds.minY + bounds.height * 2 / 3]
            return heights.enumerated().flatMap { index, y -> [Candidate] in
                let penalty = Double(index) * 2
                return [at(x + 4, y, penalty), at(x - 4 - w, y, penalty + 1)]
            }
        }
    }

    /// 그림 밖으로 나간 후보를 안으로 민다. 그림보다 크거나 좌표가 망가졌으면 놓을 수 없다.
    static func fitted(_ box: Box, in bounds: Box) -> Box? {
        guard box.minX.isFinite, box.minY.isFinite, box.width.isFinite, box.height.isFinite,
              box.width <= bounds.width, box.height <= bounds.height
        else { return nil }
        var fitted = box
        fitted.minX = min(max(box.minX, bounds.minX), bounds.maxX - box.width)
        fitted.minY = min(max(box.minY, bounds.minY), bounds.maxY - box.height)
        return fitted
    }

    /// 그 네모가 덮는 그림의 무게.
    static func coverage(of box: Box, ink: [Ink]) -> Double {
        ink.reduce(0) { sum, spot in box.contains(x: spot.x, y: spot.y) ? sum + spot.weight : sum }
    }

    // MARK: - 그림을 점으로

    /// 꺾은선을 `step` 포인트마다 점으로 끊는다. 화면 밖 점(무한대 · NaN)이 낀 마디는 건너뛴다.
    public static func trace(_ line: [(x: Double, y: Double)], weight: Double, step: Double = 3) -> [Ink] {
        var ink: [Ink] = []
        for (start, end) in zip(line, line.dropFirst()) {
            guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite else { continue }
            let length = ((end.x - start.x) * (end.x - start.x) + (end.y - start.y) * (end.y - start.y)).squareRoot()
            let count = max(1, Int(length / max(step, 0.5)))
            for index in 0..<count {
                let t = Double(index) / Double(count)
                ink.append(Ink(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t, weight: weight))
            }
        }
        if let last = line.last, last.x.isFinite, last.y.isFinite {
            ink.append(Ink(x: last.x, y: last.y, weight: weight))
        }
        return ink
    }

    /// 점 표시 하나 — 가운데와 둘레 여덟 곳. 글씨가 점을 덮지 않게 무겁게 준다.
    public static func marker(x: Double, y: Double, radius: Double = 5, weight: Double = 8) -> [Ink] {
        guard x.isFinite, y.isFinite else { return [] }
        return [Ink(x: x, y: y, weight: weight)] + (0..<8).map { index in
            let angle = Double(index) * Double.pi / 4
            return Ink(x: x + radius * cos(angle), y: y + radius * sin(angle), weight: weight)
        }
    }
}
