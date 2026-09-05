import Core
import Foundation
import SwiftData

#if DEBUG
/// CI 스크린샷과 미리보기용 가상 데이터.
///
/// **실제 금액·기관명이 아니다.** 저장소에 개인 금융 정보를 커밋하지 않는다는 원칙에 따라
/// 구조만 실제와 같게 두고 숫자는 전부 지어낸 값을 쓴다.
/// 실행 인자 `-seedSampleData` 가 있을 때만 인메모리 저장소에 채운다.
enum SampleData {

    static func seed(into context: ModelContext) {
        let dad = Member(name: "아빠", roleNote: "본인", birthYear: 1984, birthMonth: 3,
                         taxResidency: .korea, colorIndex: 0, sortIndex: 0)
        let mom = Member(name: "엄마", roleNote: "미국 시민권자", birthYear: 1986, birthMonth: 7,
                         taxResidency: .usa, colorIndex: 1, sortIndex: 1)
        let son = Member(name: "아들", roleNote: "2022년생", birthYear: 2022, birthMonth: 5,
                         taxResidency: .usa, colorIndex: 2, sortIndex: 2)
        let daughter = Member(name: "딸", roleNote: "2023년생", birthYear: 2023, birthMonth: 9,
                              taxResidency: .usa, colorIndex: 3, sortIndex: 3)
        [dad, mom, son, daughter].forEach(context.insert)

        // 아빠 — 일반 위탁 · 연금보험 · 전세보증금 · 마이너스통장
        let dadBrokerage = account("종합계좌", "증권사 A", .general, dad, 0, context)
        holding("해외 ETF A", .equity, .etf, "US", .accumulating, .weekly, 48_200_000, dadBrokerage, 0, context)
        holding("해외 ETF B", .equity, .etf, "US", .accumulating, .weekly, 26_400_000, dadBrokerage, 1, context)
        holding("국내 대형주", .equity, .stock, "KR", .frozen, .weekly, 9_100_000, dadBrokerage, 2, context)

        let dadInsurance = account("연금보험", "보험사 B", .insurance, dad, 1, context)
        holding("해지환급금", .insurance, .other, "KR", .accumulating, .monthly, 19_800_000, dadInsurance, 0, context)

        let dadLease = account("전세보증금", "", .leaseDeposit, dad, 2, context)
        holding("보증금", .realEstate, .physical, "KR", .accumulating, .fixed, 100_000_000, dadLease, 0, context)

        let dadLoan = account("마이너스통장", "은행 C", .loan, dad, 3, context)
        holding("사용액", .cash, .cash, "KR", .accumulating, .weekly, 4_500_000, dadLoan, 0, context)

        // 엄마 — 국내 개별주만 (PFIC 회피)
        let momBrokerage = account("일반계좌", "증권사 D", .general, mom, 0, context)
        holding("국내 로봇주", .equity, .stock, "KR", .accumulating, .weekly, 2_000_000, momBrokerage, 0, context)

        // 아들 — 국내 ETF 가 섞여 있어 PFIC 경고가 뜬다
        let sonBrokerage = account("증여계좌", "증권사 D", .general, son, 0, context)
        holding("국내 반도체주", .equity, .stock, "KR", .frozen, .weekly, 24_300_000, sonBrokerage, 0, context)
        holding("해외 ETF A", .equity, .etf, "US", .accumulating, .weekly, 1_750_000, sonBrokerage, 1, context)
        holding("국내 지수 ETF", .equity, .etf, "KR", .frozen, .weekly, 3_100_000, sonBrokerage, 2, context)

        // 딸
        let daughterBrokerage = account("증여계좌", "증권사 D", .general, daughter, 0, context)
        holding("국내 바이오주", .equity, .stock, "KR", .accumulating, .weekly, 5_600_000, daughterBrokerage, 0, context)
        holding("해외 ETF A", .equity, .etf, "US", .accumulating, .weekly, 1_800_000, daughterBrokerage, 1, context)

        seedPastReviews(into: context)
    }

    /// 지난 점검 기록. 연속 기록과 주간 증감이 화면에 실제로 보이게 한다.
    /// 이번 주는 일부러 비워 둬서 "지금 입력" 상태를 확인할 수 있게 한다.
    private static func seedPastReviews(into context: ModelContext) {
        let thisWeek = ReviewWeek.anchor(for: .now)
        let calendar = Calendar.current
        var running = 231_400_000

        for weeksAgo in stride(from: 12, through: 1, by: -1) {
            guard let anchor = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: thisWeek) else { continue }
            let previous = running
            running += 500_000 + weeksAgo * 37_000

            let session = ReviewSession(weekAnchor: anchor, totalCount: 12)
            session.enteredCount = 12
            session.completedAt = anchor
            session.totalValueMinor = running
            session.previousTotalValueMinor = previous
            context.insert(session)

            context.insert(Snapshot(weekAnchor: anchor,
                                    netWorthMinor: running,
                                    investableMinor: running - 100_000_000,
                                    liabilitiesMinor: 4_500_000))
        }
    }

    @discardableResult
    private static func account(_ name: String, _ institution: String, _ kind: AccountKind,
                                _ owner: Member, _ sortIndex: Int,
                                _ context: ModelContext) -> Account {
        let account = Account(name: name, institution: institution, kind: kind,
                              owner: owner, sortIndex: sortIndex)
        context.insert(account)
        return account
    }

    private static func holding(_ name: String, _ assetClass: AssetClass,
                                _ instrumentType: InstrumentType, _ country: String,
                                _ status: HoldingStatus, _ cadence: EntryCadence,
                                _ valueMinor: Int, _ account: Account, _ sortIndex: Int,
                                _ context: ModelContext) {
        let holding = Holding(name: name, assetClass: assetClass, instrumentType: instrumentType,
                              listingCountryCode: country, status: status, cadence: cadence,
                              valueMinor: valueMinor, account: account, sortIndex: sortIndex)
        context.insert(holding)
    }
}
#endif
