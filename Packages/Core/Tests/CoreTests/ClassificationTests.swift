import Foundation
import Testing
@testable import Core

/// 계좌 종류 → 자산군 → 상품 종류 좁히기 (docs/08-feedback.md 50번).
@Suite("Classification — 관련 있는 선택지만")
struct ClassificationTests {

    @Test("모든 계좌 종류에 자산군이 하나는 있다 — 빈 목록이면 기본값이 없다")
    func everyAccountKindHasAssetClasses() {
        for kind in AccountKind.allCases {
            #expect(!kind.allowedAssetClasses.isEmpty, "\(kind)")
            #expect(kind.allowedAssetClasses.contains(kind.defaultAssetClass))
        }
    }

    @Test("모든 자산군에 상품 종류가 하나는 있다")
    func everyAssetClassHasInstrumentTypes() {
        for assetClass in AssetClass.allCases {
            #expect(!assetClass.allowedInstrumentTypes.isEmpty, "\(assetClass)")
            #expect(assetClass.allowedInstrumentTypes.contains(assetClass.defaultInstrumentType))
        }
    }

    @Test("현금 · 예적금 · 전월세보증금 · 받을 돈은 현금성뿐이다")
    func cashLikeClassesAreCashOnly() {
        for assetClass in [AssetClass.cash, .deposit, .leaseDeposit, .receivable] {
            #expect(assetClass.allowedInstrumentTypes == [.cash], "\(assetClass)")
        }
    }

    @Test("전월세보증금 · 부동산 · 받을 돈 · 연금보험 계좌는 자산군이 하나다")
    func singlePurposeAccountsHaveOneAssetClass() {
        #expect(AccountKind.leaseDeposit.allowedAssetClasses == [.leaseDeposit])
        #expect(AccountKind.realEstate.allowedAssetClasses == [.realEstate])
        #expect(AccountKind.receivable.allowedAssetClasses == [.receivable])
        #expect(AccountKind.insurance.allowedAssetClasses == [.insurance])
    }

    @Test("일반 위탁의 기본은 주식 · ETF 이고, 그 기본 상품은 개별주다")
    func brokerageDefaults() {
        #expect(AccountKind.general.defaultAssetClass == .equity)
        #expect(AssetClass.equity.defaultInstrumentType == .stock)
    }

    @Test("목록에 중복이 없다")
    func noDuplicates() {
        for kind in AccountKind.allCases {
            let classes = kind.allowedAssetClasses
            #expect(Set(classes).count == classes.count, "\(kind)")
        }
        for assetClass in AssetClass.allCases {
            let types = assetClass.allowedInstrumentTypes
            #expect(Set(types).count == types.count, "\(assetClass)")
        }
    }
}
