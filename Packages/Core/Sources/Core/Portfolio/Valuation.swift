import Foundation

/// 평가 계산에 들어가는 단일 보유 항목. 기준 통화로 이미 환산된 상태다.
///
/// SwiftData 모델을 그대로 쓰지 않고 이 값 타입으로 납작하게 만들어 넘긴다.
/// 그래야 계산이 영속 계층을 모르고, 시뮬레이터 없이 테스트된다 (ADR-0002).
public struct Position: Sendable, Hashable {
    public var memberID: UUID
    public var accountID: UUID
    public var assetClass: AssetClass
    public var countryCode: String
    public var value: Money
    public var isLiability: Bool
    public var countsAsInvestable: Bool

    public init(
        memberID: UUID,
        accountID: UUID,
        assetClass: AssetClass,
        countryCode: String,
        value: Money,
        isLiability: Bool,
        countsAsInvestable: Bool
    ) {
        self.memberID = memberID
        self.accountID = accountID
        self.assetClass = assetClass
        self.countryCode = countryCode
        self.value = value
        self.isLiability = isLiability
        self.countsAsInvestable = countsAsInvestable
    }
}

/// 현황판이 필요로 하는 모든 합계.
public struct Rollup: Sendable, Equatable {
    /// 부채를 뺀 자산 합계.
    public var assets: Money
    public var liabilities: Money
    /// 투자자산. 전세보증금·부동산은 빠진다.
    public var investable: Money
    /// 구성원별 순자산 (그 사람의 부채는 음수로 반영).
    public var byMember: [UUID: Money]
    /// 자산군별 — **모든 자산** 기준. 부동산·보증금도 들어간다 (자산 배분 도넛용).
    public var byAssetClass: [AssetClass: Money]
    /// 국가별 — **투자자산만** 기준.
    ///
    /// 전세보증금을 넣으면 분모(투자자산)보다 분자가 커져 비중이 100%를 넘는다.
    /// 1페이지의 `한국 29.8 / 미국 70.2` 도 투자자산 기준이다.
    public var byCountry: [String: Money]

    /// 순자산 = 자산 − 부채. 화면에서 가장 큰 숫자.
    public var netWorth: Money { assets - liabilities }

    /// 투자자산 중 특정 국가의 비중. 투자자산이 0이면 nil.
    public func countryShare(_ code: String) -> Decimal? {
        (byCountry[code] ?? .zero(investable.currency)).share(of: investable)
    }
}

public enum Valuation {

    /// 보유 항목을 현황판이 쓰는 합계로 굴린다.
    ///
    /// 부채는 자산에서 빼고, 투자자산 합계에는 전세보증금·부동산을 넣지 않는다.
    /// 1페이지가 "투자자산 합계"와 "가족 총자산"을 따로 적는 것과 같은 구분이다.
    public static func rollUp(_ positions: [Position], base: CurrencyCode) -> Rollup {
        var assets = Money.zero(base)
        var liabilities = Money.zero(base)
        var investable = Money.zero(base)
        var byMember: [UUID: Money] = [:]
        var byAssetClass: [AssetClass: Money] = [:]
        var byCountry: [String: Money] = [:]

        for position in positions {
            precondition(
                position.value.currency == base,
                "Position은 기준 통화로 환산된 뒤에 넘겨야 합니다: \(position.value.currency) vs \(base)"
            )
            let value = position.value

            if position.isLiability {
                liabilities += value
                // 부채는 구성원 합계에서 음수로 반영한다 — 그 사람의 순자산이므로.
                byMember[position.memberID, default: .zero(base)] -= value
                continue
            }

            assets += value
            byMember[position.memberID, default: .zero(base)] += value
            byAssetClass[position.assetClass, default: .zero(base)] += value

            // 국가 비중은 투자자산에 대해서만 센다. 위 byCountry 주석 참고.
            if position.countsAsInvestable {
                investable += value
                byCountry[position.countryCode, default: .zero(base)] += value
            }
        }

        return Rollup(
            assets: assets,
            liabilities: liabilities,
            investable: investable,
            byMember: byMember,
            byAssetClass: byAssetClass,
            byCountry: byCountry
        )
    }
}
