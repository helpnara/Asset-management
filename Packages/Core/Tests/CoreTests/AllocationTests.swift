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

    @Test("열쇠가 다르면 이름이 같아도 안 합친다 — 계좌 층")
    func doesNotMergeWhenKeysDiffer() {
        // 실제로 났던 버그다 (docs/08-feedback.md 30번). 같은 이름의 계좌 둘이
        // 하나로 합쳐져 **둘 다 100%** 로 보였다. 계좌는 이름이 같아도 다른
        // 개체이므로 열쇠를 따로 준다.
        //
        // 기댓값은 파이썬으로 대조했다:
        //   29,800,000 / 32,100,000 = 92.8348…%  → 내림 92, 소수부 .8348
        //    2,300,000 / 32,100,000 =  7.1651…%  → 내림  7, 소수부 .1651
        //   남은 1 은 소수부가 큰 쪽으로 → 93 / 7
        let slices = Allocation.slices([
            Allocation.Entry(key: "account-1", label: "일반적립",
                             amount: Money(minorUnits: 29_800_000, currency: .krw),
                             targetBP: nil),
            Allocation.Entry(key: "account-2", label: "일반적립",
                             amount: Money(minorUnits: 2_300_000, currency: .krw),
                             targetBP: nil)
        ])
        #expect(slices.count == 2)
        #expect(slices.map(\.label) == ["일반적립", "일반적립"])
        #expect(slices.map(\.actualPercent) == [93, 7])
        // 화면이 되찾을 때 쓰는 값. 열쇠가 겹치면 두 줄이 같은 것을 가리킨다.
        #expect(slices.map(\.key) == ["account-1", "account-2"])
        #expect(slices.map(\.id) == ["account-1", "account-2"])
    }

    @Test("열쇠를 안 주면 이름이 열쇠다 — 종목 층은 그대로 합친다")
    func defaultsKeyToLabel() {
        let slices = Allocation.slices([
            entry("TIGER", 100, nil),
            entry("TIGER", 100, nil)
        ])
        #expect(slices.count == 1)
        #expect(slices[0].key == "TIGER")
    }

    @Test("목표는 적은 그대로 쓴다 — 정규화하지 않는다")
    func targetsAreTakenAsWritten() {
        // 한때 목표 합으로 나눠 비례 배분했다. 그러면 30% 라고 적은 것이 화면에
        // 50% 로 보인다. 사용자가 요구한 표기는 `15/20%` — 적은 값이 그대로
        // 서야 한다. 합이 60%뿐이면 그건 **덜 적은 것**이고, 화면은 합계를
        // 눈에 띄게 적어 그 사실을 알린다.
        let slices = Allocation.slices([
            entry("A", 100, 3_000),
            entry("B", 100, 3_000)
        ])
        #expect(slices[0].target == Decimal(string: "0.3"))
        #expect(slices[0].actual == Decimal(string: "0.5"))
        // 30% 목표에 50% 를 들고 있으면 20%p 넘쳤다.
        #expect(slices[0].status == .over)
        #expect(Allocation.targetSumBP([entry("A", 100, 3_000), entry("B", 100, 3_000)]) == 6_000)
    }

    @Test("한 줄에 실제와 목표가 나란히 선다 — 15/20%")
    func comparisonLabelReadsAsRequested() {
        // 조치·주의만으로는 얼마나 벗어났는지 알 수 없다는 것이 사용자의 지적이다.
        let slices = Allocation.slices([
            entry("KODEX 국고채3년", 15, 2_000),
            entry("나머지", 85, 8_000)
        ])
        #expect(slices[0].comparisonLabel == "15/20%")
        // 목표 20%에 실제 15% — 5%p 모자라니 ±3%p 를 벗어난다.
        #expect(slices[0].status == .under)
        // 목표가 없으면 실제만 적는다.
        let untargeted = Allocation.slices([entry("A", 15, nil), entry("B", 85, nil)])
        #expect(untargeted[0].comparisonLabel == "15%")
    }

    @Test("목표 합은 같은 이름을 합쳐서 센다")
    func targetSumMergesByName() {
        // `slices` 와 같은 규칙이어야 화면의 두 숫자가 어긋나지 않는다.
        #expect(Allocation.targetSumBP([
            entry("TIGER", 100, 2_000),
            entry("TIGER", 100, 2_000),
            entry("VOO", 300, 6_000)
        ]) == 10_000)
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

    @Test("허용 오차는 퍼센트포인트 하나다 — 기본 ±3%p")
    func toleranceIsOneNumber() {
        // 절대와 상대를 섞어 쓰던 것을 걷어냈다. 두 숫자가 어떻게 맞물리는지
        // 설명하기 어렵고 조절하기도 어려웠다.
        #expect(Allocation.Tolerance().allowed == Decimal(string: "0.03"))
        #expect(Allocation.Tolerance(absolute: Ratio(basisPoints: 500)).allowed
                == Decimal(string: "0.05"))
    }

    @Test("어느 쪽으로 벗어났는지 말한다 — 초과 · 부족 · (지키면 조용히)")
    func statusSaysWhichWay() {
        let tolerance = Allocation.Tolerance()          // ±3%p
        let target = Decimal(string: "0.20")!
        // 17~23% 는 지킴. 배지를 안 단다.
        #expect(Allocation.status(actual: Decimal(string: "0.23")!,
                                  target: target, tolerance: tolerance) == .onTrack)
        #expect(Allocation.status(actual: Decimal(string: "0.17")!,
                                  target: target, tolerance: tolerance) == .onTrack)
        #expect(Allocation.status(actual: Decimal(string: "0.24")!,
                                  target: target, tolerance: tolerance) == .over)
        #expect(Allocation.status(actual: Decimal(string: "0.16")!,
                                  target: target, tolerance: tolerance) == .under)
        // 지키고 있을 때는 아무 말도 안 한다.
        #expect(Allocation.DriftStatus.onTrack.label == "")
        #expect(Allocation.DriftStatus.onTrack.isDrifting == false)
        #expect(Allocation.DriftStatus.over.isDrifting)
    }

    @Test("정수 퍼센트는 합이 정확히 100 이 된다")
    func integerPercentsSumToHundred() {
        // 실제로 화면에 나온 값이다. 줄마다 따로 반올림하면
        // 32 + 8 + 16 + 7 + 38 = 101 이 되어 틀려 보인다.
        let total = Decimal(264_000_000)
        let fractions = [83_700_000, 19_800_000, 42_000_000, 18_500_000, 100_000_000]
            .map { Decimal($0) / total }
        let percents = Allocation.integerPercents(fractions)
        #expect(percents == [32, 7, 16, 7, 38])
        #expect(percents.reduce(0, +) == 100)
    }

    @Test("합이 1 이 아니면 부풀리지 않는다")
    func partialSetsAreNotInflated() {
        // 목표를 덜 적어 60%뿐인 것을 100 으로 만들면 거짓말이 된다.
        #expect(Allocation.integerPercents([Decimal(string: "0.3")!,
                                            Decimal(string: "0.3")!]) == [30, 30])
        #expect(Allocation.integerPercents([]).isEmpty)
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
