import SwiftUI

/// 이 기기를 쓰는 사람이 **무엇을 할 수 있는가** (docs/09-family-sharing.md 4단계).
///
/// 4차의 절반은 공유가 아니라 이것이다. 지금 화면은 전부 "고칠 수 있는 사람"을
/// 전제로 만들어져 있어서, 보기 권한만 받은 사람이 열면 **눌러도 아무 일도 안
/// 일어나는 버튼이 널린 화면**이 된다. 그래서 공유(`CKShare`)를 붙이기 전에
/// 보기 전용 화면부터 만든다 — 붙이고 나서 만들면, 아내분이 처음 여는 화면이
/// 그 상태가 된다.
enum FamilyRole: String, CaseIterable, Sendable, Identifiable {
    /// 관리자. 전부 고친다. 공유를 만든 사람(아빠)이 여기다.
    case owner
    /// 참가자 중 관리자가 **일부 구성원의 것**을 고칠 수 있게 넓혀 준 사람.
    /// 어느 구성원인지는 `Member.editorIDs` 가 정한다.
    case editor
    /// 참가자 기본값 — 보기만 한다.
    case viewer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .owner: return "관리자"
        case .editor: return "편집 권한 받음"
        case .viewer: return "보기 전용"
        }
    }

    /// 자기 구성원에 딸린 것(계좌·종목)을 고칠 수 있나 — 역할 수준의 답.
    /// 어느 구성원인지까지 따지려면 `mayEdit(editorIDs:participantID:)`.
    var canEdit: Bool { self != .viewer }

    /// **참가자마다 고칠 수 있는 구성원을 관리자가 정한다** (docs/09 4단계 ·
    /// 합격 기준 7번). `CKShare` 의 권한은 존 전체에 걸린다 — "변경 가능" 이면
    /// 남의 계좌도 서버는 받아 준다. 그래서 구성원 단위는 앱이 잠근다:
    /// 관리자가 더보기 → 가족 → 편집 권한에서 참가자마다 구성원을 체크하면
    /// `Member.editorIDs` 에 그 참가자의 ID 가 적히고, 참가자 기기는 제 ID 가
    /// 적힌 구성원만 고친다. 엄마는 엄마·아들 것, 아들은 아들 것 — 그런 식으로.
    func mayEdit(editorIDs: String, participantID: String?) -> Bool {
        switch self {
        case .owner: return true
        case .editor:
            guard let participantID, !participantID.isEmpty else { return false }
            return Member.editorIDSet(editorIDs).contains(participantID)
        case .viewer: return false
        }
    }

    /// 가구 전체에 걸리는 것 — 계획 가정, 구성원 추가·삭제, 백업 되돌리기,
    /// 알림·진단 설정. **관리자만이다.**
    ///
    /// 되돌리기가 특히 그렇다. iCloud 는 삭제까지 퍼뜨리므로, 참가자가 자기
    /// 기기에서 되돌리면 관리자의 기록까지 갈아 끼운다 (40번).
    var canManageHousehold: Bool { self == .owner }
}

// MARK: - 환경값

/// 지금 화면이 **고칠 수 있는 화면인가**.
///
/// 화면마다 역할을 따지지 않고 이 값 하나만 읽게 한다. 그래야 4차에서
/// `CKShare` 참가자 상태를 여기에 꽂는 것으로 끝난다 — 화면은 안 고친다.
private struct CanEditKey: EnvironmentKey {
    static let defaultValue = true
}

/// 가구 전체 설정을 만질 수 있는가. `canEdit` 보다 좁다.
private struct CanManageHouseholdKey: EnvironmentKey {
    static let defaultValue = true
}

/// 지금 보고 있는 역할. 안내 문구를 쓸 때만 읽는다.
private struct FamilyRoleKey: EnvironmentKey {
    static let defaultValue = FamilyRole.owner
}

/// 이 기기의 `CKShare` 참가자 ID. 관리자 기기에서는 `nil`.
private struct ParticipantIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var canEdit: Bool {
        get { self[CanEditKey.self] }
        set { self[CanEditKey.self] = newValue }
    }

    var canManageHousehold: Bool {
        get { self[CanManageHouseholdKey.self] }
        set { self[CanManageHouseholdKey.self] = newValue }
    }

    var familyRole: FamilyRole {
        get { self[FamilyRoleKey.self] }
        set { self[FamilyRoleKey.self] = newValue }
    }

    var participantID: String? {
        get { self[ParticipantIDKey.self] }
        set { self[ParticipantIDKey.self] = newValue }
    }

    /// 화면이 구성원 하나를 두고 묻는 한 줄. `role.mayEdit(editorIDs:participantID:)`
    /// 를 환경 둘로 묶은 것이다. 구성원이 없으면(주인 없는 계좌) 관리자만.
    func mayEdit(_ member: Member?) -> Bool {
        familyRole.mayEdit(editorIDs: member?.editorIDs ?? "", participantID: participantID)
    }
}

extension View {
    /// 이 아래 화면 전부에 역할을 건다.
    func familyRole(_ role: FamilyRole, participantID: String? = nil) -> some View {
        environment(\.familyRole, role)
            .environment(\.canEdit, role.canEdit)
            .environment(\.canManageHousehold, role.canManageHousehold)
            .environment(\.participantID, participantID)
    }
}

// MARK: - CI 용 실행 인자

/// CI 가 보기 전용 화면을 찍을 때 역할을 지정한다.
///
///     xcrun simctl launch <udid> <bundle> -rolePreview viewer
///
/// 기기에서 역할을 흉내 내던 토글(더보기의 구역 + 화면 위 띠)은 실제 공유로
/// 참가자 화면이 확인된 2026-09-10 에 지웠다. 이제 역할은 `CKShare` 가 정하고,
/// 이 인자는 시뮬레이터에서만 뜻이 있다.
enum RolePreview {
    static var launchArgument: FamilyRole? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-rolePreview"),
              arguments.indices.contains(index + 1) else { return nil }
        return FamilyRole(rawValue: arguments[index + 1])
    }
}

// MARK: - 구성원의 편집 권한 목록

extension Member {
    /// `editorIDs` 는 쉼표로 이은 문자열이다 — CloudKit 에 배열 칸을 더하지
    /// 않으려고. 읽고 쓰는 길은 이 둘뿐이다.
    static func editorIDSet(_ raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    func grants(_ participantID: String) -> Bool {
        Self.editorIDSet(editorIDs).contains(participantID)
    }

    func setGrant(_ participantID: String, _ on: Bool) {
        var ids = Self.editorIDSet(editorIDs)
        if on { ids.insert(participantID) } else { ids.remove(participantID) }
        let next = ids.sorted().joined(separator: ",")
        if next != editorIDs { editorIDs = next }
    }
}
