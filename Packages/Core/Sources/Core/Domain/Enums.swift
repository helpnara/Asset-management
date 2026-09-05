import Foundation

/// 세적. 미국 세적자는 한국 상장 ETF가 PFIC로 분류되어 세금이 징벌적이므로
/// 상품 선택에 제약이 걸린다 (docs/reference/one-pager-analysis.md).
public enum TaxResidency: String, Codable, Sendable, CaseIterable, Identifiable {
    case korea
    case usa
    case both

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .korea: return "한국"
        case .usa: return "미국"
        case .both: return "한국 · 미국"
        }
    }

    /// PFIC 규제를 받는가. 미국 납세 의무가 있으면 받는다.
    public var isSubjectToPFIC: Bool { self != .korea }
}

public enum AccountKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case general            // 일반 위탁
    case isa
    case pensionSavings     // 연금저축
    case irp
    case retirementPension  // 퇴직연금
    case insurance          // 연금보험 — 해지환급금 기준
    case deposit            // 예적금 · 현금
    case leaseDeposit       // 전세보증금
    case realEstate
    case loan               // 부채
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .general: return "일반 위탁"
        case .isa: return "ISA"
        case .pensionSavings: return "연금저축"
        case .irp: return "IRP"
        case .retirementPension: return "퇴직연금"
        case .insurance: return "연금보험"
        case .deposit: return "예적금 · 현금"
        case .leaseDeposit: return "전세보증금"
        case .realEstate: return "부동산"
        case .loan: return "대출"
        case .other: return "기타"
        }
    }

    /// 부채 계좌인가. 총자산에서 빼야 한다.
    public var isLiability: Bool { self == .loan }

    /// 투자자산으로 셀 것인가.
    ///
    /// 전세보증금·부동산은 자산이지만 "투자자산 합계"에서는 빼고 센다.
    /// 1페이지가 투자자산과 총자산을 나눠 적는 것과 같은 이유다.
    public var countsAsInvestable: Bool {
        switch self {
        case .leaseDeposit, .realEstate, .loan: return false
        default: return true
        }
    }

    /// 연간 납입 한도가 있는 계좌인가 (한도 게이지 표시 대상).
    public var hasContributionLimit: Bool {
        switch self {
        case .isa, .pensionSavings, .irp: return true
        default: return false
        }
    }
}

public enum AssetClass: String, Codable, Sendable, CaseIterable, Identifiable {
    case cash
    case deposit
    case equity        // 주식 · ETF
    case bond
    case crypto
    case realEstate
    case insurance
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cash: return "현금"
        case .deposit: return "예적금"
        case .equity: return "주식 · ETF"
        case .bond: return "채권"
        case .crypto: return "암호화폐"
        case .realEstate: return "부동산"
        case .insurance: return "보험"
        case .other: return "기타"
        }
    }
}

public enum InstrumentType: String, Codable, Sendable, CaseIterable, Identifiable {
    case stock
    case etf
    case fund
    case bond
    case cash
    case physical
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .stock: return "개별주"
        case .etf: return "ETF"
        case .fund: return "펀드"
        case .bond: return "채권"
        case .cash: return "현금성"
        case .physical: return "실물"
        case .other: return "기타"
        }
    }
}

/// 보유 상태. 1페이지의 `동결` · `적립 25만` · `신규` 배지를 그대로 옮긴 것.
public enum HoldingStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case accumulating   // 적립중
    case frozen         // 동결 — 신규 자금 0원
    case new            // 신규 — 아직 매수 전
    case closed         // 정리 완료

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .accumulating: return "적립중"
        case .frozen: return "동결"
        case .new: return "신규"
        case .closed: return "정리 완료"
        }
    }
}

/// 주간 점검에서 얼마나 자주 물어볼 것인가.
/// 매주 물어보는 항목을 최소로 유지하는 것이 3분 안에 끝내는 조건이다 (ADR-0005).
public enum EntryCadence: String, Codable, Sendable, CaseIterable, Identifiable {
    case weekly     // 매주
    case monthly    // 월 1회 — 연금보험 해지환급금 등
    case fixed      // 고정 — 전세보증금처럼 잘 안 바뀌는 것. 점검에서 건너뛴다

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .weekly: return "매주"
        case .monthly: return "월 1회"
        case .fixed: return "고정"
        }
    }
}
