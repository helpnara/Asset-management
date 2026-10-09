// **옛 판으로 만든 저장소를 지금 앱의 모델만 가지고 연다** (docs/18-stage5-foundation.md 5-3).
//
//     swiftc -O -parse-as-library App/Persistence/ModelDefaults.swift \
//            Tools/coredata/check-migration.swift -o /tmp/checkmigration
//     /tmp/checkmigration <지금 앱>.app/SlowRich.momd <옛 판 1>/SlowRich.momd [<옛 판 2> …]
//
// **무엇을 확인하나.** 모델(`.xcdatamodeld`)에는 판이 하나뿐이고, 칸을 더할 때마다 그 한 판을
// 고쳐 왔다. 교과서대로라면 경량 마이그레이션은 옛 판 모델이 앱 안에 있어야 하는데, 가족 폰은
// 한 번도 안 죽었다. 가장 그럴듯한 설명은 SQLite 저장소가 마지막으로 쓴 모델의 사본을 파일 안에
// 들고 있고, 옛 판이 없으면 그것을 원본으로 쓴다는 것이다. 이 검사기는 그 설명을 **실제로 시험한다**.
// 실행 파일 옆에는 옛 판 모델이 없다 — 열린다면 저장소 안의 사본으로 옮겼다는 뜻이다.
//
// 앱이 하는 것과 같게 연다 — `ModelDefaults` 를 같이 컴파일해 그대로 부르고, 변경 기록 · 원격
// 변경 알림 옵션을 켜고, 옮기기 설정은 기본값(자동 · 추론)이다. CloudKit 은 붙이지 않는다 —
// 옮기기는 저장소 코디네이터의 일이라 미러링과 상관없다.
import CoreData
import Foundation

@main
struct CheckMigration {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count >= 2 else {
            FileHandle.standardError.write(Data("쓰임: checkmigration <지금>.momd <옛 판>.momd …\n".utf8))
            exit(2)
        }
        let current = model(at: arguments[0])
        var failed = false

        for oldPath in arguments.dropFirst() {
            let old = model(at: oldPath)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("migration-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("SlowRich.sqlite")
            let same = old.entityVersionHashesByName == current.entityVersionHashesByName

            // 1) 옛 판으로 만들고 엔티티마다 세 줄씩 넣는다. 속성은 `ModelDefaults` 가 심은 기본값이다.
            var counts: [String: Int] = [:]
            do {
                let container = try open(url, model: old)
                let context = container.viewContext
                for entity in old.entities where !entity.isAbstract {
                    guard let name = entity.name else { continue }
                    for _ in 0..<3 { _ = NSManagedObject(entity: entity, insertInto: context) }
                    counts[name] = 3
                }
                try context.save()
                let coordinator = container.persistentStoreCoordinator
                for store in coordinator.persistentStores { try coordinator.remove(store) }
            } catch {
                print("❌ \(oldPath): 옛 판으로 저장소를 만들지 못했습니다 — \(describe(error))")
                failed = true
                continue
            }

            // 2) 지금 모델만으로 연다. 줄 수가 그대로여야 한다.
            do {
                let container = try open(url, model: current)
                let context = container.viewContext
                var problems: [String] = []
                for (name, expected) in counts.sorted(by: { $0.key < $1.key }) {
                    guard current.entitiesByName[name] != nil else {
                        problems.append("\(name): 지금 모델에 없다")
                        continue
                    }
                    let found = try context.count(for: NSFetchRequest<NSManagedObject>(entityName: name))
                    if found != expected { problems.append("\(name): \(expected) → \(found)") }
                }
                if problems.isEmpty {
                    let note = same ? "판이 같아 옮길 것 없음" : "옛 판 모델 없이 옮김"
                    print("✅ \(oldPath) → 지금 모델 (\(note)): 엔티티 \(counts.count)개, 줄 수 그대로")
                } else {
                    print("❌ \(oldPath): 열렸지만 줄 수가 다르다 — " + problems.joined(separator: " · "))
                    failed = true
                }
            } catch {
                print("❌ \(oldPath): 지금 모델로 저장소를 못 열었다 — \(describe(error))")
                print("   판을 쌓아야만 한다는 뜻이다. docs/18 의 5-3 결과로 방향을 다시 정한다.")
                failed = true
            }
            try? FileManager.default.removeItem(at: directory)
        }
        exit(failed ? 1 : 0)
    }

    /// 앱처럼 옮겨 담고 기본값을 심는다.
    static func model(at path: String) -> NSManagedObjectModel {
        guard let compiled = NSManagedObjectModel(contentsOf: URL(fileURLWithPath: path)) else {
            FileHandle.standardError.write(Data("모델을 열지 못했습니다: \(path)\n".utf8))
            exit(2)
        }
        let model = ModelDefaults.editableCopy(of: compiled)
        _ = ModelDefaults.fill(model)
        return model
    }

    static func open(_ url: URL, model: NSManagedObjectModel) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "SlowRich", managedObjectModel: model)
        let description = NSPersistentStoreDescription(url: url)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in
            if failure == nil { failure = error }
        }
        if let failure { throw failure }
        return container
    }

    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        var parts = ["\(ns.domain) \(ns.code)"]
        if let reason = ns.localizedFailureReason { parts.append(reason) }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("밑: \(underlying.domain) \(underlying.code)")
        }
        return parts.joined(separator: " · ")
    }
}
