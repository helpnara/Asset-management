// **이 파일은 손으로 고친다.** (Household+CoreDataClass.swift 의 머리말 참고)

import CoreData
import Foundation


extension DiaryEntry {

    @nonobjc class func fetchRequest() -> NSFetchRequest<DiaryEntry> {
        NSFetchRequest<DiaryEntry>(entityName: "DiaryEntry")
    }

    @NSManaged var id: UUID

    /// 어느 날의 일기인가. 자정으로 맞춘 날짜. 하루에 하나다.
    @NSManaged var day: Date

    /// 오늘의 목표.
    @NSManaged var goal: String

    /// 오늘의 실적.
    @NSManaged var result: String

    /// 오늘 감사한 것.
    @NSManaged var gratitude: String

    @NSManaged var createdAt: Date
}
