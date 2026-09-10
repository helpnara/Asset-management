import CloudKit
import CoreData
import SwiftUI
import UIKit

/// `FamilySharing` **밖에** 둔다. 그 클래스는 `@MainActor` 인데
/// `LocalizedError` 의 `errorDescription` 은 격리되지 않은 요구라,
/// 안에 넣으면 준수가 막힌다.
enum FamilySharingFailure: LocalizedError {
    case noCloudKit
    case noShare
    case timedOut

    var errorDescription: String? {
        switch self {
        case .noCloudKit:
            return "iCloud 로 열리지 않아 공유할 수 없습니다. 더보기 → 동기화를 보세요."
        case .noShare:
            return "공유를 만들지 못했습니다."
        case .timedOut:
            return "공유를 만드는 데 너무 오래 걸립니다. 더보기 → 동기화의 "
                + "**마지막 내보내기**가 성공으로 돌아온 뒤 다시 시도하세요."
        }
    }
}

/// 공유가 지금 어떤 상태인가. **값이라 스레드를 넘겨도 안전하다.**
struct FamilyShareState: Sendable {
    var households = 0
    var hasLocalShare = false
    var isSaved = false
    var participants = 0

    /// **이 기기의 진짜 역할.** 공유 저장소에 `CKShare` 가 있으면 참가자고,
    /// 그 공유의 `currentUserParticipant.permission` 이 역할을 정한다
    /// (docs/09-family-sharing.md 4단계). 없으면 소유자다.
    var role: FamilyRole = .owner

    /// 뿌리(가구)에 안 매달린 기록 수. 소유자 기기에서 0 이어야 한다 — 매달리지
    /// 않은 기록은 공유에 안 실려 상대 기기에 안 보인다.
    var orphans = 0

    /// 참가자 기기에서 빈 가구가 안 치워질 때 그 이유 (`"members 2"` 꼴).
    var pruneBlockers: String?

    /// **이 기기의 참가자 ID** — `CKShare` 가 주는 사용자 레코드 이름. 관리자가
    /// `Member.editorIDs` 에 적어 둔 것과 이것을 견줘 편집 범위를 정한다.
    /// 소유자 기기에서는 `nil`.
    var participantID: String?

    /// 소유자 기기가 보는 참가자들 (소유자 본인 제외). 편집 권한 화면의 재료.
    var people: [SharePerson] = []

    /// **참가자 기기의 개인 저장소에 남은 가족 기록** (docs/09 ④). 0 이어야 한다.
    /// 있으면 그 기록은 상대 기기에 안 간다 — 지우고 다시 만들어야 한다.
    var strays = 0

    /// 공유가 아는 **내 이름** (참가자 신원의 이름 구성 요소). 본인 기기에서는
    /// 비어 있을 때가 많아 `ActorName` 이 대신한다 (77번).
    var myName: String?

    /// **공유를 한 번이라도 실제로 읽었나** (76번). 앱을 켠 직후 이 값이
    /// 거짓인 동안은 역할을 모르는 것이지 소유자인 것이 아니다.
    var isResolved = false

    /// **참가자였는데 공유가 없어졌다** (79번). 관리자가 참가자를 빼거나 공유를
    /// 중단하면 이 기기의 공유 저장소에서 `CKShare` 가 사라진다. 마지막 역할은
    /// 지키되(71번) 그 사실은 알려야 한다 — 안 그러면 영영 "참가 중" 이다.
    var shareLost = false

    var isParticipant: Bool { role != .owner }

    /// 사람이 읽을 한 줄.
    var label: String {
        if isParticipant { return "참가 중 · \(role.label)" }
        if households == 0 { return "아직 없음" }
        if !hasLocalShare { return "공유 안 함" }
        if !isSaved { return "만들다 만 상태" }
        return "공유 중 · 참가자 \(participants)명"
    }

    var isTrouble: Bool { households > 1 || (hasLocalShare && !isSaved) || orphans > 0 }
}

/// `CKShare` 참가자 한 사람. 화면에 건네는 값이라 `Sendable` 구조체다.
struct SharePerson: Sendable, Identifiable, Hashable {
    /// 사용자 레코드 이름. 같은 사람은 어느 기기에서 봐도 같다.
    let id: String
    let name: String
    /// `CKShare` 의 권한이 변경 가능인가. 편집 권한 화면이 구성원 체크와 함께 맞춘다.
    let canWrite: Bool
    let accepted: Bool
}

/// **가족 공유.** 가구 하나 = `CKShare` 한 장 (docs/09-family-sharing.md 2b).
///
/// `CKShare` 는 **한 장에 권한이 하나**다. 구성원마다 다른 권한을 주려면 공유를
/// 여러 장 만들어야 하는데, 그러면 자료를 어느 장에 매달지부터 갈라진다.
/// 그래서 **공유는 한 장으로 두고 역할은 앱 안에서 판정한다.**
///
/// ## ⚠️ `share(_:to:)` 를 메인에서 부르면 앱이 죽는다
///
/// 기기 크래시 로그가 알려 줬다:
///
///     FRONTBOARD 0x8BADF00D — scene-update watchdog transgression:
///     exhausted real (wall clock) time allowance of 10.00 seconds
///
///     Thread 0 (com.apple.main-thread):
///       _dispatch_group_wait_slow
///       -[_PFRequestExecutor wait]
///       -[NSPersistentCloudKitContainer shareManagedObjects:toShare:completion:]
///       -[UICloudSharingController __viewControllerWillBePresented:]
///
/// **`share(_:to:)` 는 완료 블록을 받으면서도 부른 스레드를 붙잡고 기다린다.**
/// 그런데 `UICloudSharingController` 는 준비 핸들러를 **메인에서** 부른다.
/// 옮길 레코드가 수백 건이면 10초를 넘고, 워치독이 앱을 죽인다.
///
/// 그래서 여기서는 **백그라운드 컨텍스트에서** 부른다. 관리 객체는 스레드를
/// 넘기지 않고 `objectID` 만 넘겨 그쪽에서 다시 꺼낸다 (CLAUDE.md).
///
/// `fetchShares` 도 같은 실행기를 쓰므로 상태를 읽는 것도 메인에서 안 한다.
@MainActor
@Observable
final class FamilySharing {

    static let shared = FamilySharing()

    /// **공유가 왜 안 됐나.** 시트가 띄우는 알림은 CloudKit 오류 코드를 안
    /// 보여 준다. 그 코드가 없으면 원인을 추측하게 된다.
    var lastFailure: String?

    /// 화면이 읽는 상태. 백그라운드에서 읽어 여기에 얹는다.
    private(set) var state = FamilyShareState()

    /// 기존 기록을 뿌리에 매단 결과. 소유자 기기에서 한 번 보이고 만다.
    var lastAdoption: String?

    /// 마지막으로 판정한 역할. **앱을 켜자마자** 화면이 맞는 역할로 뜨게 한다 —
    /// 공유 조회는 백그라운드라 한 박자 늦는데, 그 사이 참가자 기기에
    /// 편집 버튼이 잠깐 보였다 사라지면 고장으로 읽힌다.
    static let roleKey = "family.resolvedRole"

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.roleKey),
           let role = FamilyRole(rawValue: raw) {
            state.role = role
        }
    }

    /// **뿌리에 안 매달린 기록을 매달고, 공유 존 밖에 남은 기록을 센다.** 옮기지는 않는다.
    ///
    /// 왜 있나. `Household` 는 4차 2a 에 생겼고, `attachNew` 는 **저장할 때
    /// 새로 만든 것**만 매단다. 그 전에 만든 기록은 `household` 가 비어 있었다.
    /// 공유는 뿌리와 관계로 이어진 것만 옮기므로 아내분 폰에는 빈 가구만 갔다
    /// (docs/09-family-sharing.md "2b 에서 막힌 것 ③").
    ///
    /// **옮기기는 여기서 하지 않는다.** 처음엔 자동으로 옮겼는데, 옮기기가
    /// 스키마(`CD_moveReceipt`)에 막혀 반쯤 실패하자 **다른 기기(아이폰)의
    /// 기록이 전부 지워졌다.** 옮기기는 개인 존에서 지우고 공유 존에 새로
    /// 만드는 두 단계라, 뒤가 실패하면 앞의 삭제만 퍼진다. 그래서 옮기기는
    /// 사람이 **백업을 받은 뒤 버튼으로** 한 기기에서만 한다
    /// (`moveUnsharedIntoShare`). 여기서는 매달기와 세기만 한다.
    ///
    /// 엔티티 이름을 손으로 적지 않는다. 모델에서 `household` 관계를 가진
    /// 엔티티를 전부 돈다 — 열다섯 개인데 하나 빠지면 그 종류만 상대 기기에
    /// 조용히 안 보인다.
    nonisolated static func adoptOrphans(in context: NSManagedObjectContext,
                                         container: NSPersistentCloudKitContainer) -> Int {
        let byAge = [NSSortDescriptor(key: "createdAt", ascending: true)]
        guard let household = context.all(Household.self, sortedBy: byAge).first else { return 0 }

        // A. 뿌리에 매단다. 관계를 잇는 것뿐이라 지워지는 것은 없다.
        var adopted = 0
        for entity in householdEntities(of: container) {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.predicate = NSPredicate(format: "household == nil")
            for object in (try? context.fetch(request)) ?? [] {
                object.setValue(household, forKey: "household")
                adopted += 1
            }
        }
        if adopted > 0 {
            do {
                try context.save()
            } catch {
                let text = "기록 \(adopted)건을 뿌리에 매달지 못했습니다\n" + CloudKitErrorText.describe(error)
                Task { @MainActor in FamilySharing.shared.lastAdoption = text }
                return adopted
            }
        }

        // B. 공유가 있으면 **공유 존 밖에 남은 것**을 센다. 옮기는 것은 버튼이다.
        guard let share = try? container.fetchShares(matching: [household.objectID])[household.objectID]
        else { return 0 }
        _ = share
        return unshared(in: context, container: container).count
    }

    /// 참가자 기기의 **개인 저장소**에 있는 가족 기록 수. 가구 자체는 세지
    /// 않는다 (빈 껍데기는 따로 치운다). 0 이 정상이다 (docs/09 ④).
    nonisolated static func strays(in context: NSManagedObjectContext,
                                   container: NSPersistentCloudKitContainer,
                                   sharedStoreURL: URL) -> Int {
        guard let privateStore = container.persistentStoreCoordinator.persistentStores
                .first(where: { $0.url != sharedStoreURL }) else { return 0 }
        var count = 0
        for entity in householdEntities(of: container) {
            let request = NSFetchRequest<NSManagedObject>(entityName: entity)
            request.affectedStores = [privateStore]
            count += (try? context.count(for: request)) ?? 0
        }
        return count
    }

    /// 모델에서 `household` 관계를 가진 엔티티 이름.
    nonisolated static func householdEntities(of container: NSPersistentCloudKitContainer) -> [String] {
        container.managedObjectModel.entities
            .filter { $0.name != "Household" && $0.relationshipsByName["household"] != nil }
            .compactMap(\.name)
    }

    /// 공유 존 밖에 있는 기록. "매달렸는가" 가 아니라 **"공유 존에 있는가"**
    /// (`fetchShares(matching:)`) 로 본다 — 매달림만 보면 첫 실패 뒤 영영 다시
    /// 안 옮긴다.
    nonisolated static func unshared(in context: NSManagedObjectContext,
                                     container: NSPersistentCloudKitContainer) -> [NSManagedObject] {
        var outside: [NSManagedObject] = []
        for entity in householdEntities(of: container) {
            let objects = (try? context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity))) ?? []
            guard !objects.isEmpty else { continue }
            let shares = (try? container.fetchShares(matching: objects.map(\.objectID))) ?? [:]
            outside += objects.filter { shares[$0.objectID] == nil }
        }
        return outside
    }

    /// **공유 존 밖의 기록을 공유 존으로 옮긴다.** 사람이 버튼으로 부른다.
    ///
    /// 옮기기 전에 백업을 받으라고 화면이 먼저 말한다. 옮기기는 개인 존에서
    /// 지우고 공유 존에 새로 만드는 두 단계라, 뒤가 실패하면 다른 기기에는
    /// 삭제만 퍼진다 — 실제로 한 번 그렇게 아이폰 기록이 통째로 사라졌고
    /// 백업으로 되돌렸다 (docs/09-family-sharing.md ③-2).
    func moveUnsharedIntoShare() {
        guard let container = cloudContainer else {
            lastAdoption = "iCloud 로 열리지 않아 옮길 수 없습니다."
            return
        }
        lastAdoption = "공유 존으로 옮기는 중…"
        let carried = UncheckedBox(container)
        DispatchQueue.global(qos: .userInitiated).async {
            let container = carried.value
            let context = container.newBackgroundContext()
            context.perform {
                let byAge = [NSSortDescriptor(key: "createdAt", ascending: true)]
                guard let household = context.all(Household.self, sortedBy: byAge).first,
                      let share = try? container.fetchShares(matching: [household.objectID])[household.objectID]
                else {
                    Task { @MainActor in FamilySharing.shared.lastAdoption = "저장된 공유가 없어 옮길 수 없습니다." }
                    return
                }
                let outside = Self.unshared(in: context, container: container)
                let count = outside.count
                guard count > 0 else {
                    Task { @MainActor in FamilySharing.shared.lastAdoption = "공유 존 밖에 남은 기록이 없습니다." }
                    return
                }
                // 부른 스레드를 붙잡는 호출이라 여기(백그라운드)서만 부른다.
                container.share(outside, to: share) { _, _, _, error in
                    let text = error.map { CloudKitErrorText.describe($0) }
                    Task { @MainActor in
                        let sharing = FamilySharing.shared
                        if let text {
                            sharing.lastAdoption = "기록 \(count)건을 공유 존으로 옮기지 못했습니다\n" + text
                        } else {
                            sharing.lastAdoption = "기록 \(count)건을 공유 존으로 옮겼습니다. "
                                + "상대 기기에 1~2분 뒤 나타납니다."
                        }
                        sharing.refreshState()
                    }
                }
            }
        }
    }

    /// `CKShare` 참가자 정보를 앱의 역할로 옮긴다. 백그라운드에서 부른다.
    nonisolated static func role(of share: CKShare) -> FamilyRole {
        guard let me = share.currentUserParticipant else { return .viewer }
        if me.role == .owner { return .owner }
        return me.permission == .readWrite ? .editor : .viewer
    }

    /// 소유자 본인을 뺀 참가자들. 아직 수락 전이면 사용자 레코드가 없을 수
    /// 있어 그런 사람은 뺀다 — 편집 권한은 수락한 뒤에 준다.
    nonisolated static func people(of share: CKShare) -> [SharePerson] {
        share.participants.compactMap { participant in
            guard participant.role != .owner,
                  let id = participant.userIdentity.userRecordID?.recordName else { return nil }
            let identity = participant.userIdentity
            // 이름을 모르면 ID 꼬리라도 붙인다 — "참가자" 둘이 나란히 서면
            // 누가 누군지 가를 수 없다 (77번).
            let name = identity.nameComponents.map { PersonNameComponentsFormatter().string(from: $0) }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? identity.lookupInfo?.emailAddress
                ?? identity.lookupInfo?.phoneNumber
                ?? "참가자 " + ActorName.idTail(id)
            return SharePerson(id: id, name: name,
                               canWrite: participant.permission == .readWrite,
                               accepted: participant.acceptanceStatus == .accepted)
        }
    }

    /// 편집 권한 화면이 마지막으로 한 일의 결과.
    var lastPermissionResult: String?

    /// **참가자의 `CKShare` 권한을 바꾼다.** 구성원 체크가 하나라도 켜지면
    /// 변경 가능, 전부 꺼지면 보기 전용으로 맞춘다 — 서버 권한이 보기 전용이면
    /// 앱이 아무리 열어 줘도 저장이 튕긴다. 공유 저장은 백그라운드다.
    func setPermission(canWrite: Bool, for personID: String) {
        guard let container = cloudContainer, let store = Persistence.privateStore else {
            lastPermissionResult = "iCloud 로 열리지 않아 권한을 바꿀 수 없습니다."
            return
        }
        let carried = UncheckedBox((container, store))
        DispatchQueue.global(qos: .userInitiated).async {
            let (container, store) = carried.value
            let context = container.newBackgroundContext()
            context.perform {
                let byAge = [NSSortDescriptor(key: "createdAt", ascending: true)]
                guard let household = context.all(Household.self, sortedBy: byAge).first,
                      let share = try? container.fetchShares(matching: [household.objectID])[household.objectID],
                      let participant = share.participants.first(where: {
                          $0.userIdentity.userRecordID?.recordName == personID })
                else {
                    Task { @MainActor in FamilySharing.shared.lastPermissionResult = "공유에서 그 참가자를 찾지 못했습니다." }
                    return
                }
                let wanted: CKShare.ParticipantPermission = canWrite ? .readWrite : .readOnly
                guard participant.permission != wanted else {
                    Task { @MainActor in FamilySharing.shared.refreshState() }
                    return
                }
                participant.permission = wanted
                container.persistUpdatedShare(share, in: store) { _, error in
                    let text = error.map { CloudKitErrorText.describe($0) }
                    Task { @MainActor in
                        let sharing = FamilySharing.shared
                        sharing.lastPermissionResult = text.map { "권한을 바꾸지 못했습니다\n" + $0 }
                            ?? (canWrite ? "변경 가능으로 바꿨습니다. 상대 기기는 앱을 앞으로 가져오면 반영됩니다."
                                         : "보기 전용으로 바꿨습니다.")
                        sharing.refreshState()
                    }
                }
            }
        }
    }

    private var cloudContainer: NSPersistentCloudKitContainer? {
        Persistence.container as? NSPersistentCloudKitContainer
    }

    /// 오류를 **가장 안쪽 이유까지** 펴서 적는다 (`CloudKitErrorText`).
    func record(_ error: Error, while step: String) {
        lastFailure = "\(step)\n" + CloudKitErrorText.describe(error)
    }

    /// **상태를 백그라운드에서 읽는다.**
    ///
    /// `fetchShares` 도 `share(_:to:)` 와 같은 실행기를 쓴다. 더보기 화면을
    /// 여는 것만으로 메인이 멈추면 안 된다.
    func refreshState() {
        guard let container = cloudContainer else {
            state = FamilyShareState()
            return
        }
        let carried = UncheckedBox((container, Persistence.sharedStore))
        let sharedStoreURL = Persistence.sharedStoreURL
        DispatchQueue.global(qos: .userInitiated).async {
            let (container, sharedStore) = carried.value
            let context = container.newBackgroundContext()
            context.perform {
                var next = FamilyShareState()

                // **못 읽었으면 마지막 판정을 지킨다** (docs/08-feedback.md 71번).
                // 예전에는 기본값이 소유자라, 앱을 켠 직후 공유 조회가 한 번
                // 실패하면 참가자 폰의 모든 편집이 잠깐 풀렸다가 다음 조회에서
                // 다시 잠겼다 — 게다가 그 "소유자" 를 저장까지 해서 다음 실행도
                // 풀린 채 시작했다. 역할은 **공유를 실제로 읽었을 때만** 바꾸고
                // 저장한다. 참가자 ID 도 받아 둔 것으로 먼저 채운다.
                let lastRole = UserDefaults.standard.string(forKey: Self.roleKey)
                    .flatMap(FamilyRole.init(rawValue:)) ?? .owner
                next.role = lastRole
                next.participantID = Self.realUserRecordName(nil)

                // **참가자인가.** 공유 저장소에 `CKShare` 가 있으면 그렇다.
                // 소유자의 공유는 개인 저장소에 있어서 여기 안 잡힌다.
                if let sharedStore,
                   let share = (try? container.fetchShares(in: sharedStore))?.first {
                    next.role = Self.role(of: share)
                    next.participantID = Self.realUserRecordName(
                        share.currentUserParticipant?.userIdentity.userRecordID?.recordName)
                    next.myName = share.currentUserParticipant?.userIdentity.nameComponents
                        .map { PersonNameComponentsFormatter().string(from: $0) }
                        .flatMap { $0.isEmpty ? nil : $0 }
                    UserDefaults.standard.set(next.role.rawValue, forKey: Self.roleKey)
                } else if lastRole != .owner {
                    // 참가자로 기억하는데 공유가 없다. 아직 안 내려온 것일 수도
                    // 있어 역할은 그대로 두고, 판단은 화면이 가져오기 완료와
                    // 함께 한다 (79번).
                    next.shareLost = true
                }
                next.isResolved = true

                // 참가자 기기에는 가구가 **하나만** 있어야 한다. 초대를 받기 전에
                // 앱이 제 가구를 만들어 두므로(첫 화면이 계획을 만든다), 받고
                // 나면 빈 껍데기가 하나 남는다. 그걸 여기서 치운다.
                if next.role != .owner {
                    let pruned = Household.pruneEmptyLocalDuplicates(in: context,
                                                                     sharedStoreURL: sharedStoreURL)
                    if pruned > 0 { try? context.save() }
                    next.pruneBlockers = Household.pruneBlockers(in: context, sharedStoreURL: sharedStoreURL)
                    next.strays = Self.strays(in: context, container: container, sharedStoreURL: sharedStoreURL)
                } else {
                    // 소유자 기기: 가구가 생기기 전에 만든 기록을 뿌리에 매단다.
                    // 매달리지 않은 기록은 공유에 안 실린다 (아래 adoptOrphans).
                    next.orphans = Self.adoptOrphans(in: context, container: container)
                }

                let households = (try? context.fetch(Household.fetchRequest())) ?? []
                next.households = households.count
                // 가장 오래된 것이 진짜다 — 나중 것은 뒤늦게 내려온 사본이다.
                if let household = households.min(by: { $0.createdAt < $1.createdAt }),
                   let share = try? container
                       .fetchShares(matching: [household.objectID])[household.objectID] {
                    next.hasLocalShare = true
                    // **`url` 이 있어야 서버에 있는 것이다.** 만들다 만 것과 가른다.
                    next.isSaved = share.url != nil
                    next.participants = share.participants.count
                    next.people = Self.people(of: share)
                }
                let result = next
                Task { @MainActor in
                    FamilySharing.shared.state = result
                    // **소유자도 한 번은 적어 둔다** (76번). 가져오기가 끝났는데도
                    // 공유가 없으면 이 기기는 소유자다 — 다음 실행부터는 확인을
                    // 기다리지 않는다. 참가자는 위에서 공유를 읽을 때 적힌다.
                    if !result.isParticipant, !result.shareLost,
                       CloudKitSyncMonitor.shared.hasFinishedImport,
                       UserDefaults.standard.string(forKey: Self.roleKey) == nil {
                        UserDefaults.standard.set(FamilyRole.owner.rawValue, forKey: Self.roleKey)
                    }
                    // 참가자인데 제 이름을 아직 모르면 서버에 묻는다 (아래 참고).
                    if result.isParticipant && result.participantID == nil {
                        FamilySharing.shared.fetchUserRecordNameIfNeeded()
                    }
                }
            }
        }
    }

    /// **`__defaultOwner__` 는 이름이 아니다.** CloudKit 은 본인 기기에서 본인을
    /// 가리킬 때 실제 사용자 레코드 이름 대신 이 자리표시(`CKCurrentUserDefaultName`)
    /// 를 준다. 참가자 폰이 공유의 `currentUserParticipant` 에서 읽은 것이 그것이라,
    /// 관리자 폰이 `Member.editorIDs` 에 적은 실제 이름(`_…`)과 영영 안 맞았다
    /// (docs/08-feedback.md 62번 — 두 폰의 ID 꼬리가 완전히 달랐다).
    ///
    /// 실제 이름은 `CKContainer.fetchUserRecordID` 가 준다. 한 번 받으면
    /// `UserDefaults` 에 둔다 — 컨테이너 안에서 바뀌지 않는 값이다.
    nonisolated static let userRecordKey = "family.userRecordName"

    nonisolated static func realUserRecordName(_ raw: String?) -> String? {
        if let raw, !raw.isEmpty, raw != CKCurrentUserDefaultName { return raw }
        return UserDefaults.standard.string(forKey: userRecordKey)
    }

    func fetchUserRecordNameIfNeeded() {
        guard UserDefaults.standard.string(forKey: Self.userRecordKey) == nil else { return }
        CKContainer(identifier: Persistence.cloudKitContainerID).fetchUserRecordID { id, error in
            guard let name = id?.recordName, name != CKCurrentUserDefaultName else {
                if let error {
                    let text = "참가자 ID 를 받지 못했습니다\n" + CloudKitErrorText.describe(error)
                    Task { @MainActor in FamilySharing.shared.lastFailure = text }
                }
                return
            }
            UserDefaults.standard.set(name, forKey: Self.userRecordKey)
            Task { @MainActor in FamilySharing.shared.refreshState() }
        }
    }

    /// **초대 시트가 공유를 만들 때 부르는 자리.**
    ///
    /// 애플이 Core Data 용으로 문서화한 길은 `preparationHandler` 다 —
    /// UIKit 이 공유를 만들고 저장까지 맡는다. 우리는 뿌리 객체를 넘기고
    /// 제목만 얹는다. 다만 **부르는 것은 백그라운드에서** 한다 (위 참고).
    func prepareShare(titled title: String,
                      completion: @escaping (CKShare?, CKContainer?, Error?) -> Void) {
        guard let container = cloudContainer else {
            completion(nil, nil, FamilySharingFailure.noCloudKit)
            return
        }

        lastFailure = nil

        // 뿌리가 없으면 만든다. **저장 안 된 객체는 공유할 수 없으므로**
        // 만든 직후 바로 쓴다. 여기까지는 메인이어야 한다 — viewContext 다.
        let household = Household.current(in: Persistence.viewContext)
        Autosave.shared.flush()
        let rootID = household.objectID

        // `completion` 도 `CKShare` 도 컨테이너도 `Sendable` 이 아니다.
        // 안전한 이유를 아는 상자에 담아 건넨다.
        let box = UncheckedBox(completion)
        let carried = UncheckedBox(container)
        let progress = PreparationState()

        // **빈 화면을 영원히 두지 않는다.** 옮길 것이 많으면 오래 걸리므로
        // 넉넉히 두되, 끝내 안 끝나면 늦었다고 말한다.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(90))
            guard !progress.finished else { return }
            progress.finished = true
            self.lastFailure = "공유 만들기: 90초 안에 끝나지 않았습니다.\n"
                + "더보기 → 동기화의 마지막 내보내기가 성공인지 먼저 보세요."
            box.value(nil, nil, FamilySharingFailure.timedOut)
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let container = carried.value
            let context = container.newBackgroundContext()
            context.perform {
                guard let root = try? context.existingObject(with: rootID) else {
                    Self.finish(progress, box, nil, nil, FamilySharingFailure.noShare, title)
                    return
                }
                // 이미 있는 공유는 이어서 쓴다. 만들다 만 것도 여기서 아물어진다.
                let existing = try? container.fetchShares(matching: [rootID])[rootID]
                container.share([root], to: existing) { _, share, ckContainer, error in
                    Self.finish(progress, box, share, ckContainer, error, title)
                }
            }
        }
    }

    /// 결과를 **메인으로 건너가서** 한 번만 넘긴다.
    ///
    /// 시간 초과와 진짜 응답이 둘 다 완료를 부르면 안 된다.
    private nonisolated static func finish(_ progress: PreparationState,
                                           _ box: UncheckedBox<(CKShare?, CKContainer?, Error?) -> Void>,
                                           _ share: CKShare?,
                                           _ container: CKContainer?,
                                           _ error: Error?,
                                           _ title: String) {
        let carried = UncheckedBox((share, container, error))
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard !progress.finished else { return }
                progress.finished = true
                let (share, container, error) = carried.value
                if let error {
                    FamilySharing.shared.record(error, while: "공유 만들기")
                }
                // 상대가 보는 이름. **넘기기 전에** 얹는다.
                if let share {
                    share[CKShare.SystemFieldKey.title] = title
                }
                box.value(share, container, error)
            }
        }
    }

    /// 서버에 저장된 공유. **`state.isSaved` 가 참일 때만 부른다.**
    ///
    /// `fetchShares` 는 메타데이터 조회라 `shareManagedObjects` 처럼 무겁지
    /// 않다 — 앱을 죽인 것은 그쪽이다. 그래도 이미 있다는 것을 알고 부를 때만
    /// 쓴다.
    func savedShare(for household: Household) -> CKShare? {
        guard let cloudContainer,
              let share = try? cloudContainer
                  .fetchShares(matching: [household.objectID])[household.objectID],
              share.url != nil else { return nil }
        return share
    }

    /// **초대를 받아들인다** — 참가자 쪽에서 링크를 눌렀을 때.
    ///
    /// 공유 존을 **공유 저장소**로 들여온다. 개인 저장소를 가리키면 남의
    /// 기록이 내 것에 섞이므로 `Persistence.sharedStore` 여야 한다.
    ///
    /// 이것도 백그라운드에서 부른다. 네트워크 작업이고, 메인을 붙잡는
    /// Core Data 호출에 한 번 데었다 (워치독).
    func accept(_ metadata: CKShare.Metadata) {
        // 소유자가 제 링크를 누르면 서버가 거부한다 (CKError 12, "owner participant
        // tried to accept share"). 서버까지 가지 않고 여기서 말해 준다.
        if metadata.participantRole == .owner {
            lastFailure = "초대 받기: 본인이 만든 공유 링크입니다. 문제없습니다 — "
                + "이 링크는 초대받은 가족의 폰에서 눌러야 합니다."
            return
        }
        guard let container = cloudContainer, let store = Persistence.sharedStore else {
            lastFailure = "초대 받기: iCloud 로 열리지 않아 받을 수 없습니다."
            return
        }
        lastFailure = nil
        let carried = UncheckedBox((container, metadata, store))
        DispatchQueue.global(qos: .userInitiated).async {
            let (container, metadata, store) = carried.value
            container.acceptShareInvitations(from: [metadata], into: store) { _, error in
                let text = error.map { CloudKitErrorText.describe($0) }
                Task { @MainActor in
                    let sharing = FamilySharing.shared
                    if let text {
                        sharing.lastFailure = "초대 받기\n" + text
                    } else {
                        sharing.lastFailure = nil
                        sharing.didAcceptInvitation = true
                    }
                    sharing.refreshState()
                }
            }
        }
    }

    /// 이 기기에서 초대를 받아들인 적이 있나. 참가자 화면의 근거다.
    var didAcceptInvitation = false

    /// **참가자 상태를 지운다** (79번). 관리자가 공유를 끊은 뒤 이 기기가
    /// 영영 "참가 중" 으로 남지 않게 — 기억한 역할과 받아 둔 참가자 ID 를
    /// 비우고 다시 읽는다. 공유 저장소는 이미 비어 있으므로 지울 기록은 없다.
    func forgetParticipation() {
        UserDefaults.standard.removeObject(forKey: Self.roleKey)
        UserDefaults.standard.removeObject(forKey: Self.userRecordKey)
        didAcceptInvitation = false
        state.role = .owner
        state.shareLost = false
        refreshState()
    }

    /// **이 기기가 이 객체를 고칠 수 있나.**
    ///
    /// 참가자 쪽에서는 `CKShare` 의 권한이 답한다. 소유자 쪽에서는 늘 참이다.
    /// 4단계에서 `\.canEdit` 에 꽂을 값이 이것이다.
    func canEdit(_ object: NSManagedObject) -> Bool {
        guard let cloudContainer else { return true }
        return cloudContainer.canUpdateRecord(forManagedObjectWith: object.objectID)
    }
}

/// 준비가 끝났는지. 시간 초과와 진짜 응답이 **둘 다** 완료를 부르면 안 된다.
private final class PreparationState: @unchecked Sendable {
    var finished = false
}

private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// **초대 시트를 UIKit 으로 직접 띄운다.**
///
/// 처음에는 `UIViewControllerRepresentable` 로 감싸 SwiftUI `.sheet` 안에
/// 박아 넣었는데, 기기에서 **빈 화면**이 나왔다.
///
/// `preparationHandler` 로 만든 `UICloudSharingController` 는 준비가 끝날
/// 때까지 비어 있고, **그 준비는 컨트롤러가 제대로 모달로 표시될 때
/// 시작된다.** 남의 뷰 안에 박아 넣으면 그 생애주기를 못 타서 준비가
/// 시작되지 않는다 — 그래서 영영 빈 화면이다.
///
/// (빌드 28·29 에서 시트가 그려졌던 것은 `init(share:container:)` 라
/// 준비 없이 즉시 그려졌기 때문이다. 준비 핸들러로 바꾸자 드러났다.)
///
/// 참가자 추가·권한 변경·공유 중단이 다 이 화면에 붙어 있으므로 우리가
/// 다시 만들지 않는다. 띄우는 방식만 애플이 기대하는 대로 고친다.
@MainActor
enum FamilyShareSheet {

    static func present(titled title: String) {
        let controller = makeController(titled: title)
        // 보기 전용이 **기본**이다 (확정된 요구). 넓히는 것은 이 화면에서
        // 아빠가 참가자별로 정한다.
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPrivate]
        controller.delegate = delegate
        delegate.title = title

        guard let top = topViewController() else {
            FamilySharing.shared.lastFailure = "초대 화면을 띄울 자리를 찾지 못했습니다."
            return
        }
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
    }

    /// **저장된 공유가 있으면 관리 화면, 없으면 만들기.**
    ///
    /// 두 화면은 하는 일이 다르다. 관리 쪽은 참가자 목록·권한·공유 중단을
    /// 내놓고, 만들기 쪽은 초대 링크를 보낼 곳을 고르게 한다. 하나로 합치면
    /// 관리할 방법이 없어진다.
    ///
    /// 가르는 기준은 `share.url` 이다 — 서버에 저장돼야 생기는 값이라
    /// 반쪽짜리를 관리 화면으로 보내는 일이 없다.
    private static func makeController(titled title: String) -> UICloudSharingController {
        // **저장된 공유가 있다고 화면이 이미 알고 있을 때만** 조회한다.
        // 모르는 채로 물어보면 없는 경우까지 기다리게 된다.
        let household = Household.current(in: Persistence.viewContext)
        if FamilySharing.shared.state.isSaved,
           let saved = FamilySharing.shared.savedShare(for: household) {
            return UICloudSharingController(
                share: saved,
                container: CKContainer(identifier: Persistence.cloudKitContainerID))
        }
        return UICloudSharingController { _, completion in
            FamilySharing.shared.prepareShare(titled: title, completion: completion)
        }
    }

    /// 지금 화면 맨 위. 시트 위에 시트를 띄우면 아무것도 안 보인다.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// 대리자는 **한 번 만들어 들고 있는다.** 지역 변수로 두면 시트가 뜬
    /// 직후 사라져서, 실패 이유를 받을 자리가 없어진다.
    private static let delegate = Delegate()

    final class Delegate: NSObject, UICloudSharingControllerDelegate {
        var title = ""

        func itemTitle(for controller: UICloudSharingController) -> String? { title }

        /// **시트가 실패한 이유를 여기서 붙잡는다.** 시트의 알림은 "링크를
        /// 생성할 수 없습니다" 까지만 말한다. CloudKit 오류 코드는 이
        /// 콜백으로만 온다.
        /// **이 콜백들도 메인이라는 보장이 없다.** 공유 저장은 네트워크
        /// 작업이라 백그라운드에서 온다. 오류를 **여기서 미리 글로 바꿔**
        /// 놓으면 건너가는 것이 문자열뿐이라 안전하다.
        func cloudSharingController(_ controller: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            let text = CloudKitErrorText.describe(error)
            Task { @MainActor in
                FamilySharing.shared.lastFailure = "시트가 공유를 저장\n" + text
            }
        }

        func cloudSharingControllerDidSaveShare(_ controller: UICloudSharingController) {
            Task { @MainActor in FamilySharing.shared.lastFailure = nil }
        }

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            Task { @MainActor in FamilySharing.shared.lastFailure = nil }
        }
    }
}
