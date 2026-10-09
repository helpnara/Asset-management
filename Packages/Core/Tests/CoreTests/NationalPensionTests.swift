import Foundation
import Testing
@testable import Core

/// 기댓값은 전부 파이썬 `fractions` 로 따로 계산했다 (CLAUDE.md — 지어낸
/// 기댓값을 넣지 않는다). 월액 = Σ상수 × (A+B) × (240+초과월) / (1000·240·12·연수).
@Suite("NationalPension — 국민연금 근사")
struct NationalPensionTests {

    private func krw(_ value: Int) -> Money { Money(minorUnits: value, currency: .krw) }

    @Test("비례상수는 가입 연도마다 다르다")
    func constants() {
        #expect(NationalPension.constantMilli(forYear: 1998) == 2400)
        #expect(NationalPension.constantMilli(forYear: 1999) == 1800)
        #expect(NationalPension.constantMilli(forYear: 2008) == 1500)
        #expect(NationalPension.constantMilli(forYear: 2025) == 1245)
        #expect(NationalPension.constantMilli(forYear: 2026) == 1290)
        #expect(NationalPension.constantMilli(forYear: 2060) == 1290)
    }

    // 1999~2038 (40년, 초과 240개월), B = A = 3,089,062. Σ상수 = 57,675.
    // 57675 × 6,178,124 × 480 / (1000·240·12·40) = 1,484,680.42375 → 1,484,680
    // 대체율 = 57675 × 10 / (3 × 40) = 4806.25 → 4806
    @Test("40년 가입, 평균 소득자")
    func fortyYearsAverageEarner() throws {
        let estimate = try #require(NationalPension.estimate(
            averageMonthlyIncome: krw(3_089_062), firstYear: 1999, lastYear: 2038))
        #expect(estimate.years == 40)
        #expect(estimate.monthly.minorUnits == 1_484_680)
        #expect(estimate.replacementBP == 4806)
    }

    // 2026~2045 (20년, 초과 없음), 입력 1,000만원은 상한 6,370,000 으로 잘린다.
    // 25800 × 9,459,062 × 240 / (1000·240·12·20) = 1,016,849.165 → 1,016,849
    @Test("상한을 넘는 소득은 상한으로 자른다 · 2026년 이후는 43%")
    func ceilingAndNewRate() throws {
        let estimate = try #require(NationalPension.estimate(
            averageMonthlyIncome: krw(10_000_000), firstYear: 2026, lastYear: 2045))
        #expect(estimate.incomeUsed.minorUnits == 6_370_000)
        #expect(estimate.monthly.minorUnits == 1_016_849)
        #expect(estimate.replacementBP == 4300)
    }

    // 2010~2039 (30년, 초과 120개월), 입력 10만원은 하한 40만원. Σ상수 = 39,780.
    // 39780 × 3,489,062 × 360 / (1000·240·12·30) = 578,312.0265 → 578,312
    @Test("하한 아래 소득은 하한으로 올린다")
    func floor() throws {
        let estimate = try #require(NationalPension.estimate(
            averageMonthlyIncome: krw(100_000), firstYear: 2010, lastYear: 2039))
        #expect(estimate.incomeUsed.minorUnits == 400_000)
        #expect(estimate.monthly.minorUnits == 578_312)
        #expect(estimate.replacementBP == 4420)
    }

    // 2016~2045 (30년), B = 300만. Σ상수 = 38,925.
    // 38925 × 6,089,062 × 360 / (1000·240·12·30) = 987,569.743 → 987,570
    @Test("구간이 걸치면 연수로 가중 평균한다")
    func weightedAcrossEras() throws {
        let estimate = try #require(NationalPension.estimate(
            averageMonthlyIncome: krw(3_000_000), firstYear: 2016, lastYear: 2045))
        #expect(estimate.monthly.minorUnits == 987_570)
        #expect(estimate.replacementBP == 4325)
    }

    // 1985~1997 → 1988~1997 (10년, 전부 2.4). 10년이면 기본연금액의 50% (194번 E2).
    // 24000 × 5,589,062 × 120 / (1000·240·12·10) = 558,906.2 → 558,906
    @Test("1988년 전은 가입 기간이 아니다 · 딱 10년이면 된다 · 그때는 절반")
    func schemeStart() throws {
        let estimate = try #require(NationalPension.estimate(
            averageMonthlyIncome: krw(2_500_000), firstYear: 1985, lastYear: 1997))
        #expect(estimate.years == 10)
        #expect(estimate.monthly.minorUnits == 558_906)
        #expect(estimate.replacementBP == 8000)
    }

    // 2012~2045 (34년 폭) 인데 실제 300개월. Σ상수 = 44,595, 초과 60개월.
    // 44595 × 9,459,062 × 300 / (1000·240·12·34) = 1,292,361.73 → 1,292,362
    // 대체율 = 44595 × 10 / (3 × 34) = 4372.06 → 4372
    @Test("실제 가입 개월 수가 연도 폭보다 짧으면 그만큼만 센다 (125번)")
    func actualMonths() throws {
        let estimate = try #require(NationalPension.estimate(
            averageMonthlyIncome: krw(10_000_000), firstYear: 2012, lastYear: 2045, months: 300))
        #expect(estimate.years == 25)
        #expect(estimate.monthly.minorUnits == 1_292_362)
        #expect(estimate.replacementBP == 4372)
        // 개월 수를 폭 전부로 주면 안 준 것과 같다.
        #expect(NationalPension.estimate(averageMonthlyIncome: krw(3_000_000),
                                         firstYear: 2016, lastYear: 2045, months: 360)?.monthly.minorUnits
                == NationalPension.estimate(averageMonthlyIncome: krw(3_000_000),
                                            firstYear: 2016, lastYear: 2045)?.monthly.minorUnits)
        // 119개월은 연금이 아니다.
        #expect(NationalPension.estimate(averageMonthlyIncome: krw(3_000_000),
                                         firstYear: 2012, lastYear: 2045, months: 119) == nil)
    }

    // 가입 10~20년은 50% + 10년 넘는 1년마다 5% = 월수/240 (194번 E2). 파이썬으로 따로 계산.
    // 2026~2040 (15년, 180개월), B = 300만. Σ상수 = 19,350.
    // 19350 × 6,089,062 × 180 / (1000·240·12·15) = 490,930.62375 → 490,931 (예전 식은 654,574)
    // 2026~2035 (10년) 은 327,287 — 20년(654,574)의 정확히 절반.
    @Test("가입 20년 미만이면 그만큼 줄어든다")
    func underTwentyYears() throws {
        let fifteen = try #require(NationalPension.estimate(
            averageMonthlyIncome: krw(3_000_000), firstYear: 2026, lastYear: 2040))
        #expect(fifteen.years == 15)
        #expect(fifteen.monthly.minorUnits == 490_931)
        let ten = try #require(NationalPension.estimate(
            averageMonthlyIncome: krw(3_000_000), firstYear: 2026, lastYear: 2035))
        #expect(ten.monthly.minorUnits == 327_287)
    }

    @Test("수령 개시 나이 — 1969년생부터 65세")
    func claimAge() {
        #expect(NationalPension.claimAge(birthYear: 1952) == 60)
        #expect(NationalPension.claimAge(birthYear: 1955) == 61)
        #expect(NationalPension.claimAge(birthYear: 1960) == 62)
        #expect(NationalPension.claimAge(birthYear: 1963) == 63)
        #expect(NationalPension.claimAge(birthYear: 1968) == 64)
        #expect(NationalPension.claimAge(birthYear: 1969) == 65)
        #expect(NationalPension.claimAge(birthYear: 1985) == 65)
    }

    @Test("10년 미만이면 연금이 아니다")
    func tooShort() {
        #expect(NationalPension.estimate(averageMonthlyIncome: krw(3_000_000),
                                         firstYear: 2030, lastYear: 2038) == nil)
        #expect(NationalPension.estimate(averageMonthlyIncome: krw(3_000_000),
                                         firstYear: 2040, lastYear: 2030) == nil)
    }
}
