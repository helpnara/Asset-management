import CoreData
import SwiftUI

/// `@Query` 를 대신한다 — **`[T]` 를 그대로 돌려준다** (docs/09-family-sharing.md 1b-2).
///
/// ```swift
/// @Fetched(sort: \Member.sortIndex) private var members: [Member]
/// @Fetched private var holdings: [Holding]
/// ```
///
/// **왜 `@FetchRequest` 를 직접 안 쓰나.** 그러면 타입이 `[Holding]` 에서
/// `FetchedResults<Holding>` 으로 바뀐다. 82곳만 고치면 끝나는 것이 아니라
/// 그 값을 넘겨받는 자리까지 줄줄이 깨진다 — `ReviewScheduling.Input(holdings:)`
/// 처럼 `[Holding]` 을 받는 곳이 곳곳에 있고, 그건 CI 한 바퀴에 한 파일씩
/// 발견하게 된다.
///
/// 겉을 `[T]` 로 두면 **82곳은 이름 한 토큰만 바뀌고 딸린 곳은 안 바뀐다.**
/// 화면이 하나도 안 달라져야 하는 단계에서 이게 맞는 거래다.
///
/// 이름을 `Query` 로 두지 않은 것은 SwiftData 의 것과 헷갈리기 때문이다.
/// 이건 우리 것이고, 하는 일도 그것보다 좁다.
@propertyWrapper
struct Fetched<Result: NSManagedObject>: DynamicProperty {

    @FetchRequest private var results: FetchedResults<Result>

    /// **매번 배열을 새로 만든다.** 이 앱이 다루는 크기(구성원 넷 · 종목 수십)에서는
    /// 값이 싸고, 대신 쓰는 쪽이 `[T]` 라는 사실이 흔들리지 않는다.
    var wrappedValue: [Result] { Array(results) }

    /// 정렬 없이. 예전 `@Query private var plans: [Plan]` 자리다.
    init() {
        _results = FetchRequest(sortDescriptors: [])
    }

    /// 키패스 하나로 정렬. 82곳 중 47곳이 이 꼴이다.
    ///
    /// **키패스에 `& Sendable` 을 적는다.** Swift 6 의 `SortDescriptor` 가
    /// 그것을 요구한다 — 안 적으면
    /// `type 'KeyPath<Result, Value>' does not conform to 'Sendable'` 로 막힌다.
    /// 부르는 쪽은 `\Member.sortIndex` 같은 리터럴이라 그대로 통과한다.
    init<Value>(sort keyPath: KeyPath<Result, Value> & Sendable,
                order: SortOrder = .forward) where Value: Comparable {
        _results = FetchRequest(sortDescriptors: [SortDescriptor(keyPath, order: order)])
    }
}

// MARK: - 코드에서 꺼내 쓰기

extension NSManagedObjectContext {

    /// SwiftData 의 `fetch(FetchDescriptor<T>())` 자리.
    ///
    /// 화면 밖(서비스·백업·알림)에서 꺼내 쓰는 여섯 곳을 위해 둔다.
    /// `NSFetchRequest` 를 그대로 쓰면 세 줄이 되는데, 그 세 줄이 여섯 번
    /// 반복되면 하나를 빠뜨려도 눈에 안 띈다.
    func all<T: NSManagedObject>(_ type: T.Type,
                                 sortedBy sort: [NSSortDescriptor] = [],
                                 predicate: NSPredicate? = nil,
                                 limit: Int? = nil) -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.sortDescriptors = sort
        request.predicate = predicate
        if let limit { request.fetchLimit = limit }
        return (try? fetch(request)) ?? []
    }
}

// MARK: - 지역 바인딩

/// `bindings` 를 **프로토콜로** 준다.
///
/// `extension NSManagedObject { var bindings: ObservedObject<Self>.Wrapper }`
/// 로 두면 컴파일러가 막는다:
///
///     covariant 'Self' or 'Self?' can only appear at the top level of property type
///
/// 클래스 익스텐션의 프로퍼티 타입 **안쪽**에는 `Self` 를 못 쓴다. 프로토콜
/// 익스텐션에서는 된다.
protocol ManagedBindable: NSManagedObject {}

extension NSManagedObject: ManagedBindable {}

extension ManagedBindable {

    /// `@Bindable` 자리 (docs/09-family-sharing.md 1b-2).
    ///
    /// SwiftData 의 `@Model` 은 `Observable` 이라 `@Bindable var plan = plan`
    /// 으로 지역 그림자를 만들고 `$plan.title` 을 쓸 수 있었다. Core Data 의
    /// `NSManagedObject` 는 `Observable` 이 아니라 **`ObservableObject`** 다.
    /// 뷰의 저장 프로퍼티라면 `@ObservedObject` 로 그대로 되지만, **뷰 본문
    /// 안의 지역 변수로는 못 쓴다.**
    ///
    /// 그 여섯 곳을 위해 둔다. `ObservedObject` 의 투영값이 곧 바인딩 묶음이다.
    ///
    /// ```swift
    /// let bind = plan.bindings          // 예전의 `@Bindable var plan = plan`
    /// MoneyField(title: "매월 적립", minorUnits: bind.monthlyContributionMinor)
    /// ```
    var bindings: ObservedObject<Self>.Wrapper {
        ObservedObject(wrappedValue: self).projectedValue
    }
}
