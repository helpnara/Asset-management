import Foundation

/// **국민연금 예상 수령액 근사** (docs/05-roadmap.md D3).
///
/// 공단의 예상연금 조회를 대신하지 않는다 — 공식은 해마다 바뀌고, 소득
/// 재평가·크레딧·조기·연기 수령은 여기 없다. 이 앱이 이걸 두는 이유는
/// **배우는 도구**다: "내가 몇 년 넣고 얼마 벌면 대략 얼마 받나" 를 손에
/// 쥐어 보고, 그 값을 "은퇴 후 소득" 에 **참고값**으로 넣는다 (사용자 결정
/// 09-11 — 모르면 0 을 넣고, 아는 만큼 고친다).
///
/// 공식 (기본연금액, 연):
///
///     비례상수 × (A + B) × (1 + 0.05 × 20년 초과 가입 연수)
///
/// - A: 전체 가입자의 최근 3년 평균 월소득 (연금 수급 직전 재평가). 매년
///   공단이 고시한다.
/// - B: 본인의 가입 기간 평균 월소득 (재평가 뒤). 기준소득월액 상·하한 안.
/// - 비례상수: 가입 연도마다 다르다 — 1988~1998 은 2.4 (소득대체율 70%),
///   1999~2007 은 1.8 (60%), 2008 부터 1.5 에서 해마다 0.015 씩 내려오다
///   2025년 개정으로 **2026년부터 1.29 (43%) 에 고정**됐다. 가입 기간이
///   여러 구간에 걸치면 연수로 가중 평균한다.
///
/// A 도 B 도 오늘 돈으로 재평가한 값이라 결과도 **오늘 돈**이다 — 그래서
/// "은퇴 후 소득" 의 "오늘 돈 기준으로 적으세요" 와 바로 맞는다.
///
/// 금액에 `Double` 을 쓰지 않는다 (ADR-0003). 비례상수는 천분율 정수로 들고
/// 나눗셈은 마지막에 한 번, 은행가 반올림으로 끝낸다.
public enum NationalPension {

    /// 2026년 적용 A값. 공단 고시 참고값 — 해마다 바뀐다.
    public static let referenceAValueMinor = 3_089_062
    /// 기준소득월액 상·하한 (2025.7 ~ 2026.6).
    public static let incomeCeilingMinor = 6_370_000
    public static let incomeFloorMinor = 400_000
    /// 이보다 짧으면 연금이 아니라 반환일시금이다.
    public static let minimumYears = 10
    /// 제도가 시작된 해. 그 전은 가입 기간이 아니다.
    public static let firstSchemeYear = 1988

    public struct Estimate: Sendable, Hashable {
        /// 예상 월 수령액, 오늘 돈 기준.
        public let monthly: Money
        /// 센 가입 연수.
        public let years: Int
        /// 가입 기간에 적용된 평균 소득대체율 (basis point). 2026년 이후만이면 4300.
        public let replacementBP: Int
        /// 상·하한을 적용한 뒤 실제로 쓴 본인 평균 월소득.
        public let incomeUsed: Money
    }

    /// 그 해에 가입한 기간의 비례상수 × 1000.
    public static func constantMilli(forYear year: Int) -> Int {
        switch year {
        case ..<1999: return 2400
        case 1999...2007: return 1800
        case 2008...2025: return 1500 - 15 * (year - 2008)
        default: return 1290
        }
    }

    /// - Parameters:
    ///   - averageMonthlyIncome: 본인의 가입 기간 평균 월소득 (오늘 돈). 상·하한 안으로 자른다.
    ///   - firstYear: 처음 납부한 해. 1988년 전이면 1988 로 본다.
    ///   - lastYear: 마지막으로 납부하는 해 (포함).
    ///   - aValue: A값. 기본은 2026년 고시값.
    /// - Returns: 가입 기간이 10년 미만이거나 연도가 뒤집혔으면 `nil`.
    public static func estimate(averageMonthlyIncome: Money,
                                firstYear: Int, lastYear: Int,
                                aValue: Money = Money(minorUnits: referenceAValueMinor, currency: .krw)) -> Estimate? {
        let first = max(firstYear, firstSchemeYear)
        guard lastYear >= first else { return nil }
        let years = lastYear - first + 1
        guard years >= minimumYears else { return nil }

        let income = min(max(averageMonthlyIncome.minorUnits, incomeFloorMinor), incomeCeilingMinor)
        let sumMilli = (first...lastYear).reduce(0) { $0 + constantMilli(forYear: $1) }
        let months = years * 12
        let extraMonths = max(0, months - 240)

        // 연 기본연금액 = (Σ상수/연수)/1000 × (A + B) × (240 + 초과월수)/240 → 월은 ÷ 12.
        // 0.05 × 초과연수 = 초과월수 / 240 이라 분수 하나로 정확히 떨어진다.
        let numerator = Decimal(sumMilli) * Decimal(aValue.minorUnits + income) * Decimal(240 + extraMonths)
        let denominator = Decimal(1_000 * 240 * 12) * Decimal(years)
        let monthly = Decimals.roundedInt(numerator / denominator, rounding: .bankers)

        // 상수 1.2 가 대체율 40% 이므로 대체율(bp) = 상수(milli) × 10 / 3.
        let replacement = Decimals.roundedInt(Decimal(sumMilli * 10) / (Decimal(3) * Decimal(years)),
                                              rounding: .bankers)

        return Estimate(monthly: Money(minorUnits: monthly, currency: averageMonthlyIncome.currency),
                        years: years, replacementBP: replacement,
                        incomeUsed: Money(minorUnits: income, currency: averageMonthlyIncome.currency))
    }
}
