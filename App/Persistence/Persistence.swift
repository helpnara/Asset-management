import CoreData
import Foundation

enum Persistence {

    /// iCloud 컨테이너. Apple Developer 계정에서 같은 이름으로 만들어 둬야 한다
    /// (docs/06-testflight.md). 번들 ID 앞에 `iCloud.` 를 붙인 것이 관례다.
    static let cloudKitContainerID = "iCloud.com.helpnara.slowrich"

    /// 컴파일된 모델 이름. `App/SlowRich.xcdatamodeld` 가 `SlowRich.momd` 가 된다.
    static let modelName = "SlowRich"

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

    struct Store {
        let container: NSPersistentContainer
        let mode: Mode
    }

    /// **SwiftData 가 쓰던 그 파일이다.** 여기가 이 이전에서 제일 위험한 한 줄이다
    /// (docs/09-family-sharing.md 1단계, 걸린 것 2번).
    ///
    /// SwiftData 는 경로를 안 주면 `Application Support/default.store` 를 쓴다.
    /// `NSPersistentContainer` 는 기본값이 `<이름>.sqlite` 라, 그대로 두면 **빈
    /// 저장소를 새로 만든다.** 앱은 멀쩡히 뜨고 화면만 비는데, 사용자에게는
    /// 몇 달치 기록이 날아간 것으로 보인다.
    ///
    /// **같은 파일만 열면 그대로 읽힌다.** CI 탐침이 확인했다 — 판본 해시
    /// 15/15, 마이그레이션 없이 열렸고 값과 관계까지 읽혔다. 탐침 자체는
    /// SwiftData 로 저장소를 만들어야 해서 이 커밋에서 지웠고, **그 답이
    /// 남은 자리가 여기다.**
    static var storeURL: URL {
        let directory = URL.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("default.store")
    }

    /// **모델은 한 번만 만든다.**
    ///
    /// 두 가지 때문이다.
    ///
    /// 하나, `NSPersistentContainer(name:)` 은 부를 때마다 모델을 새로 만든다.
    /// 이 파일은 iCloud 로 한 번, 실패하면 로컬로 한 번 부르므로 한 프로세스에
    /// 모델이 둘 올라가고, Core Data 가 이렇게 경고한다:
    ///
    ///     Multiple NSEntityDescriptions claim the NSManagedObject subclass
    ///     'Account' so +entity is unreliable
    ///
    /// 이 저장소는 **조용히 틀린 값**으로 이미 두 번 데었다. 경고로 두지 않는다.
    ///
    /// 둘, CloudKit 이 요구하는 기본값을 여기서 심는다 — `ModelDefaults` 에
    /// 왜 파일이 아니라 코드로 심는지 적어 두었다.
    static var managedObjectModel: NSManagedObjectModel { modelBox.model }

    /// `NSManagedObjectModel` 은 `Sendable` 이 아니라 `static let` 으로 못 둔다:
    ///
    ///     static property 'managedObjectModel' is not concurrency-safe because
    ///     non-'Sendable' type 'NSManagedObjectModel' may have shared mutable state
    ///
    /// 그런데 이 모델은 **만든 뒤로 아무도 안 고친다.** `ModelDefaults.fill` 은
    /// 저장소 코디네이터가 가져가기 전에 한 번만 돌고, 그 뒤로는 읽기 전용이다.
    /// 모델 하나를 여러 컨테이너가 나눠 쓰는 것은 Core Data 가 권하는 쓰임이다.
    ///
    /// 그래서 검사를 끄는 대신(`@preconcurrency` 는 안 쓴다 — CLAUDE.md),
    /// **안전한 이유를 아는 상자**에 담아 건넨다. 상자는 이 파일 밖으로 안 나간다.
    private struct ModelBox: @unchecked Sendable {
        let model: NSManagedObjectModel
    }

    private static let modelBox: ModelBox = {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "momd"),
              let compiled = NSManagedObjectModel(contentsOf: url) else {
            fatalError("\(modelName).momd 를 찾지 못했습니다")
        }
        // 파일에서 읽은 것은 못 고친다. 옮겨 담고 나서 심는다.
        let model = ModelDefaults.editableCopy(of: compiled)
        ModelDefaults.fill(model)
        return ModelBox(model: model)
    }()

    static let shared: Store = open()

    static var container: NSPersistentContainer { shared.container }
    static var viewContext: NSManagedObjectContext { shared.container.viewContext }

    /// 공유받은 자료가 들어가는 저장소. iCloud 모드가 아니면 `nil`.
    ///
    /// 초대를 수락할 때 **어느 저장소로 들여올지** 를 이걸로 가리킨다.
    /// 개인 저장소를 가리키면 남의 기록이 내 것에 섞인다.
    static var sharedStore: NSPersistentStore? {
        shared.container.persistentStoreCoordinator.persistentStores
            .first { $0.url == sharedStoreURL }
    }
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
        // CI 스크린샷은 인메모리다. 여기에 iCloud 를 붙이면 안 된다.
        if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
            let container = NSPersistentContainer(name: modelName,
                                                  managedObjectModel: managedObjectModel)
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
            var failure: Error?
            container.loadPersistentStores { _, error in failure = error }
            if let failure { fatalError("인메모리 저장소를 열지 못했습니다: \(failure)") }
            configure(container.viewContext)
            #if DEBUG
            SampleData.seed(into: container.viewContext)
            #endif
            return Store(container: container, mode: .inMemory)
        }

        // CI 는 `CODE_SIGNING_ALLOWED=NO` 로 빌드해서 entitlement 가 붙지 않는다.
        // 아래 fallback 이 그 경우도 받아내지만, 스크린샷이 예외 처리 방식에
        // 기대게 두고 싶지 않아 실행 인자로 명시적으로 끈다.
        if ProcessInfo.processInfo.arguments.contains("-localStoreOnly") {
            if let container = try? load(cloudKit: false) {
                return Store(container: container, mode: .localOnly(reason: "-localStoreOnly"))
            }
        }

        do {
            return Store(container: try load(cloudKit: true), mode: .cloudKit)
        } catch {
            // **여기서 한 번 더 물어본다.** 아래 탐침이 답하는 것은
            // "내 설정이 틀렸나, 아니면 이 파일이 문제인가" 다.
            let reason = describe(error) + "\n\n" + probeWithEmptyStore()
            do {
                return Store(container: try load(cloudKit: false),
                             mode: .localOnly(reason: reason))
            } catch {
                fatalError("데이터 저장소를 열지 못했습니다: \(error)")
            }
        }
    }

    /// 오류를 **읽을 수 있게** 편다.
    ///
    /// `String(describing:)` 은 `Error Domain=... Code=...` 한 줄로 뭉개서
    /// 정작 필요한 `NSLocalizedFailureReason` 이 안 보인다. CloudKit 통합이
    /// 거절할 때 진짜 이유는 거기 들어 있다.
    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var lines = ["\(ns.domain) \(ns.code)"]
        for key in [NSLocalizedFailureReasonErrorKey,
                    NSLocalizedDescriptionKey,
                    NSDebugDescriptionErrorKey] {
            if let value = ns.userInfo[key] as? String, !value.isEmpty {
                lines.append(value)
            }
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("바탕: \(underlying.domain) \(underlying.code) "
                         + (underlying.localizedFailureReason ?? underlying.localizedDescription))
        }
        return lines.joined(separator: "\n")
    }

    /// **빈 저장소로는 붙나?** — 원인을 둘로 가르는 탐침.
    ///
    /// iCloud 로 못 열었을 때 답이 갈리는 곳은 딱 여기다:
    ///
    ///  · 빈 파일로도 실패한다 → 자격·컨테이너·모델 쪽 문제다.
    ///    저장소 파일은 죄가 없다.
    ///  · 빈 파일로는 열린다 → **SwiftData 가 쓰던 그 파일**이 문제다.
    ///    미러링 메타데이터가 안 맞는 것이므로, 옮겨 담는 길로 가야 한다.
    ///
    /// 맥이 없어 디버거를 못 붙이는 이 저장소에서, 한 번의 배포로 이 갈림길을
    /// 넘는 유일한 방법이다 (판본 해시 탐침과 같은 수법).
    ///
    /// **안전한가.** 임시 파일은 비어 있으므로 iCloud 로 **밀어 넣을 것이
    /// 없다.** 미러링은 로컬이 비었다고 원격을 지우지 않는다. 읽고 나서
    /// 파일을 지운다. 그리고 이 길은 **이미 실패한 뒤에만** 지나간다.
    private static func probeWithEmptyStore() -> String {
        // **한 번 죽으면 다시 안 지나간다.**
        //
        // `loadPersistentStores` 는 조건에 따라 Error 가 아니라 ObjC 예외를
        // 던지는데, Swift 는 그걸 못 잡는다. 그러면 앱이 뜨자마자 죽고
        // 사용자는 앱을 **아예 못 연다** — 이유를 모르는 것보다 훨씬 나쁘다.
        //
        // 그래서 지나가기 전에 표식을 남기고 무사히 끝나면 지운다. 표식이
        // 남아 있으면 지난번에 여기서 죽었다는 뜻이므로 건너뛴다. 최악의
        // 경우가 "앱을 못 씀" 에서 "한 번 죽고 두 번째부터는 됨" 이 된다.
        //
        // (첫 시도가 예외 대신 Error 를 돌려줬으니 같은 설정인 이 탐침도
        // 그럴 것이다. 그래도 그 판단에 앱의 실행 여부를 걸지는 않는다.)
        let marker = URL.applicationSupportDirectory
            .appendingPathComponent("cloudkit-probe.running")
        if FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: marker)
            return "빈 저장소 탐침은 건너뛰었습니다 — 지난번에 이 자리에서 앱이 죽었습니다."
        }
        FileManager.default.createFile(atPath: marker.path(percentEncoded: false),
                                       contents: nil)
        defer { try? FileManager.default.removeItem(at: marker) }

        let url = URL.temporaryDirectory
            .appendingPathComponent("cloudkit-probe-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(
                    at: URL(fileURLWithPath: url.path(percentEncoded: false) + suffix))
            }
        }

        let container = NSPersistentCloudKitContainer(name: modelName,
                                                      managedObjectModel: managedObjectModel)
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions =
            NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber,
                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]

        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure {
            return "빈 저장소로도 iCloud 를 못 붙였습니다 — 파일 탓이 아닙니다:\n"
                + describe(failure)
        }
        return "빈 저장소로는 붙습니다 — 쓰던 파일 쪽 문제입니다."
    }

    /// 참가자 쪽 자료가 사는 파일. **개인 저장소와 따로 둔다.**
    ///
    /// CloudKit 은 private 과 shared 를 다른 데이터베이스로 본다. Core Data 는
    /// 그 둘을 **저장소 두 개**로 받으며, 한 파일에 섞을 수 없다.
    static var sharedStoreURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("shared.store")
    }

    private static func load(cloudKit: Bool) throws -> NSPersistentContainer {
        let container: NSPersistentContainer = cloudKit
            ? NSPersistentCloudKitContainer(name: modelName,
                                            managedObjectModel: managedObjectModel)
            : NSPersistentContainer(name: modelName,
                                    managedObjectModel: managedObjectModel)

        let description = NSPersistentStoreDescription(url: storeURL)
        if cloudKit {
            description.cloudKitContainerOptions =
                NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
        }
        // **미러링이 요구한다.** 둘 다 없으면 `NSPersistentCloudKitContainer` 가
        // 아예 안 뜬다.
        description.setOption(true as NSNumber,
                              forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber,
                              forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]

        // **공유받은 자료가 들어올 자리** (docs/09-family-sharing.md 2b).
        //
        // 아내분 기기에서는 여기가 본체가 된다 — 초대를 수락하면 가구가 통째로
        // 이 저장소로 들어온다. 아빠 기기에서는 비어 있다.
        //
        // **아빠 기기에도 연다.** 안 열면 참가자가 고친 것이 안 내려오고,
        // 그때 화면에는 아무 표시도 안 난다. 비어 있는 저장소를 여는 값은
        // 거의 없지만, 없어서 못 받는 값은 "아내가 적은 것이 아빠 화면에
        // 안 나타남" 이다.
        if cloudKit {
            let shared = NSPersistentStoreDescription(url: sharedStoreURL)
            let options =
                NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
            options.databaseScope = .shared
            shared.cloudKitContainerOptions = options
            shared.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            shared.setOption(true as NSNumber,
                             forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            container.persistentStoreDescriptions.append(shared)
        }

        // **블록이 저장소마다 한 번씩 불린다.** 하나만 실패해도 잡는다 —
        // 공유 저장소가 조용히 안 열리면 참가자 자료가 통째로 안 보인다.
        var failure: Error?
        container.loadPersistentStores { _, error in
            if failure == nil { failure = error }
        }
        if let failure { throw failure }

        configure(container.viewContext)
        return container
    }

    /// **바깥에서 온 변경을 자동으로 받아들인다.** iCloud 로 내려온 값이
    /// 화면에 반영되려면 이게 있어야 한다. 충돌은 **저장소 쪽 값**을 택한다 —
    /// 다른 기기에서 이미 확정된 값을 이 기기의 낡은 값으로 덮지 않는다.
    private static func configure(_ context: NSManagedObjectContext) {
        context.automaticallyMergesChangesFromParent = true
        // 전역 `var NSMergeByPropertyStoreTrumpMergePolicy` 는 Swift 6 에서
        // "not concurrency-safe" 로 막힌다. 같은 정책을 값으로 만든다.
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyStoreTrumpMergePolicyType)
    }
}
