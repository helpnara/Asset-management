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
    case receivable         // 받을 돈 — 지인에게 빌려준 돈. `loan` 의 거울상이다
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
        case .receivable: return "받을 돈"
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
        case .leaseDeposit, .realEstate, .loan, .receivable: return false
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

/// 이 돈이 어떤 속도로 자라는가.
///
/// 예전에는 **순자산 전액**을 계획의 기대수익률(연 8%)로 굴렸다. 그래서
/// 전세보증금 2억이 23년 뒤 궤적에서 11.8억이 됐다 — 실제로는 2억 그대로인
/// 돈인데도 그랬다 (docs/08-feedback.md 11번).
///
/// 인출 순서도 이 프로필이 정한다. 생활비는 **투자자산에서 먼저** 꺼낸다.
/// 전세보증금은 꺼내 쓸 수 있는 돈이 아니므로 마지막이다.
public enum ReturnProfile: String, Codable, Sendable, CaseIterable, Identifiable {
    /// 계획의 기대수익률로 굴린다. 적립과 목돈이 들어오는 곳도 여기다.
    case investment
    /// 이자는 붙지만 투자 수익률과는 다른 세계. 예적금·연금보험.
    case lowYield
    case realEstate
    /// 명목 그대로. 전세보증금·받을 돈처럼 자라지 않는 돈.
    case fixed

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .investment: return "투자자산"
        case .lowYield: return "저수익"
        case .realEstate: return "부동산"
        case .fixed: return "고정"
        }
    }

    /// 인출할 때 먼저 꺼내는 순서. 작을수록 먼저다.
    public var drawdownOrder: Int {
        switch self {
        case .investment: return 0
        case .lowYield: return 1
        case .realEstate: return 2
        case .fixed: return 3
        }
    }
}

public extension AccountKind {
    /// 이 계좌의 돈이 자라는 속도. 계좌마다 따로 적으면 그 값이 이긴다.
    var returnProfile: ReturnProfile {
        switch self {
        case .general, .isa, .pensionSavings, .irp, .retirementPension, .other:
            return .investment
        case .insurance, .deposit:
            return .lowYield
        case .realEstate:
            return .realEstate
        case .leaseDeposit, .receivable, .loan:
            return .fixed
        }
    }

    /// 주간 점검에서 얼마나 자주 물어볼 것인가의 기본값.
    ///
    /// 새 계좌가 무조건 `매주` 라서 전세보증금까지 매주 물어봤다.
    /// 종류를 고르면 주기가 따라오게 하고, 필요하면 사람이 바꾼다.
    var defaultCadence: EntryCadence {
        switch self {
        case .leaseDeposit, .realEstate, .loan, .receivable: return .fixed
        case .insurance: return .monthly
        default: return .weekly
        }
    }
}

public enum AssetClass: String, Codable, Sendable, CaseIterable, Identifiable {
    case cash
    case deposit
    case equity        // 주식 · ETF
    case bond
    case crypto
    /// 금 · 원자재. 금통장이 여기 들어간다 — `other` 에 두면 배분 도넛에서
    /// "기타" 로 뭉개진다 (docs/08-feedback.md 7번).
    case commodity
    case realEstate
    /// 전세보증금. `realEstate` 에 섞으면 "집을 얼마나 갖고 있나" 와
    /// "돌려받을 보증금이 얼마인가" 가 한 칸이 된다 — 성격이 다른 돈이다
    /// (docs/08-feedback.md 14번).
    case leaseDeposit
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
        case .commodity: return "금 · 원자재"
        case .realEstate: return "부동산"
        case .leaseDeposit: return "전세보증금"
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
