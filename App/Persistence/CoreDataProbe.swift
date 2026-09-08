#if DEBUG
import CoreData
import Foundation
import SwiftData

/// **1b 를 시작해도 되는지 SDK 에 직접 묻는다** (docs/09-family-sharing.md 1단계).
///
/// 4차의 제일 비싼 사고는 이것이다: 저장 계층을 Core Data 로 바꿨는데 우리가
/// 만든 모델이 **SwiftData 가 만들어 둔 저장소와 안 맞는** 경우. 그러면 앱은
/// 멀쩡히 뜨고 화면만 빈다. 사용자는 몇 달치 기록이 날아간 것을 본다.
///
/// 이건 문서를 읽어서는 알 수 없다. Core Data 는 저장소에 **모델 판본 해시**를
/// 적어 두고 열 때 대조하는데, SwiftData 가 `@Model` 에서 만들어 내는 모델에
/// 우리가 모르는 것이 하나라도 더 있으면 해시가 달라진다.
///
/// 그래서 82곳을 손대기 **전에** 물어본다. 이 저장소가 CKShare 를 물었던 것과
/// 같은 방식이다 (`Tools/probe-swiftdata-sharing.sh`) — 심판은 SDK 다.
///
/// ```
/// xcrun simctl launch --console <udid> com.helpnara.slowrich -probeCoreDataStore
/// ```
///
/// **아무것도 안 바꾼다.** 임시 폴더에 저장소를 하나 만들어 보고 지운다.
/// `#if DEBUG` 안에 있으므로 TestFlight 빌드에는 들어가지 않는다.
enum CoreDataProbe {

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-probeCoreDataStore")
    }

    /// 결과를 표준 출력에 찍고 앱을 끝낸다. CI 가 이 줄들을 읽는다.
    static func run() -> Never {
        print("══ Core Data 가 SwiftData 저장소를 열 수 있나 ══")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("coredata-probe-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("default.store")
        defer { try? FileManager.default.removeItem(at: directory) }

        guard writeWithSwiftData(at: storeURL) else { fail("SwiftData 로 저장소를 못 만들었습니다") }
        guard let model = compiledModel() else { fail("번들에서 SlowRich.momd 를 못 읽었습니다") }

        // **어디가 다른지부터 찍는다.** "안 맞는다" 만으로는 고칠 데를 모른다.
        // 저장소는 엔티티마다 판본 해시를 적어 두므로, 우리 모델의 해시와
        // 견주면 **어느 엔티티가 다른지**가 이름으로 나온다.
        compareVersionHashes(storeURL, model: model)

        // **한 번 돌 때 여러 가정을 함께 물어본다.** CI 한 바퀴가 10분이라
        // 가정 하나씩 고쳐 넣으면 하루가 간다. 옵셔널 여부는 판본 해시에
        // 들어가므로, 모델을 불러다 그 값만 바꿔 가며 해시를 다시 세면
        // **어느 규칙이 맞는지**가 한 번에 나온다.
        tryVariants(storeURL)

        // **원본을 그대로 열지 않는다.** 방금 SwiftData 로 연 파일이라 잠겨
        // 있어서, 마이그레이션 시도가 "attempt to write a readonly database" 로
        // 죽는다 — 그건 모델이 안 맞아서가 아니라 파일이 안 열려서다.
        // 사본을 만들어 물어야 답이 깨끗하다.
        guard let copied = copyStore(storeURL) else { fail("저장소 사본을 못 만들었습니다") }

        // **엄격하게 먼저 연다.** 자동 마이그레이션을 켜 두면 모델이 달라도
        // 조용히 옮겨 버려서 "같은가" 라는 질문에 답이 안 나온다.
        switch open(copied, model: model, migrating: false) {
        case .success(let container):
            print("결과: 판본이 **똑같다** — 마이그레이션 없이 열린다")
            report(container)
            print("PROBE-RESULT: IDENTICAL")
            exit(0)
        case .failure(let error):
            print("엄격하게는 못 열었습니다: \(error.localizedDescription)")
        }

        // 안 맞으면 경량 마이그레이션으로 넘어갈 수 있는지 본다. 넘어간다면
        // 1b 는 여전히 갈 수 있고, 대신 첫 실행에 한 번 변환이 일어난다.
        guard let second = copyStore(storeURL) else { fail("저장소 사본을 못 만들었습니다") }
        switch open(second, model: model, migrating: true) {
        case .success(let container):
            print("결과: 판본은 다르지만 **경량 마이그레이션으로 열린다**")
            report(container)
            print("PROBE-RESULT: LIGHTWEIGHT")
            exit(0)
        case .failure(let error):
            print("경량 마이그레이션으로도 못 열었습니다: \(error)")
            print("PROBE-RESULT: INCOMPATIBLE")
            exit(1)
        }
    }

    // MARK: - 단계

    /// SwiftData 로 저장소를 만들고 알아볼 수 있는 값 하나를 적는다.
    private static func writeWithSwiftData(at url: URL) -> Bool {
        do {
            let configuration = ModelConfiguration(schema: Persistence.schema,
                                                   url: url,
                                                   cloudKitDatabase: .none)
            let container = try ModelContainer(for: Persistence.schema,
                                               configurations: [configuration])
            let context = ModelContext(container)
            let member = Member(name: probeName, sortIndex: 7)
            context.insert(member)
            let account = Account(name: "탐침 계좌", owner: member, sortIndex: 1)
            context.insert(account)
            try context.save()
            print("SwiftData 로 적었습니다: 구성원 1 · 계좌 1 (\(url.lastPathComponent))")
            return true
        } catch {
            print("SwiftData 쓰기 실패: \(error)")
            return false
        }
    }

    /// 옵셔널 규칙을 바꿔 가며 어느 것이 저장소와 맞는지 센다.
    ///
    /// 모델은 쓰기 전까지 고칠 수 있고 판본 해시는 그때 다시 계산되므로,
    /// 같은 `.momd` 를 여러 번 불러다 값만 바꾸면 된다.
    private static func tryVariants(_ url: URL) {
        let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite, at: url)
        guard let stored = metadata?[NSStoreModelVersionHashesKey] as? [String: Data] else { return }

        let variants: [(String, (NSAttributeDescription) -> Void)] = [
            ("있는 그대로 (Swift 선언을 따름)", { _ in }),
            ("속성을 전부 옵셔널로", { $0.isOptional = true }),
            ("속성을 전부 필수로", { $0.isOptional = false }),
        ]

        print("── 옵셔널 규칙별로 몇 개가 맞나 ──")
        for (label, mutate) in variants {
            guard let momd = Bundle.main.url(forResource: "SlowRich", withExtension: "momd"),
                  let model = NSManagedObjectModel(contentsOf: momd) else { continue }
            for entity in model.entities {
                for case let attribute as NSAttributeDescription in entity.properties {
                    mutate(attribute)
                }
            }
            let hashes = model.entityVersionHashesByName
            let matched = stored.filter { hashes[$0.key] == $0.value }.count
            print("  \(label): \(matched)/\(stored.count) 맞음")
        }
    }

    /// SQLite 저장소는 `-wal` · `-shm` 을 달고 다닌다. 셋 다 옮겨야 온전한 사본이다.
    private static func copyStore(_ url: URL) -> URL? {
        let directory = url.deletingLastPathComponent()
            .appendingPathComponent("copy-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: url.path + suffix)
                guard FileManager.default.fileExists(atPath: from.path) else { continue }
                try FileManager.default.copyItem(
                    at: from,
                    to: directory.appendingPathComponent(url.lastPathComponent + suffix))
            }
            return directory.appendingPathComponent(url.lastPathComponent)
        } catch {
            print("사본 실패: \(error)")
            return nil
        }
    }

    /// 저장소에 적힌 엔티티별 판본 해시와 우리 모델의 것을 견준다.
    ///
    /// 여기가 이 탐침에서 제일 쓸모 있는 부분이다 — "안 맞는다" 는 이미
    /// 알았고, **어느 엔티티가 왜 다른지**를 알아야 고칠 수 있다.
    private static func compareVersionHashes(_ url: URL, model: NSManagedObjectModel) {
        let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite, at: url)
        guard let stored = metadata?[NSStoreModelVersionHashesKey] as? [String: Data] else {
            print("저장소에서 판본 해시를 못 읽었습니다")
            return
        }
        let ours = model.entityVersionHashesByName

        print("── 엔티티 판본 해시 대조 ──")
        print("  저장소(SwiftData): \(stored.count)개 · 우리 모델: \(ours.count)개")

        let onlyStore = stored.keys.filter { ours[$0] == nil }.sorted()
        let onlyModel = ours.keys.filter { stored[$0] == nil }.sorted()
        if !onlyStore.isEmpty { print("  저장소에만 있는 엔티티: \(onlyStore.joined(separator: ", "))") }
        if !onlyModel.isEmpty { print("  우리 모델에만 있는 엔티티: \(onlyModel.joined(separator: ", "))") }

        var same = 0
        var different: [String] = []
        for (name, hash) in stored.sorted(by: { $0.key < $1.key }) {
            guard let mine = ours[name] else { continue }
            if mine == hash { same += 1 } else { different.append(name) }
        }
        print("  해시가 같은 엔티티: \(same)개")
        if different.isEmpty {
            print("  해시가 다른 엔티티: 없음")
        } else {
            print("  **해시가 다른 엔티티 \(different.count)개**: \(different.joined(separator: ", "))")
        }
    }

    /// 빌드가 만들어 낸 `.momd`. 이것이 1b 에서 쓸 바로 그 모델이다.
    private static func compiledModel() -> NSManagedObjectModel? {
        guard let url = Bundle.main.url(forResource: "SlowRich", withExtension: "momd") else {
            print("번들에 SlowRich.momd 가 없습니다 — XcodeGen 이 모델을 리소스로 잡았을 수 있습니다")
            return nil
        }
        let model = NSManagedObjectModel(contentsOf: url)
        print("모델을 읽었습니다: 엔티티 \(model?.entities.count ?? 0)개")
        return model
    }

    private static func open(_ url: URL, model: NSManagedObjectModel,
                             migrating: Bool) -> Result<NSPersistentContainer, Error> {
        let container = NSPersistentContainer(name: "SlowRich", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldMigrateStoreAutomatically = migrating
        description.shouldInferMappingModelAutomatically = migrating
        container.persistentStoreDescriptions = [description]

        var outcome: Result<NSPersistentContainer, Error> = .failure(ProbeError.didNotFinish)
        container.loadPersistentStores { _, error in
            outcome = error.map { .failure($0) } ?? .success(container)
        }
        return outcome
    }

    /// 정말 **우리가 적은 값**이 읽히는지 본다. 저장소가 열리는 것과 값이
    /// 보이는 것은 다른 이야기다 — 빈 화면은 여기서 갈린다.
    private static func report(_ container: NSPersistentContainer) {
        let context = container.viewContext
        for entity in ["Member", "Account"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            let rows = (try? context.fetch(request)) ?? []
            print("  \(entity): \(rows.count)건")
            if entity == "Member", let name = rows.first?.value(forKey: "name") as? String {
                print("  구성원 이름: \(name) \(name == probeName ? "✓ 우리가 적은 값이다" : "✗ 다르다")")
            }
            if entity == "Account", let owner = rows.first?.value(forKey: "owner") {
                print("  계좌→구성원 관계: 이어져 있다 (\(type(of: owner)))")
            }
        }
    }

    private static let probeName = "탐침-구성원"

    private enum ProbeError: Error { case didNotFinish }

    private static func fail(_ message: String) -> Never {
        print(message)
        print("PROBE-RESULT: ERROR")
        exit(1)
    }
}
#endif
