import Foundation

/// **문의 · 피드백 받는 곳** (docs/05-roadmap.md G2).
///
/// 서버가 없으니 메일이 유일한 창구다. 주소는 사용자가 정해 준 것만 적는다 —
/// 비어 있으면 더보기에 문의 줄이 아예 안 뜬다. 제목에 버전과 빌드가 들어가
/// "몇 번 빌드였나" 를 묻지 않아도 된다 (A8).
enum SupportContact {
    /// 문의 받을 주소 (사용자가 2026-09-11 에 정해 준 것).
    static let email = "kyunglagkwon@gmail.com"

    static var isConfigured: Bool { !email.isEmpty }

    static func mailURL(version: String) -> URL? {
        guard isConfigured else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "느린 부자의 기록 \(version) 문의"),
            URLQueryItem(name: "body", value: "\n\n— 앱 \(version) · iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
        ]
        return components.url
    }
}
