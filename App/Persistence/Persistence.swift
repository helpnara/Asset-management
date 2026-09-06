import Foundation
import SwiftData

enum Persistence {

    /// iCloud 컨테이너. Apple Developer 계정에서 같은 이름으로 만들어 둬야 한다
    /// (docs/06-testflight.md). 번들 ID 앞에 `iCloud.` 를 붙인 것이 관례다.
    static let cloudKitContainerID = "iCloud.com.helpnara.slowrich"

    /// 저장소가 실제로 어떤 모드로 열렸는지.
    ///
    /// "켰다고 생각했는데 사실 안 켜져 있었다"가 이 앱에서 제일 위험한 상태다.
    /// 몇 달치 기록이 동기화되고 있는 줄 알았는데 아니면 되돌릴 방법이 없다.
    /// 그래서 모드를 값으로 들고 다니며 더보기 화면에 그대로 보여 준다.
    enum Mode: Sendable, Equatable {
        case cloudKit
        /// iCloud 를 붙이지 못했다. 자료는 기기에만 있다.
        case localOnly(reason: String)
        /// CI 스크린샷용 인메모리.
        case inMemory
    }

    struct Store: Sendable {
        let container: ModelContainer
        let mode: Mode
    }

    /// `Schema` 는 `Sendable` 이 아니라서 `static let` 으로 두면 Swift 6 동시성 검사에
    /// 걸린다("static property is not concurrency-safe"). 계산 프로퍼티는 매번 새 인스턴스를
    /// 돌려주므로 공유 가변 상태가 아니다.
    static var schema: Schema {
        Schema([Member.self, Account.self, Holding.self, ReviewSession.self, Snapshot.self, SnapshotLine.self, Plan.self, CashEvent.self, IncomeStream.self, UserMilestone.self, TodoItem.self, Scenario.self, Principle.self, ChangeLog.self, AllocationTarget.self])
    }

    static let shared: Store = open()

    static var container: ModelContainer { shared.container }
    static var mode: Mode { shared.mode }

    /// iCloud → 기기 로컬 순으로 시도한다.
    ///
    /// iCloud 로 못 열었다고 앱을 죽이면 안 된다. 자격이 없는 빌드(CI 시뮬레이터는
    /// `CODE_SIGNING_ALLOWED=NO` 라 entitlement 가 아예 안 붙는다)나 컨테이너를
    /// 아직 안 만든 경우가 있고, 그때도 사용자는 기록을 이어 적을 수 있어야 한다.
    ///
    /// 되돌아가도 **자료를 잃지 않는다** — 두 설정 모두 같은 로컬 sqlite 를 쓰고,
    /// iCloud 여부는 그 위에 미러링을 얹느냐 마느냐의 차이다.
    static func open() -> Store {
        let schema = Persistence.schema

        // CI 스크린샷은 인메모리다. 여기에 iCloud 를 붙이면 안 된다.
        if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
                fatalError("인메모리 저장소를 열지 못했습니다")
            }
            #if DEBUG
            SampleData.seed(into: ModelContext(container))
            #endif
            return Store(container: container, mode: .inMemory)
        }

        // CI 는 `CODE_SIGNING_ALLOWED=NO` 로 빌드해서 entitlement 가 붙지 않는다.
        // 아래 fallback 이 그 경우도 받아내지만, 스크린샷이 SwiftData 의 예외
        // 처리 방식에 기대게 두고 싶지 않아 실행 인자로 명시적으로 끈다.
        if ProcessInfo.processInfo.arguments.contains("-localStoreOnly") {
            let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
                return Store(container: container, mode: .localOnly(reason: "-localStoreOnly"))
            }
        }

        do {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            return Store(container: try ModelContainer(for: schema, configurations: [configuration]),
                         mode: .cloudKit)
        } catch {
            let reason = String(describing: error)
            do {
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
                return Store(container: try ModelContainer(for: schema, configurations: [configuration]),
                             mode: .localOnly(reason: reason))
            } catch {
                fatalError("데이터 저장소를 열지 못했습니다: \(error)")
            }
        }
    }
}
