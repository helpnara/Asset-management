import CoreData
import Foundation

extension Household {

    /// 가구는 **하나뿐이다.** 없으면 만든다.
    ///
    /// `Plan.current(in:)` 과 같은 꼴이다. 여러 개가 생기면 공유가 갈라지므로,
    /// 만드는 자리는 여기 하나로 둔다.
    static func current(in context: NSManagedObjectContext) -> Household {
        // **정렬해서 고른다.** 정렬 없는 `.first` 는 순서를 보장하지 않는다.
        // 가구가 둘이 되는 일은 없어야 하지만(iCloud 로 다른 기기의 것이
        // 내려오거나, 공유로 존이 옮겨 갈 때 생길 수 있다), 만약 둘이 되면
        // **부르는 자리마다 다른 것을 골라** 화면과 공유가 서로 다른 가구를
        // 보게 된다. 그런 어긋남은 화면에 티가 안 난다.
        //
        // 가장 오래된 것이 진짜다 — 나중 것이 뒤늦게 내려온 사본이다.
        let sorted = context.all(Household.self,
                                 sortedBy: [NSSortDescriptor(key: "createdAt", ascending: true)])
        if let existing = sorted.first {
            return existing
        }
        return Household(context: context)
    }

    /// 지금 저장소에 있는 가구 수. **하나여야 한다.**
    ///
    /// 화면에 내놓는 이유는, 둘이 되면 공유가 엉뚱한 가구에 붙는데 그것이
    /// 다른 어떤 자리에서도 안 보이기 때문이다.
    static func count(in context: NSManagedObjectContext) -> Int {
        context.all(Household.self).count
    }

    /// **참가자 기기의 가구를 하나로 만든다.** 치운 가구 수를 돌려준다.
    ///
    /// 초대를 받아들이는 순서가 문제다. 링크를 누르면 앱이 먼저 뜨고, 첫
    /// 화면이 계획을 만들고, 저장이 그 계획을 새 가구에 매단다 — 공유 존이
    /// 서버에서 내려오기 **전에**. 그래서 참가자 기기에는 늘 가구가 둘이
    /// 된다: 관리자의 것(공유 저장소)과 빈 껍데기(개인 저장소).
    ///
    /// 둘인 채로 두면 무엇이 나쁜가. `Plan` 이 둘이라 계획 화면이 어느 것을
    /// 보여 줄지 정해지지 않고, `current(in:)` 은 가장 오래된 것을 고르지만
    /// 화면은 `plans.first` 를 읽는다. 빈 계획이 걸리면 아내분 화면의 계획·궤적이
    /// 비어 보인다 — 합격 기준 3번이 그것이다.
    ///
    /// **치우는 조건은 셋 다여야 한다:** 공유 저장소에 **계획까지 내려온**
    /// 가구가 있고(참가자다), 이 가구는 개인 저장소에 있고, 계획 말고는 매달린
    /// 것이 하나도 없다. 관리자 기기에서는 첫 조건이 거짓이라 아무것도 안 한다.
    /// 참가자가 그 사이에 무언가를 적었다면 세 번째 조건이 막는다 — 기록은 안
    /// 지운다.
    ///
    /// 첫 조건에 "계획까지" 를 붙인 이유. 공유 존은 레코드가 나눠 내려온다 —
    /// 가구는 왔는데 계획이 아직이면, 빈 껍데기를 치운 직후 화면이
    /// `Plan.current` 로 계획을 **새로 만들고**, 저장이 그것을 공유 가구에
    /// 매단다. 보기 전용 참가자의 그 쓰기는 서버가 거부하고, 기기에는 계획이
    /// 둘 남는다. 관리자의 계획이 내려온 뒤에만 치우면 그 일이 없다.
    static func pruneEmptyLocalDuplicates(in context: NSManagedObjectContext,
                                          sharedStoreURL: URL) -> Int {
        let households = context.all(Household.self,
                                     sortedBy: [NSSortDescriptor(key: "createdAt", ascending: true)])
        guard households.count > 1 else { return 0 }

        func isShared(_ household: Household) -> Bool {
            household.objectID.persistentStore?.url == sharedStoreURL
        }
        guard households.contains(where: { isShared($0) && ($0.plans?.count ?? 0) > 0 })
        else { return 0 }

        var pruned = 0
        for household in households where !isShared(household) && blockers(of: household).isEmpty {
            for plan in (household.plans as? Set<Plan>) ?? [] {
                context.delete(plan)
            }
            for log in (household.changeLogs as? Set<ChangeLog>) ?? [] {
                context.delete(log)
            }
            context.delete(household)
            pruned += 1
        }
        return pruned
    }

    /// 앱이 스스로 만드는 것. 이것만 매달려 있으면 빈 껍데기다.
    /// 계획은 첫 화면이 만들고, 변경 기록은 그 계획을 만들면서 남는다.
    static let selfMadeKinds: Set<String> = ["plans", "changeLogs"]

    /// 이 가구를 빈 껍데기로 볼 수 없게 하는 것들 — `"members 2"` 꼴.
    ///
    /// 관계 이름을 손으로 적지 않는다. 열다섯 개인데 하나 빠뜨리면 그 종류의
    /// 기록이 든 가구를 빈 것으로 보고 지운다. 참가자 기기에서 빈 가구가 안
    /// 치워질 때 **무엇이 막는지** 화면에 적으려고 목록으로 돌려준다.
    static func blockers(of household: Household) -> [String] {
        household.entity.relationshipsByName
            .filter { $0.value.isToMany && !selfMadeKinds.contains($0.key) }
            .compactMap { key, _ in
                let count = (household.value(forKey: key) as? NSSet)?.count ?? 0
                return count > 0 ? "\(key) \(count)" : nil
            }
            .sorted()
    }

    /// 개인 저장소에 남은 가구가 왜 안 치워지는지. 없으면 `nil`.
    static func pruneBlockers(in context: NSManagedObjectContext, sharedStoreURL: URL) -> String? {
        let households = context.all(Household.self,
                                     sortedBy: [NSSortDescriptor(key: "createdAt", ascending: true)])
        guard households.count > 1 else { return nil }
        let local = households.filter { $0.objectID.persistentStore?.url != sharedStoreURL }
        let reasons = local.flatMap(blockers(of:))
        return reasons.isEmpty ? nil : reasons.joined(separator: ", ")
    }

    /// **새로 만든 것을 빠짐없이 뿌리에 매단다.**
    ///
    /// 저장 직전에 한 번 훑는다. 만드는 자리마다 손으로 매다는 방법도 있지만,
    /// 그건 **한 곳만 빠뜨려도 조용히 실패한다** — 그 계좌는 화면에 잘 보이고
    /// 상대 기기에서만 안 보인다. 만드는 자리는 스물세 곳이고 앞으로 더 는다.
    ///
    /// 그래서 "만들 때" 가 아니라 **"저장할 때"** 를 잡는다. 저장을 거치지 않고
    /// 디스크에 남는 길은 없으므로, 여기가 유일하게 새는 곳이 없는 자리다.
    static func attachNew(in context: NSManagedObjectContext) {
        // `household` 관계가 없는 엔티티(목실감 일기)는 **일부러** 안 매단다 —
        // 개인 저장소에만 남아 공유 존으로 안 가게. `value(forKey:)` 로 없는 키를
        // 읽으면 죽으므로 관계 유무를 먼저 본다.
        let familyObjects = context.insertedObjects.filter { object in
            !(object is Household) && object.entity.relationshipsByName["household"] != nil
        }
        guard !familyObjects.isEmpty else { return }

        let household = current(in: context)
        for object in familyObjects where object.value(forKey: "household") == nil {
            object.setValue(household, forKey: "household")
        }

        // **가구가 사는 저장소에 넣는다** (docs/09-family-sharing.md ④). 참가자
        // 기기에는 저장소가 둘(개인·공유)인데, 배정하지 않으면 Core Data 가
        // 첫 번째(개인)에 넣는다. 그러면 관계는 공유 저장소의 가구를 가리키는데
        // 기록은 개인 iCloud 로 올라가 "동기화 성공" 인 채 상대에게 영영 안 간다 —
        // 아내분이 만든 계좌가 그렇게 아빠 폰에 안 왔다.
        if let store = household.objectID.persistentStore {
            for object in familyObjects where object.objectID.isTemporaryID {
                context.assign(object, to: store)
            }
        }
    }
}
