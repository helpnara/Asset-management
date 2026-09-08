// 컴파일된 모델을 **진짜 Core Data 런타임으로** 열어 CloudKit 규칙을 확인한다.
//
//     swiftc App/Persistence/ModelDefaults.swift \
//            Tools/coredata/check-cloudkit-model.swift -o /tmp/checkmodel
//     /tmp/checkmodel <어떤앱>.app/SlowRich.momd
//
// **왜 파이썬 검사기로는 부족한가.** `check-model-matches-ckdb.py` 는 모델
// *파일*을 읽어서 "기본값 글자가 적혀 있나"를 봤다. 그런데 Core Data 는
// **UUID 속성에서 그 글자를 읽지 않는다.** 파일에는 있고 런타임에는 없다.
// 그래서 파일 검사와 `momc` 를 둘 다 통과한 모델이 기기에서 막혔다:
//
//     CloudKit integration requires that all attributes be optional, or have
//     a default value set. (필수 UUID 16개)
//
// 파일을 아무리 들여다봐도 안 보이는 종류다. **모델을 실제로 만들어서
// `defaultValue` 를 물어보는 것**만이 답한다. 그래서 이 검사기는 리눅스에서
// 못 돌고, macOS 러너에서만 돈다.
//
// 앱이 쓰는 `ModelDefaults.fill` 을 **같이 컴파일해서 그대로 부른다** —
// 검사기가 따로 흉내 내면 둘이 어긋나는 날이 온다.
import CoreData
import Foundation

// **`@main` 인 이유.** `swiftc` 로 파일 둘을 함께 컴파일하면 최상위 코드는
// `main.swift` 에만 올 수 있다. 이 파일은 이름이 하는 일을 말해야 하므로
// 진입점을 명시한다 (`-parse-as-library` 와 짝).
@main
struct CheckCloudKitModel {
    static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 2 else {
            FileHandle.standardError.write(Data("쓰임: checkmodel <경로>/SlowRich.momd\n".utf8))
            exit(2)
        }

        let url = URL(fileURLWithPath: arguments[1])
        guard let compiled = NSManagedObjectModel(contentsOf: url) else {
            FileHandle.standardError.write(Data("모델을 열지 못했습니다: \(url.path)\n".utf8))
            exit(2)
        }

        // 앱이 하는 것과 **똑같이** 옮겨 담고 심는다. 이 두 줄이 앱과 다르면
        // 검사기는 통과하고 기기에서만 죽는다 — 실제로 여기서 한 번 죽었다.
        let model = ModelDefaults.editableCopy(of: compiled)
        let filled = ModelDefaults.fill(model)

        var problems: [String] = []

        // **옮겨 담은 뒤 판본 해시가 그대로인가.**
        //
        // 여기가 어긋나면 사용자의 저장소가 안 열린다 — 앱은 멀쩡히 뜨고
        // 화면만 빈다. 몇 달치 기록이 사라진 것으로 보이는 그 실패다
        // (docs/09-family-sharing.md 1단계, 걸린 것 2번).
        //
        // 해시는 이름·타입·옵셔널에서 나오고 기본값은 안 들어가므로 그대로여야
        // 한다. 그래도 **그 믿음에 사용자의 기록을 걸지 않는다.** 직접 센다.
        let before = compiled.entityVersionHashesByName
        let after = model.entityVersionHashesByName
        for (entity, hash) in before where after[entity] != hash {
            problems.append("\(entity): 옮겨 담으면서 판본 해시가 바뀌었습니다 "
                            + "— 쓰던 저장소가 안 열립니다")
        }
        for entity in after.keys where before[entity] == nil {
            problems.append("\(entity): 옮겨 담은 모델에만 있는 엔티티입니다")
        }
        for entity in before.keys where after[entity] == nil {
            problems.append("\(entity): 옮겨 담으면서 엔티티가 사라졌습니다")
        }

        for entity in model.entities {
            let name = entity.name ?? "?"

            for case let attribute as NSAttributeDescription in entity.properties
            where !attribute.isOptional && attribute.defaultValue == nil {
                problems.append("\(name).\(attribute.name): 필수인데 기본값이 없습니다 "
                                + "(타입 \(attribute.attributeType.rawValue)) — CloudKit 이 막습니다")
            }

            for case let relationship as NSRelationshipDescription in entity.properties {
                if !relationship.isOptional {
                    problems.append("\(name).\(relationship.name): 관계는 전부 옵셔널이어야 합니다")
                }
                if relationship.inverseRelationship == nil {
                    problems.append("\(name).\(relationship.name): 역관계가 없습니다")
                }
                if relationship.isOrdered {
                    problems.append("\(name).\(relationship.name): 순서 있는 관계는 CloudKit 이 못 씁니다")
                }
            }

            if !entity.uniquenessConstraints.isEmpty {
                problems.append("\(name): 유니크 제약은 CloudKit 이 못 씁니다")
            }
        }

        if problems.isEmpty {
            let attributes = model.entities.reduce(0) { $0 + $1.attributesByName.count }
            print("CloudKit 규칙 통과 — 엔티티 \(model.entities.count)개 · 속성 \(attributes)개")
            print("판본 해시 \(before.count)개 그대로 — 쓰던 저장소가 그대로 열립니다")
            print("코드로 기본값을 심은 곳 \(filled.count)개: \(filled.sorted().joined(separator: ", "))")
            exit(0)
        }

        FileHandle.standardError.write(Data("""
        모델이 CloudKit 규칙에 어긋납니다 — 이대로 배포하면 기기에서 동기화가
        붙지 않고, 화면에는 티가 나지 않습니다:

        \(problems.map { "  · \($0)" }.joined(separator: "\n"))

        기본값을 파일(.xcdatamodeld)에 적어도 UUID 같은 타입은 런타임이 안 읽습니다.
        App/Persistence/ModelDefaults.swift 에 타입을 더하세요.

        """.utf8))
        exit(1)

    }
}
