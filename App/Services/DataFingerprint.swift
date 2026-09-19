import CoreData
import CryptoKit
import Foundation

/// **두 기기의 자료가 어디서 갈리는지 숫자로 보는 도구** (docs/08-feedback.md 165번).
///
/// 2026-09-19, 아이폰에서 고친 계획 제목이 아이패드에 안 왔다. 기대수익률은
/// 오는데 제목은 안 오고, 동기화 화면은 "마지막 내보내기: 성공" 이었다.
/// 코드를 아무리 읽어도 **어느 기록이 어디까지 갔는지**는 알 수 없었다 —
/// 그건 두 기기의 저장소를 나란히 놓고 봐야 아는 것이다.
///
/// 그래서 저장소를 **지문**으로 줄인다. 엔티티마다 모든 속성을 정렬해 한 줄로
/// 적고, 줄들을 정렬해 해시한다. 두 기기의 지문이 같으면 그 엔티티는 같은
/// 것이고, 다르면 거기가 갈린 자리다. **금액은 밖으로 안 나간다** — 해시뿐이다.
///
/// 정렬을 두 번 하는 이유: 기기마다 저장 순서가 다르다. 속성을 이름순으로,
/// 기록을 글자순으로 세워야 같은 자료가 같은 지문이 된다. 날짜는 UTC ISO 로
/// 적는다 — 시간대가 다른 기기끼리도 같아야 하므로.
@MainActor
enum DataFingerprint {

    struct Row {
        let entity: String
        let count: Int
        /// 이 엔티티에서 가장 늦은 시각 (`updatedAt` → `createdAt` → `at` … 순으로 찾는다).
        let latest: Date?
        let digest: String
    }

    /// 저장소 전체를 엔티티별 지문으로.
    @MainActor
    static func rows(in context: NSManagedObjectContext) -> [Row] {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else { return [] }
        let entities = model.entities.sorted { ($0.name ?? "") < ($1.name ?? "") }
        return entities.compactMap { entity in
            guard let name = entity.name else { return nil }
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.returnsObjectsAsFaults = false
            let objects = (try? context.fetch(request)) ?? []
            let keys = attributeKeys(of: entity)
            let stampKey = ["updatedAt", "createdAt", "at", "day", "weekAnchor"]
                .first { entity.attributesByName[$0] != nil }

            var lines: [String] = []
            var latest: Date?
            for object in objects {
                lines.append(line(of: object, keys: keys))
                if let stampKey, let stamp = object.value(forKey: stampKey) as? Date,
                   latest.map({ stamp > $0 }) ?? true {
                    latest = stamp
                }
            }
            lines.sort()
            return Row(entity: name, count: objects.count, latest: latest,
                       digest: digest(lines.joined(separator: "\n")))
        }
    }

    /// 계획 하나를 **필드 묶음별** 지문으로. "계획이 다르다" 에서 "은퇴 이후
    /// 묶음이 다르다" 까지 좁혀 준다. 시각은 해시하지 않고 그대로 적는다 —
    /// 금액이 아니고, 어느 쪽이 더 새 것인지 보는 데 필요하다.
    @MainActor
    static func planGroups(_ plan: NSManagedObject) -> [(group: String, digest: String)] {
        let groups: [(String, [String])] = [
            ("문서 글귀", ["title", "asOfNote", "declaration"]),
            ("기간", ["startYear", "retirementYear", "horizonYear", "startedOn"]),
            ("적립", ["monthlyContributionMinor", "contributionGrowthBP",
                     "usesMemberContributions", "contributionOrderRaw"]),
            ("수익률", ["annualReturnBP", "postRetirementReturnBP", "inflationBP",
                       "lowYieldReturnBP", "realEstateReturnBP", "bondReturnBP", "commodityReturnBP"]),
            ("은퇴 이후", ["monthlySpendingMinor", "annualHobbyMinor", "annualMedicalMinor",
                         "targetAmountMinor", "targetIsAuto"]),
            ("진단 기준", ["withdrawalRateBP", "monthlyIncomeMinor", "savingsFloorBP", "illiquidCapBP",
                         "usTargetBP", "mixToleranceBP", "driftToleranceBP", "driftRelativeBP",
                         "disabledDiagnosesRaw"]),
        ]
        let known = plan.entity.attributesByName
        return groups.map { name, keys in
            // 모델에 없는 키를 `value(forKey:)` 로 읽으면 죽는다. 있는 것만.
            let present = keys.filter { known[$0] != nil }
            let joined = present.map { "\($0)=\(text(plan.value(forKey: $0)))" }.joined(separator: "|")
            return (name, digest(joined))
        }
    }

    // MARK: - 재료

    private static func attributeKeys(of entity: NSEntityDescription) -> [String] {
        entity.attributesByName
            .filter { key, attribute in
                // 이진 · 변환 속성(옮김 영수증 같은 것)은 기기마다 다를 수 있고 뜻도 없다.
                attribute.attributeType != .binaryDataAttributeType
                    && attribute.attributeType != .transformableAttributeType
            }
            .keys.sorted()
    }

    private static func line(of object: NSManagedObject, keys: [String]) -> String {
        keys.map { "\($0)=\(text(object.value(forKey: $0)))" }.joined(separator: "|")
    }

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func text(_ value: Any?) -> String {
        switch value {
        case nil: return "∅"
        case let date as Date: return iso.string(from: date)
        case let uuid as UUID: return uuid.uuidString
        case let number as NSNumber: return number.stringValue
        case let string as String: return string
        default: return String(describing: value ?? "∅")
        }
    }

    /// 짧게 자른 SHA-256. 여덟 자리면 우연히 겹칠 일이 없고 눈으로 견줄 수 있다.
    static func digest(_ string: String) -> String {
        let hash = SHA256.hash(data: Data(string.utf8))
        return hash.prefix(4).map { String(format: "%02x", $0) }.joined()
    }
}
