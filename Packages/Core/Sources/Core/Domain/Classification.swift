import Foundation

/// **계좌 종류 → 자산군 → 상품 종류**의 관련 있는 조합 (docs/08-feedback.md 50번).
///
/// 종목을 적을 때 자산군과 상품 종류의 선택지가 전부 나와서, 전월세보증금
/// 계좌에서 `주식 · ETF` 를 고를 수 있었다. 현금·예적금·전월세보증금·받을 돈은
/// 상품 종류가 사실상 `현금성` 하나다. 그래서 **계좌가 자산군을 좁히고,
/// 자산군이 상품 종류를 좁힌다.** 각 목록의 **첫 항목이 기본값**이다.
///
/// 좁히기만 하고 막지는 않는다. 이미 저장된 값이 목록에 없으면 화면은 그
/// 값을 목록에 남긴다 — 계좌 종류를 나중에 바꿔도 종목이 빈 칸이 되지 않는다.
public extension AccountKind {

    /// 이 계좌에 들어갈 수 있는 자산군. 앞이 기본값.
    var allowedAssetClasses: [AssetClass] {
        switch self {
        case .general:
            return [.equity, .bond, .cash, .commodity, .crypto, .other]
        case .isa, .irp, .retirementPension:
            // 예금형 ISA · IRP 정기예금이 있다.
            return [.equity, .bond, .deposit, .cash, .other]
        case .pensionSavings:
            return [.equity, .bond, .cash, .other]
        case .insurance:
            return [.insurance]
        case .deposit:
            return [.deposit, .cash]
        case .leaseDeposit:
            return [.leaseDeposit]
        case .realEstate:
            return [.realEstate]
        case .loan:
            // 부채 계좌의 "종목"은 사용액이다. 샘플도 현금으로 적는다.
            return [.cash, .other]
        case .receivable:
            return [.receivable]
        case .other:
            return AssetClass.allCases
        }
    }

    /// 새 종목의 기본 자산군.
    var defaultAssetClass: AssetClass { allowedAssetClasses[0] }
}

public extension AssetClass {
    /// **나눠 담을 것이 없는 자산군** (docs/08-feedback.md 64번). 현금·예적금·
    /// 전월세보증금·받을 돈·보험은 "무엇에 굴리나" 의 물음이 없어 목표 비중을
    /// 세우지 않는다. 계좌의 종목이 전부 이것(또는 상품 종류가 현금성)이면
    /// 그 계좌는 비중을 재지 않는다.
    var isCashLike: Bool {
        switch self {
        case .cash, .deposit, .leaseDeposit, .receivable, .insurance: return true
        default: return false
        }
    }


    /// 이 자산군의 상품 종류. 앞이 기본값.
    var allowedInstrumentTypes: [InstrumentType] {
        switch self {
        case .cash, .deposit, .leaseDeposit, .receivable:
            // 돌려받을 돈·맡긴 돈은 전부 현금성이다.
            return [.cash]
        case .insurance:
            return [.other]
        case .equity:
            return [.stock, .etf, .fund]
        case .bond:
            return [.bond, .etf, .fund]
        case .crypto:
            return [.other, .etf, .fund]
        case .commodity:
            // 금 실물 · 금 ETF · 금통장(기타).
            return [.physical, .etf, .fund, .other]
        case .realEstate:
            // 실물 · 리츠(개별주·ETF·펀드).
            return [.physical, .stock, .etf, .fund, .other]
        case .other:
            return InstrumentType.allCases
        }
    }

    /// 새 종목의 기본 상품 종류.
    var defaultInstrumentType: InstrumentType { allowedInstrumentTypes[0] }
}
