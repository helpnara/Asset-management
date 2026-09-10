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
    /// 참가자 중 **본인 것을** 고칠 수 있게 넓혀 준 사람.
    case editor
    /// 참가자 기본값 — 보기만 한다.
    case viewer

    var id: String { rawValue }

    var label: String {
        switch self {
        case .owner: return "관리자"
        case .editor: return "본인 것 수정"
        case .viewer: return "보기 전용"
        }
    }

    /// 자기 구성원에 딸린 것(계좌·종목)을 고칠 수 있나.
    var canEdit: Bool { self != .viewer }

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
}

extension View {
    /// 이 아래 화면 전부에 역할을 건다.
    func familyRole(_ role: FamilyRole) -> some View {
        environment(\.familyRole, role)
            .environment(\.canEdit, role.canEdit)
            .environment(\.canManageHousehold, role.canManageHousehold)
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
