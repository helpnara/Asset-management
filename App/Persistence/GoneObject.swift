import CoreData

/// **지운 객체를 다시 그리지 않는다** (docs/08-feedback.md 189번).
///
/// 편집 시트의 `삭제` 는 `context.delete(obj); dismiss()` 다. 시트가 내려가는
/// 애니메이션이 끝날 때 SwiftUI 가 본문을 **한 번 더** 그리는데, 그 사이 자동
/// 저장(400ms)이 돌면 지운 객체는 문맥에서 떨어져 모든 속성이 nil 이 된다.
/// `String` 은 "" 로 넘어가지만 `Date` · `UUID` 는 nil 을 받을 수 없어
/// `_unconditionallyBridgeFromObjectiveC` 에서 앱이 죽는다 — 빌드 112 에서
/// 목돈 이벤트(퇴직금)를 지우다 실제로 죽었다. 새로 만든 것을 `취소` 할 때도
/// 같은 길을 탄다.
///
/// 저장 전에는 `isDeleted`, 저장 뒤에는 `managedObjectContext == nil` 로
/// 드러나므로 둘 다 본다.
extension NSManagedObject {
    var isGone: Bool { isDeleted || managedObjectContext == nil }
}
