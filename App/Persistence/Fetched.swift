import Combine
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

    /// **칸만 바뀐 것도 알린다** (225번). `@FetchRequest` 는 목록에 드나드는 것(추가 · 삭제 · 정렬)에만
    /// 반응하고, 이미 있는 객체의 칸 하나가 바뀐 것은 알리지 않는다 — 종목 편집 시트에서 목표 비중을
    /// 고치고 닫아도 자산 탭의 비중 표기 · `목표 미완` 이 계좌를 접었다 펴야 바뀌었다. 같은 병을
    /// 72번(자산 탭) · 150번(일기 줄) · 빌드 98 8번(진단 기준)에서 화면마다 따로 고쳤다.
    /// 여기서 한 번에 막는다 — 이 엔티티의 객체가 바뀌면(칸 · 들고 남 · iCloud 가 밀어 넣은 것)
    /// 이것을 쓰는 화면이 다시 그려진다.
    @StateObject private var changes: EntityChanges

    /// **매번 배열을 새로 만든다.** 이 앱이 다루는 크기(구성원 넷 · 종목 수십)에서는
    /// 값이 싸고, 대신 쓰는 쪽이 `[T]` 라는 사실이 흔들리지 않는다.
    var wrappedValue: [Result] { Array(results) }

    /// 정렬 없이. 예전 `@Query private var plans: [Plan]` 자리다.
    @MainActor
    init() {
        _results = FetchRequest(fetchRequest: Self.request(sortedBy: []))
        _changes = StateObject(wrappedValue: EntityChanges(entity: Self.entityName))
    }

    /// 키패스 하나로 정렬. 82곳 중 47곳이 이 꼴이다.
    ///
    /// **Swift 의 `SortDescriptor` 를 쓰지 않는다.** 그걸로 만들면 컴파일은
    /// 통과하고 **앱이 뜨자마자 죽는다**:
    ///
    ///     Foundation/SortDescriptor.swift:1215: Fatal error:
    ///     Attempt to convert SortDescriptor with Compared being non-NSObject
    ///
    /// Core Data 가 원하는 것은 `NSSortDescriptor` 이고, 그건 **속성 이름
    /// 문자열**로 만든다. 키패스는 이름을 얻는 데만 쓴다 — 그래야 부르는 쪽이
    /// 오타를 컴파일 때 잡힌다(`\Member.sortIndex`).
    @MainActor
    init<Value>(sort keyPath: KeyPath<Result, Value>,
                order: SortOrder = .forward) where Value: Comparable {
        let name = NSExpression(forKeyPath: keyPath).keyPath
        _results = FetchRequest(fetchRequest: Self.request(
            sortedBy: [NSSortDescriptor(key: name, ascending: order == .forward)]))
        _changes = StateObject(wrappedValue: EntityChanges(entity: Self.entityName))
    }

    /// 엔티티 이름은 클래스 이름과 같다 — 생성기가 그렇게 뽑았다.
    private static var entityName: String { String(describing: Result.self) }

    private static func request(sortedBy descriptors: [NSSortDescriptor]) -> NSFetchRequest<Result> {
        let request = NSFetchRequest<Result>(entityName: entityName)
        request.sortDescriptors = descriptors
        return request
    }
}

// MARK: - 칸 변경 알림 (225번)

/// **한 엔티티의 객체가 바뀌면 세대 번호를 올린다** — `@Fetched` 가 하나씩 들고, 올라가면 그것을 쓰는
/// 화면이 다시 그려진다. Core Data 의 `ObjectsDidChange` 를 본다: 칸만 바뀐 것(`updated`), iCloud 가
/// 밀어 넣어 다시 읽은 것(`refreshed`), 들고 난 것까지. `ValuationCache` 와 같은 알림 · 같은 판정이다.
///
/// **액터에 매지 않는다.** `@MainActor` 클래스 안에서 Combine 닫힘을 만들면 Swift 6 가 그 닫힘을
/// 메인 액터 것으로 여기는데, 알림은 배경 컨텍스트(iCloud 가져오기)에서도 온다 — 거기서 부르면
/// 실행 중에 큐 검사로 죽는다. 판정은 보낸 쪽 스레드에서 하고(`objectID` 는 어느 스레드에서 읽어도
/// 된다), 숫자는 메인 큐로 옮긴 뒤에만 올린다.
final class EntityChanges: ObservableObject {
    @Published private(set) var generation = 0
    private var subscription: AnyCancellable?

    init(entity: String) {
        subscription = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange)
            .filter { @Sendable note in EntityChanges.touches(note, entity: entity) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.generation &+= 1 }
    }

    static func touches(_ note: Notification, entity: String) -> Bool {
        // 통째로 무효화됐으면(저장소 교체 · 체험 모드 전환) 무조건.
        if note.userInfo?[NSInvalidatedAllObjectsKey] != nil { return true }
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey,
                    NSRefreshedObjectsKey, NSInvalidatedObjectsKey]
        for key in keys {
            guard let objects = note.userInfo?[key] as? Set<NSManagedObject> else { continue }
            if objects.contains(where: { $0.objectID.entity.name == entity }) { return true }
        }
        return false
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
    /// **`@MainActor` 다.** `ObservedObject.projectedValue` 가 그렇기 때문이다.
    /// 안 적으면 `sending 'self' risks causing data races` 로 막힌다.
    /// 부르는 곳은 전부 뷰 본문이라 이미 메인 액터다.
    ///
    /// (`@preconcurrency` 로 검사를 끄지 않는다 — CLAUDE.md.)
    @MainActor
    var bindings: ObservedObject<Self>.Wrapper {
        ObservedObject(wrappedValue: self).projectedValue
    }
}
