import CloudKit
import Foundation

/// CloudKit 오류를 **사람이 읽고 고칠 수 있는 글**로 편다.
///
/// **`partialFailure` 때문에 만들었다.** 기기에서 이렇게 떴다:
///
///     작업을 완료할 수 없습니다. (CKErrorDomain 오류 2.)
///
/// 코드 2 는 `partialFailure` — **"레코드마다 다른 이유가 있다"** 는 뜻이고,
/// 그 자체로는 아무것도 안 알려 준다. 진짜 답은 `partialErrorsByItemID`
/// 안에 들어 있는데 아무도 그것을 열어 보지 않고 있었다.
///
/// 맥이 없어 디버거를 못 붙이는 이 저장소에서는 **화면에 뜬 글자가 전부**다.
/// 그 글자가 "오류 2" 면 한 바퀴가 통째로 헛돈다.
enum CloudKitErrorText {

    /// 겹겹이 싸인 것을 벗겨 가장 안쪽 이유까지 적는다.
    static func describe(_ error: Error, depth: Int = 0) -> String {
        let ns = error as NSError
        let ck = error as? CKError
            ?? ns.userInfo[NSUnderlyingErrorKey] as? CKError

        if let ck, ck.code == .partialFailure, depth < 3 {
            let items = ck.partialErrorsByItemID ?? [:]
            guard !items.isEmpty else {
                return "부분 실패인데 레코드별 이유가 비어 있습니다 (CKError 2)."
            }
            // 수백 건이 같은 이유일 때가 많다. 겹치는 것은 한 번만 적는다.
            let reasons = Set(items.values.map { describe($0, depth: depth + 1) })
            return "부분 실패 \(items.count)건:\n" + reasons.sorted().joined(separator: "\n")
        }

        if let ck {
            return "[CKError \(ck.errorCode)] " + meaning(of: ck)
        }
        return "[\(ns.domain) \(ns.code)] \(ns.localizedDescription)"
    }

    /// 이 앱에서 실제로 마주칠 것들만 우리 말로 옮긴다. 나머지는 애플의 글에
    /// 코드를 붙여 그대로 둔다 — **모르는 것을 아는 척하지 않는다.**
    private static func meaning(of ck: CKError) -> String {
        switch ck.code {
        case .invalidArguments:
            // 같은 번호(12)가 두 가지로 온다. 스키마에 없는 레코드 타입을 밀어
            // 넣을 때, 그리고 **소유자가 제 공유 링크를 눌렀을 때**. 뒤의 것을
            // 스키마 탓으로 적어 헷갈리게 한 적이 있다.
            if ck.localizedDescription.contains("owner participant") {
                return "본인이 만든 공유 링크를 본인 폰에서 눌렀습니다. 문제없습니다 — "
                    + "이 링크는 초대받은 가족의 폰에서 눌러야 합니다."
            }
            return "Production 스키마에 없는 것을 밀어 넣으려 했습니다. "
                + "스키마를 배포해야 합니다. (\(ck.localizedDescription))"
        case .permissionFailure:
            return "권한이 없습니다. 레코드 타입의 접근 권한을 보세요. "
                + "(\(ck.localizedDescription))"
        case .unknownItem:
            return "서버에 그 레코드나 레코드 타입이 없습니다. (\(ck.localizedDescription))"
        case .serverRecordChanged:
            return "다른 기기가 먼저 고쳤습니다. (\(ck.localizedDescription))"
        case .notAuthenticated:
            return "iCloud에 로그인되어 있지 않습니다."
        case .quotaExceeded:
            return "iCloud 저장 공간이 부족합니다."
        case .networkUnavailable, .networkFailure:
            return "네트워크에 연결되지 않았습니다."
        case .zoneNotFound, .userDeletedZone:
            return "레코드 존이 없습니다. (\(ck.localizedDescription))"
        default:
            return ck.localizedDescription
        }
    }
}
