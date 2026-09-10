import Foundation

/// **이력에 남는 이름** (docs/08-feedback.md 74번).
///
/// `ChangeLog.actor` 는 처음부터 있었지만 `UIDevice.current.name` 을 넣고
/// 있었다. iOS 16 부터 그 값은 자격(entitlement) 없이는 그냥 "iPhone" 이라,
/// 가족 넷이 쓰는 지금 누가 고쳤는지 이력에서 알 길이 없었다.
///
/// 이름은 **이 기기에서 정한다.** 더보기 → 가족의 "이력에 남을 이름" 에
/// 적으면 그것이고, 비워 두면 공유가 아는 이름(참가자 신원) → 없으면 역할로
/// 대신한다. 스키마는 안 건드린다 — 이름은 이미 있던 `actor` 칸에 들어간다.
enum ActorName {
    static let key = "family.actorName"

    /// 사용자가 적어 둔 이름. 빈 문자열이면 안 적은 것이다.
    static var custom: String {
        (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespaces)
    }

    @MainActor
    static var current: String {
        let custom = custom
        if !custom.isEmpty { return custom }
        let state = FamilySharing.shared.state
        if state.isParticipant {
            if let name = state.myName, !name.isEmpty { return name }
            return "참가자 " + idTail(state.participantID)
        }
        return "관리자"
    }

    /// ID 는 길다 — 견주는 데는 꼬리 여섯 자면 된다.
    static func idTail(_ id: String?) -> String {
        guard let id, !id.isEmpty else { return "없음" }
        return "…" + String(id.suffix(6))
    }
}
