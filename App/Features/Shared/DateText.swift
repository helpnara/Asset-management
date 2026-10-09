import Core
import Foundation

/// **화면의 날짜는 세 모양** (docs/08-feedback.md 192번 H).
///
/// 같은 "날짜 전체" 가 `2026.09.29`(챙길 것 · 1페이지) · `2026. 9. 29.`(종목 이유 ·
/// 계획 수립일) · `2026년 9월 29일`(되돌리기 확인) 로 갈려 있었다. 화면마다
/// 포맷터를 따로 만들다 생긴 일이라, 모양을 여기 한 곳에 둔다.
///
/// - 전체 `2026.09.29` — 목록 · 기한 · 기록한 날
/// - 짧게 `09.29` — 올해 안의 가까운 날(다음 점검 · 마지막 점검)
/// - 요일 `(화)` — 하루 단위로 묶는 머리글
///
/// **여기 안 오는 것 둘.** 파일 이름의 `2026-09-29` 는 정렬되는 기계용 이름이고,
/// 일기 머리의 `9월 29일 화요일` 은 읽는 문장이라 뜻이 다르다. 진단 정보의 초 단위
/// 시각도 사람이 아니라 문제를 풀 때 쓰는 것이라 그대로 둔다.
///
/// 포맷터 대신 달력 숫자로 짓는다 — 로케일 · 기기 설정(12/24시간 등)에 따라
/// 모양이 바뀌지 않고, 어느 스레드에서 불러도 된다.
enum DateText {
    /// `2026.09.29`
    static func full(_ date: Date, calendar: Calendar = .app) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0).\(twoDigits(parts.month))." + twoDigits(parts.day)
    }

    /// `09.29`
    static func short(_ date: Date, calendar: Calendar = .app) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        return "\(twoDigits(parts.month))." + twoDigits(parts.day)
    }

    /// `화`
    static func weekday(_ date: Date, calendar: Calendar = .app) -> String {
        let index = calendar.component(.weekday, from: date) - 1   // 1 = 일요일
        return weekdays.indices.contains(index) ? weekdays[index] : ""
    }

    /// `2026.09.29 (화)`
    static func fullWithWeekday(_ date: Date, calendar: Calendar = .app) -> String {
        "\(full(date, calendar: calendar)) (\(weekday(date, calendar: calendar)))"
    }

    private static let weekdays = ["일", "월", "화", "수", "목", "금", "토"]

    private static func twoDigits(_ value: Int?) -> String {
        let value = value ?? 0
        return value < 10 ? "0\(value)" : "\(value)"
    }
}
