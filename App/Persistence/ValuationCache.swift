import Core
import CoreData
import Foundation

/// **가족 전체 자산을 한 번만 굴린다** (docs/08-feedback.md 157번).
///
/// `Valuation.rollUp` 은 종목마다 `position()` 을 만들고(계좌 · 소유자 관계를
/// 타고 들어간다) 통화별로 합친다. 값싸 보이지만 **화면이 그려질 때마다**,
/// 그것도 한 화면에서 **여러 번** 불리고 있었다 — 현황판의 `rollup` 은 계산
/// 프로퍼티라 본문에서 참조하는 곳마다 처음부터 다시 굴렸고, 그런 자리가
/// 열여덟 군데였다. 스크롤 한 번에 열여덟 번이다.
///
/// 그래서 **자료가 바뀔 때까지는 같은 결과를 돌려준다.**
///
/// **무엇이 "바뀌었다" 인가.** Core Data 의 변경 알림을 세대 번호로 센다.
/// 어떤 컨텍스트든(체험 자료의 메모리 저장소, iCloud 가 밀어 넣는 배경
/// 컨텍스트 포함) 무엇이든 바뀌면 세대가 올라가고 곳간이 비워진다 —
/// **덜 비우는 것보다 더 비우는 쪽이 안전하다.** 곳간이 틀린 숫자를 들고
/// 있는 것이 이 앱에서 가장 나쁜 고장이다.
///
/// 종목 수 · 평가액 합계 · 소속 계좌도 열쇠에 같이 넣는다. 알림이 한 박자
/// 늦게 오더라도 여기서 걸린다 — 정수 덧셈 한 바퀴는 관계를 타고 들어가
/// 통화별로 합치는 것보다 훨씬 싸다.
@MainActor
final class ValuationCache {

    static let shared = ValuationCache()

    private var generation = 0
    private var observer: NSObjectProtocol?

    /// 곳간을 다시 쓸 수 있는지 가르는 열쇠.
    private struct Key: Equatable {
        var count = 0
        var sum = 0
        var owners = 0
    }

    private var cachedGeneration = -1
    private var cachedKey = Key(count: -1, sum: -1, owners: 0)
    private var cached: Rollup?

    private init() {}

    /// 앱이 뜰 때 한 번 건다 (`Autosave.start` 바로 옆).
    ///
    /// **어느 컨텍스트인지 묻지 않는다** (`object: nil`). 체험 자료는 따로 만든
    /// 메모리 컨텍스트를 쓰므로, 하나에만 매달면 체험 중에는 곳간이 영영 안
    /// 비워진다.
    func start() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // **자산이 바뀔 때만 비운다** (163번). 처음에는 어떤 변경이든 비웠는데,
            // 계획 수익률 한 칸을 고쳐도 가족 자산을 통째로 다시 굴렸다.
            // 알림에 실린 객체의 엔티티만 본다 — `objectID` 는 어느 스레드에서
            // 읽어도 되고, 관리 객체 자체는 건드리지 않는다.
            guard Self.touchesFamilyAssets(note) else { return }
            MainActor.assumeIsolated { self?.generation &+= 1 }
        }
    }

    /// 종목 · 계좌 · 구성원 — `position()` 이 타고 들어가는 셋.
    nonisolated private static let assetEntities: Set<String> = ["Holding", "Account", "Member"]

    nonisolated private static func touchesFamilyAssets(_ note: Notification) -> Bool {
        // 통째로 무효화됐으면(저장소 교체 · 체험 모드 전환) 무조건 비운다.
        if note.userInfo?[NSInvalidatedAllObjectsKey] != nil { return true }
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey,
                    NSRefreshedObjectsKey, NSInvalidatedObjectsKey]
        for key in keys {
            guard let objects = note.userInfo?[key] as? Set<NSManagedObject> else { continue }
            for object in objects where assetEntities.contains(object.objectID.entity.name ?? "") {
                return true
            }
        }
        return false
    }

    /// **가족 전체의 종목**을 굴린 결과. 일부만 추려 넣지 않는다 — 열쇠가
    /// 개수와 합계뿐이라 같은 크기의 다른 묶음을 구분하지 못한다.
    func familyRollUp(_ holdings: [Holding]) -> Rollup {
        // **옮긴 것도 잡는다.** 종목을 다른 계좌로 옮기면 평가액 합계는 그대로인데
        // 구성원별 · 계좌별 비중이 달라진다. 계좌 객체의 주소를 섞어 두면
        // 그 경우도 열쇠가 달라진다 — UUID 를 해시하는 것보다 싸고, 어차피
        // `position()` 이 같은 관계를 타고 들어간다.
        var key = Key()
        for holding in holdings {
            key.count += 1
            key.sum = key.sum &+ holding.valueMinor
            key.owners = key.owners &+ (holding.account.map { ObjectIdentifier($0).hashValue } ?? 0)
        }
        if let cached, generation == cachedGeneration, key == cachedKey {
            return cached
        }
        let value = Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw)
        cached = value
        cachedGeneration = generation
        cachedKey = key
        return value
    }
}
