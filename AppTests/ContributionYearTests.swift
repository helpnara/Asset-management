import CoreData
import XCTest
@testable import SlowRich

/// **올해 납입액은 그해 것만 센다** (199번 B2). 해가 바뀌면 지난해 납입은 0 — 값은 지우지 않는다.
@MainActor
final class ContributionYearTests: XCTestCase {

    func testLegacyValueBelongsTo2026() {
        let context = Persistence.makeEmptyContainer().viewContext
        let account = Account(context: context, name: "IRP")
        account.annualContributionMinor = 1_800_000
        // 모델 2판 전에 적은 값은 해가 0 으로 남아 있다.
        XCTAssertEqual(account.annualContributionYear, 0)
        XCTAssertEqual(account.contributedMinor(in: 2026), 1_800_000)
        XCTAssertEqual(account.contributedMinor(in: 2027), 0, "새해에는 지난해 납입을 세지 않는다")
        XCTAssertEqual(account.annualContributionMinor, 1_800_000, "값은 지우지 않는다")
    }

    func testStampedYear() {
        let context = Persistence.makeEmptyContainer().viewContext
        let account = Account(context: context, name: "연금저축")
        account.annualContributionMinor = 500_000
        account.annualContributionYear = 2027
        XCTAssertEqual(account.contributedMinor(in: 2027), 500_000)
        XCTAssertEqual(account.contributedMinor(in: 2028), 0)
        XCTAssertEqual(account.contributedMinor(in: 2026), 0)
    }
}
