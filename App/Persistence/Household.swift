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

    /// **새로 만든 것을 빠짐없이 뿌리에 매단다.**
    ///
    /// 저장 직전에 한 번 훑는다. 만드는 자리마다 손으로 매다는 방법도 있지만,
    /// 그건 **한 곳만 빠뜨려도 조용히 실패한다** — 그 계좌는 화면에 잘 보이고
    /// 상대 기기에서만 안 보인다. 만드는 자리는 스물세 곳이고 앞으로 더 는다.
    ///
    /// 그래서 "만들 때" 가 아니라 **"저장할 때"** 를 잡는다. 저장을 거치지 않고
    /// 디스크에 남는 길은 없으므로, 여기가 유일하게 새는 곳이 없는 자리다.
    static func attachNew(in context: NSManagedObjectContext) {
        let orphans = context.insertedObjects.filter { object in
            object is Household ? false : object.value(forKey: "household") == nil
        }
        guard !orphans.isEmpty else { return }

        let household = current(in: context)
        for object in orphans {
            object.setValue(household, forKey: "household")
        }
    }
}
