import Foundation

extension Calendar {
    /// **이 앱의 달력 — 언제나 그레고리력** (docs/08-feedback.md 194번 D2).
    ///
    /// `Calendar.current` 는 기기의 달력 설정을 따른다. 일본력이면 올해가 `8`,
    /// 불기면 `2569` 라서, 연도 목록 `1930...올해` 가 거꾸로 되어 앱이 죽고
    /// 나이가 585세로 나왔으며 그 은퇴 연도가 CloudKit 으로 가족에게 퍼졌다.
    /// 연도 · 나이 · 은퇴 해 · 주 기준일 · 회고 기간은 모두 이 달력으로 센다.
    ///
    /// - 시간대는 기기를 따른다 — 토요일 자정은 그 사람의 자정이다.
    /// - 로케일은 한국어 — 요일 이름 · 주 시작(일요일)이 기기 지역과 상관없다.
    ///
    /// **예외 하나.** 알림 트리거(`UNCalendarNotificationTrigger`)는 받은 날짜 숫자를
    /// 기기 달력으로 읽는다. 그래서 트리거에 넘길 숫자만은 `Calendar.current` 로 뽑는다.
    public static var app: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }
}
