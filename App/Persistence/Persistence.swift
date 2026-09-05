import Foundation
import SwiftData

enum Persistence {
    /// 호출할 때마다 새로 만든다.
    ///
    /// `Schema` 는 `Sendable` 이 아니라서 `static let` 으로 두면 Swift 6 동시성 검사에
    /// 걸린다("static property is not concurrency-safe"). 계산 프로퍼티는 매번 새 인스턴스를
    /// 돌려주므로 공유 가변 상태가 아니다.
    static var schema: Schema {
        Schema([Member.self, Account.self, Holding.self, ReviewSession.self, Snapshot.self, SnapshotLine.self])
    }

    /// 지금은 기기 로컬 전용이다.
    ///
    /// CloudKit 동기화(ADR-0001)는 Apple Developer 계정이 생기면 켠다 —
    /// `ModelConfiguration(..., cloudKitDatabase: .private("iCloud.com.helpnara.slowrich"))`.
    /// 스키마는 이미 CloudKit 제약을 지키고 있어서 플래그만 바꾸면 된다.
    static let container: ModelContainer = makeContainer()

    /// 실행 인자 `-seedSampleData` 가 있으면 인메모리 저장소에 가상 데이터를 채운다.
    /// CI 스크린샷이 빈 화면만 찍지 않게 하려는 것이며, 릴리즈 빌드에는 들어가지 않는다.
    static func makeContainer() -> ModelContainer {
        let schema = Persistence.schema
        let wantsSample = ProcessInfo.processInfo.arguments.contains("-seedSampleData")
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: wantsSample)

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            #if DEBUG
            if wantsSample {
                SampleData.seed(into: ModelContext(container))
            }
            #endif
            return container
        } catch {
            fatalError("데이터 저장소를 열지 못했습니다: \(error)")
        }
    }
}
