import CoreData
import Foundation

/// **새 판이 나왔는지 알고, 업데이트로 보낸다** (143번).
///
/// 서버가 없고 외부 요청도 안 하므로(ADR-0005) "최신 빌드가 몇인가" 를 물을 곳이
/// 없다. 대신 가족이 같은 가구를 나눠 쓰는 것을 쓴다 — **가구에 가장 높은 빌드
/// 번호를 적어 둔다.** 한 기기가 새 판을 깔고 뜨면 그 번호가 iCloud 로 퍼지고,
/// 아직 옛 판인 기기는 자기 번호가 더 낮은 것을 보고 띠를 띄운다.
///
/// 이 앱에서 판이 다르면 무엇이 나쁜가. 새 판이 더한 칸(스키마)을 옛 판은
/// 모르니 화면에 값이 안 보이고, 옛 판이 같은 기록을 고치면 새 칸이 비어 간다.
/// 그래서 "언젠가 업데이트" 가 아니라 **업데이트 뒤 사용** 으로 안내한다.
///
/// 빌드 번호는 TestFlight 실행 번호와 같아 늘 커진다(06 문서). App Store 판도
/// 같은 번호 줄을 쓴다.
enum AppUpdate {

    /// 이 기기가 쓰는 빌드. 못 읽으면 0 — 그때는 적지도 견주지도 않는다.
    static var currentBuild: Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// TestFlight 로 깐 판인가. 영수증 파일 이름으로 안다 — 시뮬레이터 · 개발
    /// 빌드는 영수증이 없어 거짓이 되고, 그때는 App Store 쪽 주소로 간다.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    /// App Store 에 오른 뒤 App Store Connect 의 **Apple ID**(숫자)를 적는다.
    /// 비어 있으면 TestFlight 앱을 연다 — 1.0 은 가족 넷이 TestFlight 로 쓴다.
    static let appStoreID = ""

    /// 업데이트 버튼이 여는 곳. TestFlight 판이면 TestFlight 앱(거기서 `업데이트`
    /// 한 번), App Store 판이면 앱 페이지.
    static var updateURL: URL? {
        if isTestFlight || appStoreID.isEmpty {
            return URL(string: "itms-beta://")
        }
        return URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)")
    }

    /// 가구에 적힌 가장 높은 빌드. 가구가 없으면 0.
    static func latestKnownBuild(in context: NSManagedObjectContext) -> Int {
        context.all(Household.self).map(\.latestBuild).max() ?? 0
    }

    /// 이 기기의 빌드가 가구에 적힌 것보다 높으면 올려 적는다. 저장은 자동 저장이
    /// 한다. **가구를 만들지는 않는다** — 참가자 폰의 첫 실행에서 빈 가구를 하나
    /// 더 만들면 안 된다(`Household.pruneEmptyLocalDuplicates`).
    ///
    /// 부르는 쪽이 역할을 본다: 보기 전용 참가자는 부르지 않는다 — 서버가 그
    /// 쓰기를 거부하고 내보내기가 계속 실패한 채 남는다.
    static func record(in context: NSManagedObjectContext) {
        let build = currentBuild
        guard build > 0 else { return }
        for household in context.all(Household.self) where household.latestBuild < build {
            household.latestBuild = build
        }
    }

    // MARK: - 한 번만 묻기

    /// 어느 빌드까지 알림창을 띄웠나. 띠는 늘 보이고, 창은 새 빌드마다 한 번.
    static let alertedBuildKey = "update.alertedBuild"

    static func shouldAlert(for newer: Int) -> Bool {
        UserDefaults.standard.integer(forKey: alertedBuildKey) < newer
    }

    static func markAlerted(_ newer: Int) {
        UserDefaults.standard.set(newer, forKey: alertedBuildKey)
    }
}
