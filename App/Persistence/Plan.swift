import Core
import Foundation
import CoreData

/// 계획의 가정. 가구당 하나만 둔다.
///
/// 지금은 가구 전체를 하나의 숫자로 굴린다. 구성원별 적립 계획·연금·목돈 이벤트는
/// M2 후반에 세분화한다. 먼저 궤적 한 줄을 끝까지 그려 보는 것이 순서다.
extension Plan {
    // MARK: 진단 기준
    //
    // 전부 사용자가 고칠 수 있는 값이다. 기본값은 흔히 쓰는 수치일 뿐
    // 정답이 아니다. CloudKit 제약 때문에 모두 기본값을 갖는다 (ADR-0001).

    // `init(context:)` 를 따로 두지 않는다. `NSManagedObject` 가 이미 주는
    // 이니셜라이저와 이름이 같아 **자기를 부르는 무한 재귀**가 된다.
}

/// 특정 시점의 큰 자금 이동. 전월세보증금 전환, 퇴직금 유입, 주택 구입.
extension CashEvent {
    convenience init(context: NSManagedObjectContext,
                     date: Date = .now, label: String = "",
                     amountMinor: Int = 0, sortIndex: Int = 0) {
        self.init(context: context)
        self.date = date
        self.label = label
        self.amountMinor = amountMinor
        self.sortIndex = sortIndex
    }
}

/// 은퇴 후 들어오는 소득. 국민연금 · 퇴직연금 · 개인연금 · 임대소득.
///
/// **금액은 오늘 돈 기준으로 적는다.** "65세부터 월 150만원"의 150만원은
/// 지금 물가로 말한 것이지 20년 뒤의 액면가가 아니다.
extension IncomeStream {
    convenience init(context: NSManagedObjectContext, label: String = "", monthlyAmountMinor: Int = 0, startYear: Int? = nil,
         sortIndex: Int = 0) {
        self.init(context: context)
        self.label = label
        self.monthlyAmountMinor = monthlyAmountMinor
        self.startYear = startYear ?? (Calendar.current.component(.year, from: .now) + 20)
        self.sortIndex = sortIndex
    }
}

extension IncomeStream {
    var monthlyAmount: Money { Money(minorUnits: monthlyAmountMinor, currency: .krw) }

    var input: IncomeStreamInput {
        IncomeStreamInput(
            label: label,
            monthlyAmount: monthlyAmount,
            startYear: startYear,
            endYear: endYear > 0 ? endYear : nil,
            isInflationLinked: isInflationLinked
        )
    }
}

extension CashEvent {
    var amount: Money { Money(minorUnits: amountMinor, currency: .krw) }
    var isInflow: Bool { amountMinor >= 0 }
}

extension Plan {
    var annualReturn: Ratio { Ratio(basisPoints: annualReturnBP) }
    var withdrawalRate: Ratio { Ratio(basisPoints: withdrawalRateBP) }
    var savingsFloor: Ratio { Ratio(basisPoints: savingsFloorBP) }
    var illiquidCap: Ratio { Ratio(basisPoints: illiquidCapBP) }
    var usTarget: Ratio { Ratio(basisPoints: usTargetBP) }
    var mixTolerance: Ratio { Ratio(basisPoints: mixToleranceBP) }

    /// 목표 비중 판정 기준. 퍼센트포인트 하나다.
    var driftTolerance: Allocation.Tolerance {
        Allocation.Tolerance(absolute: Ratio(basisPoints: driftToleranceBP))
    }

    /// 계획에서 사람이 고칠 수 있는 값들을 한 줄로 묶은 지문.
    ///
    /// 화면이 이걸 지켜보다 달라지면 `touch()` 를 부른다. 필드마다 `onChange`
    /// 를 붙이면 스무 개가 되고, 하나 빠뜨려도 티가 안 난다.
    var editFingerprint: String {
        [startYear, retirementYear, horizonYear, monthlyContributionMinor,
         contributionGrowthBP, annualReturnBP, inflationBP, lowYieldReturnBP,
         realEstateReturnBP, targetAmountMinor, monthlySpendingMinor,
         withdrawalRateBP, monthlyIncomeMinor, savingsFloorBP, illiquidCapBP,
         usTargetBP, mixToleranceBP, driftToleranceBP,
         usesMemberContributions ? 1 : 0]
            .map(String.init).joined(separator: "-")
        + "|\(title)|\(asOfNote)|\(declaration)|\(startedOn?.timeIntervalSince1970 ?? 0)"
        + "|\(disabledDiagnosesRaw)|\(contributionOrderRaw)"
    }

    /// 켜 둔 진단 규칙. 화면과 계산이 같은 값을 읽는다.
    var enabledDiagnoses: Set<DiagnosisKind> {
        get {
            let disabled = Set(disabledDiagnosesRaw.split(separator: ",")
                .compactMap { DiagnosisKind(rawValue: String($0)) })
            return Set(DiagnosisKind.allCases).subtracting(disabled)
        }
        set {
            let disabled = Set(DiagnosisKind.allCases).subtracting(newValue)
            disabledDiagnosesRaw = disabled.map(\.rawValue).sorted().joined(separator: ",")
        }
    }

    /// 세제혜택 계좌를 채우는 순서.
    var contributionOrder: [AccountKind] {
        get {
            let saved = contributionOrderRaw.split(separator: ",")
                .compactMap { AccountKind(rawValue: String($0)) }
            return saved.isEmpty ? Diagnostics.defaultContributionOrder : saved
        }
        set { contributionOrderRaw = newValue.map(\.rawValue).joined(separator: ",") }
    }

    /// 지문의 자리마다 사람이 읽는 이름. **순서가 `editFingerprint` 와 같아야
    /// 한다** — 어긋나면 변경 이력이 엉뚱한 항목 이름을 적는다.
    static let fieldLabels: [String] = [
        "시작 연도", "은퇴 연도", "지평선", "월 적립", "적립 증가율",
        "연 기대수익률", "물가상승률", "저금리 수익률", "부동산 상승률",
        "목표 금액", "월 생활비", "인출률", "월 소득", "저축률 하한",
        "비유동 자산 상한", "미국 목표 비중", "지역 허용 오차", "비중 허용 오차",
        "구성원별 적립",
        // `|` 뒤의 글자 항목들. 같은 순서다.
        "1페이지 제목", "기준 시점", "선언문", "수립일",
        "진단 규칙", "세제혜택 순서"
    ]

    /// 두 지문을 견줘 **무엇이 달라졌는지** 이름으로 돌려준다
    /// (docs/08-feedback.md 29번). 값 자체는 남기지 않는다 — 이력이 금액
    /// 목록이 되면 남에게 보여줄 수 없는 화면이 된다.
    static func changedLabels(from before: String, to after: String) -> [String] {
        func fields(_ text: String) -> [String] {
            let parts = text.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard let numbers = parts.first else { return [] }
            return numbers.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                + parts.dropFirst()
        }
        let old = fields(before)
        let new = fields(after)
        guard old.count == new.count else { return [] }
        return zip(old, new).enumerated().compactMap { index, pair in
            guard pair.0 != pair.1, fieldLabels.indices.contains(index) else { return nil }
            return fieldLabels[index]
        }
    }

    /// 계획을 고친 시각을 찍는다. **값이 실제로 달라졌을 때만** 찍어야
    /// 화면을 열기만 해도 날짜가 바뀌는 일이 없다.
    func touch() {
        let now = Date.now
        // 같은 편집 흐름에서 여러 번 불려도 초 단위로 뭉갠다.
        if let updatedAt, now.timeIntervalSince(updatedAt) < 1 { return }
        updatedAt = now
    }
    var monthlySpending: Money { Money(minorUnits: monthlySpendingMinor, currency: .krw) }
    var monthlyIncome: Money { Money(minorUnits: monthlyIncomeMinor, currency: .krw) }
    var contributionGrowth: Ratio { Ratio(basisPoints: contributionGrowthBP) }
    var inflation: Ratio { Ratio(basisPoints: inflationBP) }
    var lowYieldReturn: Ratio { Ratio(basisPoints: lowYieldReturnBP) }
    var realEstateReturn: Ratio { Ratio(basisPoints: realEstateReturnBP) }
    var monthlyContribution: Money { Money(minorUnits: monthlyContributionMinor, currency: .krw) }
    var targetAmount: Money { Money(minorUnits: targetAmountMinor, currency: .krw) }

    var yearsToRetirement: Int {
        max(retirementYear - Calendar.current.component(.year, from: .now), 0)
    }

    /// 오늘 잔고에서 은퇴 시점까지 굴린다.
    ///
    /// 이미 반영된 목돈은 넣지 않는다. 현재 잔고에 이미 들어 있는데 또 더하면
    /// 두 번 세는 셈이 된다.
    func projection(
        from balance: Money,
        cashEvents: [CashEvent] = [],
        incomes: [IncomeStream] = [],
        members: [Member] = [],
        calendar: Calendar = .current
    ) -> ProjectionResult {
        Projection.run(
            projectionInput(from: balance, cashEvents: cashEvents, incomes: incomes,
                            members: members, calendar: calendar),
            calendar: calendar
        )
    }

    /// 실제로 굴릴 월 적립액. 구성원별로 나눠 넣고 있으면 그 합이다.
    func effectiveMonthlyContribution(members: [Member]) -> Money {
        guard usesMemberContributions else { return monthlyContribution }
        return Money(minorUnits: members.reduce(0) { $0 + $1.monthlyContributionMinor },
                     currency: .krw)
    }

    /// **한 사람 몫의 월 적립.** 구성원 궤적과 1페이지 미니 바차트가 함께 쓴다
    /// (docs/08-feedback.md 33번).
    ///
    /// 구성원별로 나눠 넣고 있으면 그 사람 칸의 값(본인 + 회사 매칭)이다.
    /// 안 나눠 넣고 있으면 계획에 한 덩어리로만 있으므로 **자산 비중대로**
    /// 나눈다 — 그러지 않으면 그 사람 몫이 0이 되어 궤적이 자라지 않는다.
    /// 자산이 없으면 0이다. 없는 돈을 나눠 줄 근거가 없다.
    func memberMonthlyContributionMinor(_ member: Member, familyTotal: Money) -> Int {
        if usesMemberContributions {
            return member.monthlyContributionMinor + member.employerMatchMinor
        }
        let mine = member.sortedAccounts
            .filter { !$0.isArchived }
            .reduce(0) { sum, account in
                let value = account.sortedHoldings.reduce(0) { $0 + $1.valueMinor }
                return sum + (account.kind.isLiability ? -value : value)
            }
        guard familyTotal.minorUnits > 0, mine > 0 else { return 0 }
        // 정수로만 센다 (ADR-0003 — 금액에 Double 을 쓰지 않는다).
        // 한 번에 곱하면 자릿수가 커져 넘칠 수 있으므로 **비중을 먼저** 낸다.
        // `Decimals` 는 `Core` 안에만 있어 여기서 못 쓴다.
        let shareBP = mine * 10_000 / familyTotal.minorUnits
        return monthlyContributionMinor * shareBP / 10_000
    }

    /// 계산 직전의 입력. 시뮬레이션은 이걸 받아 손잡이만 바꿔 끼운다.
    ///
    /// `@Model` 은 `Sendable` 이 아니지만 `ProjectionInput` 은 값 타입이라
    /// 어디로든 넘길 수 있다. 시뮬레이션이 Plan 을 들고 다니지 않는 이유다.
    func projectionInput(
        from balance: Money,
        cashEvents: [CashEvent] = [],
        incomes: [IncomeStream] = [],
        members: [Member] = [],
        asOf: Date? = nil,
        calendar: Calendar = .current
    ) -> ProjectionInput {
        // `asOf` 는 **계획선**이 쓴다 (docs/08-feedback.md 37번) — 계획을 세운
        // 날에서 출발해 굴려야 "그때 계획대로면 지금쯤 여기" 가 나온다.
        // 비워 두면 오늘이다.
        let now = calendar.startOfDay(for: asOf ?? .now)
        let retirement = Plan.endDate(retirementYear: retirementYear, notBefore: now, calendar: calendar)
        // 은퇴 후 생활비를 넣지 않았으면 은퇴 시점에서 멈춘다. 인출을 가정하지
        // 않는 궤적에 20년을 더 그려 봐야 그냥 계속 오르는 선일 뿐이다.
        let horizon = monthlySpendingMinor > 0
            ? Plan.endDate(retirementYear: max(horizonYear, retirementYear),
                           notBefore: retirement, calendar: calendar)
            : retirement
        let pending = cashEvents
            .filter { !$0.isAlreadyReflected && $0.date > now }
            .map { CashEventInput(date: $0.date, amount: $0.amount, label: $0.label) }

        return ProjectionInput(
            startDate: now,
            endDate: horizon,
            buckets: buckets(of: members, total: balance),
            monthlyContribution: effectiveMonthlyContribution(members: members),
            annualReturn: annualReturn,
            annualContributionGrowth: contributionGrowth,
            inflation: inflation,
            cashEvents: pending,
            targetAmount: targetAmountMinor > 0 ? targetAmount : nil,
            annualIncome: Money(minorUnits: monthlyIncomeMinor * 12, currency: .krw),
            retirementDate: retirement,
            monthlyRetirementSpending: monthlySpending,
            incomes: incomes.sorted { $0.sortIndex < $1.sortIndex }.map(\.input)
        )
    }

    /// 순자산을 **자라는 속도별로 나눈다.**
    ///
    /// 예전에는 순자산 전액을 연 8% 로 굴렸다. 그래서 전월세보증금 2억이 23년 뒤
    /// 궤적에서 11.8억이 됐다 — 실제로는 2억 그대로인 돈인데도
    /// (docs/08-feedback.md 11번).
    ///
    /// 수익률이 같은 계좌끼리 한 덩어리로 묶는다. 계좌마다 금리를 따로 적으면
    /// 그만큼 덩어리가 늘어나는데, 예금 몇 개 수준이라 문제되지 않는다.
    func buckets(of members: [Member], total: Money) -> [BalanceBucket] {
        struct Key: Hashable { let profile: ReturnProfile; let bp: Int }
        var sums: [Key: Int] = [:]

        for member in members {
            for account in member.sortedAccounts where !account.isArchived {
                let value = account.sortedHoldings.reduce(0) { $0 + $1.valueMinor }
                guard value != 0 else { continue }
                let profile = account.kind.returnProfile
                let key = Key(profile: profile,
                              bp: account.expectedReturnBP ?? defaultReturnBP(for: profile))
                // 부채는 음수로 담는다. 그래야 덩어리의 합이 순자산과 맞는다.
                sums[key, default: 0] += account.kind.isLiability ? -value : value
            }
        }

        var buckets = sums
            .map { BalanceBucket(profile: $0.key.profile,
                                 amount: Money(minorUnits: $0.value, currency: .krw),
                                 annualReturn: Ratio(basisPoints: $0.key.bp)) }
            .sorted {
                ($0.profile.drawdownOrder, $0.annualReturn.basisPoints)
                    < ($1.profile.drawdownOrder, $1.annualReturn.basisPoints)
            }

        // 적립과 목돈이 들어갈 자리가 반드시 있어야 한다. 투자자산이 하나도
        // 없으면(전월세보증금만 있는 초기 상태 등) 빈 덩어리를 만들어 둔다.
        if !buckets.contains(where: { $0.profile == .investment }) {
            buckets.insert(BalanceBucket(profile: .investment, amount: .zero(.krw),
                                         annualReturn: annualReturn), at: 0)
        }

        // 덩어리의 합이 화면의 순자산과 어긋나면 **화면이 거짓말을 한다.**
        // 소유자가 없는 계좌처럼 합계에 안 잡히는 경우가 있으므로 차액을
        // 투자자산에 맞춰 넣는다.
        let sum = buckets.dropFirst().reduce(buckets[0].amount) { $0 + $1.amount }
        let gap = total - sum
        if !gap.isZero, let index = buckets.firstIndex(where: { $0.profile == .investment }) {
            buckets[index].amount += gap
        }
        return buckets
    }

    private func defaultReturnBP(for profile: ReturnProfile) -> Int {
        switch profile {
        case .investment: return annualReturnBP
        case .lowYield: return lowYieldReturnBP
        case .realEstate: return realEstateReturnBP
        case .fixed: return 0
        }
    }

    /// 은퇴 연도만 바꾼 종료 시점. 시뮬레이션에서 기간 손잡이가 쓴다.
    static func endDate(retirementYear: Int, notBefore start: Date,
                        calendar: Calendar = .current) -> Date {
        let end = calendar.date(from: DateComponents(year: retirementYear, month: 12, day: 31)) ?? start
        return max(end, start)
    }

    /// 진단에 넘길 입력을 만든다.
    ///
    /// `@Model` 은 여기서 끝난다 — 나가는 것은 값 타입뿐이라 계산이 영속 계층을
    /// 모르고, 시뮬레이터 없이 테스트된다 (ADR-0002).
    func diagnosticsInput(
        rollup: Rollup,
        accounts: [Account],
        projection: ProjectionResult?,
        members: [Member] = [],
        calendar: Calendar = .current
    ) -> DiagnosticsInput {
        // 진단의 "은퇴 시점 예상"은 궤적의 끝이 아니라 **은퇴 시점**이어야 한다.
        // 인출 구간까지 그리기 시작하면서 끝값이 은퇴 후 30년 뒤 잔고가 됐다.
        let atRetirement = projection?.point(inYear: retirementYear, calendar: calendar)?.nominal
            ?? projection?.last?.nominal
        // 부동산 · 전월세보증금 = 자산 − 투자자산.
        // countsAsInvestable 이 false 인 것들이 정확히 이 몫이다.
        let illiquid = rollup.assets - rollup.investable
        let year = calendar.component(.year, from: .now)

        return DiagnosticsInput(
            netWorth: rollup.netWorth,
            investable: rollup.investable,
            illiquid: illiquid,
            byCountry: rollup.byCountry,
            monthlySpending: monthlySpending,
            withdrawalRate: withdrawalRate,
            monthlyIncome: monthlyIncome,
            driftingHoldings: members.reduce(0) { $0 + $1.driftingHoldingCount(tolerance: driftTolerance) },
            untargetedHoldings: members.reduce(0) { $0 + $1.untargetedHoldingCount },
            totalHoldings: members.reduce(0) { $0 + $1.investableHoldingCount },
            monthlyContribution: effectiveMonthlyContribution(members: members),
            savingsFloor: savingsFloor,
            annualReturn: annualReturn,
            illiquidCap: illiquidCap,
            usTarget: usTarget,
            mixTolerance: mixTolerance,
            yearsToRetirement: yearsToRetirement,
            projectedAtRetirement: atRetirement,
            doublingYear: projection?.milestone(.doubled)?.year,
            currentYear: year,
            limitAccounts: accounts
                .filter { $0.kind.hasContributionLimit }
                .map {
                    LimitAccountInput(
                        kind: $0.kind,
                        name: $0.name,
                        contributedThisYear: Money(minorUnits: $0.annualContributionMinor, currency: .krw),
                        annualLimit: Money(minorUnits: $0.annualLimitMinor, currency: .krw)
                    )
                },
            // 켜 둔 규칙과 채우는 순서는 계획에 저장된 사용자의 것이다 (47번).
            // **선언 순서와 같아야 한다** — 스위프트는 인자 순서를 지킨다.
            enabledKinds: enabledDiagnoses,
            contributionOrder: contributionOrder
        )
    }

    /// 저장소에 하나뿐인 계획을 꺼내고, 없으면 만든다.
    ///
    /// 둘 이상이면 **가장 오래된 가구의 가장 오래된 계획**이다. 정렬 없는
    /// `.first` 는 순서를 보장하지 않아서, 참가자 기기에 잠깐 가구가 둘일 때
    /// 부를 때마다 다른 계획을 줄 수 있다.
    static func current(in context: NSManagedObjectContext) -> Plan {
        let byAge = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let household = context.all(Household.self, sortedBy: byAge).first,
           let plans = household.plans as? Set<Plan>,
           let existing = plans.min(by: { $0.createdAt < $1.createdAt }) {
            return existing
        }
        if let existing = context.all(Plan.self, sortedBy: byAge).first {
            return existing
        }
        // Core Data 는 만드는 순간 컨텍스트에 들어간다 — `insert` 를 따로 안 부른다.
        return Plan(context: context)
    }
}
