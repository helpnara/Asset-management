import CoreData
import Foundation

extension Household {

    /// 가구는 **하나뿐이다.** 없으면 만든다.
    ///
    /// `Plan.current(in:)` 과 같은 꼴이다. 여러 개가 생기면 공유가 갈라지므로,
    /// 만드는 자리는 여기 하나로 둔다.
    static func current(in context: NSManagedObjectContext) -> Household {
        if let existing = context.all(Household.self).first {
            return existing
        }
        return Household(context: context)
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
