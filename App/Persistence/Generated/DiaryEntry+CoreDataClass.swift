// **이 파일은 손으로 고친다.** (Household+CoreDataClass.swift 의 머리말 참고)
//
// 칸을 더할 때는 **셋을 함께** 고친다:
//   App/SlowRich.xcdatamodeld · 이 파일 · Tools/cloudkit/slowrich.ckdb

import CoreData
import Foundation

/// **목·실·감 일기 한 날.** 그날의 목표, 실적, 감사한 것 (docs/05-roadmap.md
/// 마지막 묶음 1).
///
/// **가구에 매달지 않는다.** 이 엔티티에는 `household` 관계가 일부러 없다 —
/// 그래서 공유 존으로 안 가고 각자의 iCloud 개인 저장소에만 남는다. 아내분의
/// 보기 전용 권한과도 무관하게 본인은 쓴다. `Household.attachNew` 는 관계가
/// 없는 엔티티를 건너뛴다.
@objc(DiaryEntry)
class DiaryEntry: NSManagedObject, Identifiable {

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date.now
        day = Calendar.current.startOfDay(for: .now)
    }
}
