import Foundation
import Testing
@testable import Core

/// 목표 비중과 어긋남 판정 (docs/08-feedback.md 14번).
///
/// **기댓값은 파이썬으로 따로 계산해 대조했다** (CLAUDE.md 규칙).
@Suite("Allocation — 목표 비중")
struct AllocationTests {

    private func entry(_ label: String, _ amount: Int, _ bp: Int?) -> Allocation.Entry {
        Allocation.Entry(label: label,
                         amount: Money(minorUnits: amount, currency: .krw),
                         targetBP: bp)
    }

    @Test("같은 이름은 합쳐서 잰다 — 한 종목이 세 계좌에 흩어져 있다")
    func mergesByName() {
        // 이 설계를 가른 실제 상황이다. 계좌 안에서 재면 이 사람이 미국 주식을
        // 얼마나 갖고 있는지 알 수 없다.
        let slices = Allocation.slices([
            entry("TIGER", 100, 2_000),
            entry("TIGER", 100, 2_000),
            entry("VOO", 300, 6_000)
        ])
        #expect(slices.count == 2)
        #expect(slices[0].label == "TIGER")
        #expect(slices[0].amount == Money(minorUnits: 200, currency: .krw))
        // 목표도 합쳐진다: 2,000 + 2,000 = 4,000bp → 정규화하면 40%
        #expect(slices[0].actual == Decimal(string: "0.4"))
        #expect(slices[0].target == Decimal(string: "0.4"))
        #expect(slices[0].status == .onTrack)
    }

    @Test("목표 합이 100%가 아니어도 막지 않는다 — 비례로 정규화한다")
    func normalisesPartialTargets() {
        // 적다 말면 100이 안 되는 것이 정상이다. 그때 "전부 미달" 이라는
        // 거짓 경고가 뜨면 안 된다.
        let slices = Allocation.slices([
            entry("A", 100, 3_000),
            entry("B", 100, 3_000)
        ])
        #expect(slices[0].target == Decimal(string: "0.5"))
        #expect(slices[0].status == .onTrack)
    }

    @Test("목표를 안 정한 종목은 조용히 넘어가지 않는다")
    func noTargetIsItsOwnSignal() {
        let slices = Allocation.slices([
            entry("A", 100, 5_000),
            entry("B", 100, nil)
        ])
        let b = slices.first { $0.label == "B" }
        #expect(b?.target == nil)
        #expect(b?.status == .noTarget)
        #expect(b?.drift == nil)
    }

    @Test("허용 오차는 절대와 상대 중 큰 쪽이다")
    func toleranceTakesTheLarger() {
        let tolerance = Allocation.Tolerance()          // 5%p · 25%
        // 목표 60% → 0.6 × 25% = 15%p 가 더 크다
        #expect(tolerance.allowed(for: Decimal(string: "0.6")!) == Decimal(string: "0.15"))
        // 목표 5% → 0.05 × 25% = 1.25%p 라 절대값 5%p 가 이긴다.
        // 상대만 쓰면 작은 종목은 영영 안 걸린다.
        #expect(tolerance.allowed(for: Decimal(string: "0.05")!) == Decimal(string: "0.05"))
    }

    @Test("허용 오차 안이면 지킴, 두 배까지는 주의, 넘으면 조치")
    func threeSteps() {
        let tolerance = Allocation.Tolerance()
        let target = Decimal(string: "0.5")!            // 허용 12.5%p, 두 배 25%p
        #expect(Allocation.status(actual: Decimal(string: "0.60")!,
                                  target: target, tolerance: tolerance) == .onTrack)
        #expect(Allocation.status(actual: Decimal(string: "0.65")!,
                                  target: target, tolerance: tolerance) == .watch)
        #expect(Allocation.status(actual: Decimal(string: "0.80")!,
                                  target: target, tolerance: tolerance) == .act)
    }

    @Test("적립을 나눠 넣으면 목표에 정확히 닿는다 — 팔지 않는다")
    func contributionRestoresTheTarget() {
        // A 60 · B 40 을 50:50 으로 맞춘다. 파는 대신 100 을 나눠 넣는다.
        let slices = Allocation.slices([entry("A", 60, 5_000), entry("B", 40, 5_000)])
        let split = Allocation.contributionSplit(slices,
                                                 contribution: Money(minorUnits: 100, currency: .krw))
        let byLabel = Dictionary(uniqueKeysWithValues: split.map { ($0.label, $0.amount.minorUnits) })
        #expect(byLabel["A"] == 40)
        #expect(byLabel["B"] == 60)
        // 넣고 나면 100 : 100 — 정확히 목표다.
        #expect(split.reduce(0) { $0 + $1.amount.minorUnits } == 100)
    }

    @Test("이미 목표를 넘긴 곳에는 넣지 않는다")
    func overweightGetsNothing() {
        let slices = Allocation.slices([entry("A", 900, 5_000), entry("B", 100, 5_000)])
        let split = Allocation.contributionSplit(slices,
                                                 contribution: Money(minorUnits: 100, currency: .krw))
        #expect(split.count == 1)
        #expect(split.first?.label == "B")
        #expect(split.first?.amount.minorUnits == 100)
    }

    @Test("빈 목록과 0원 적립에서 무너지지 않는다")
    func edges() {
        #expect(Allocation.slices([]).isEmpty)
        #expect(Allocation.slices([entry("A", 0, 5_000)]).isEmpty)
        let slices = Allocation.slices([entry("A", 100, 5_000)])
        #expect(Allocation.contributionSplit(slices,
                                             contribution: .zero(.krw)).isEmpty)
    }
}
