import Foundation
import SwiftData

enum Persistence {
    static let schema = Schema([Member.self, Account.self, Holding.self])

    /// 지금은 기기 로컬 전용이다.
    ///
    /// CloudKit 동기화(ADR-0001)는 Apple Developer 계정이 생기면 켠다 —
    /// `ModelConfiguration(..., cloudKitDatabase: .private("iCloud.com.helpnara.slowrich"))`.
    /// 스키마는 이미 CloudKit 제약을 지키고 있어서 플래그만 바꾸면 된다.
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("데이터 저장소를 열지 못했습니다: \(error)")
        }
    }()
}
