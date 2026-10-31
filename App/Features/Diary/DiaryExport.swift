import Core
import Foundation

/// **목 · 실 · 감을 엑셀로** (212번, 2026-11-01 사용자: *"매일 쓰고 있는 목실감 지난 일기를 누르면 나오는
/// 내용을 엑셀로 다운받을 수 있게 하는 기능을 추가하자."*).
///
/// 새 형식을 만들지 않는다 — `내보내기` 의 주간 기록 · 보유 종목과 같은 `CSVFile`(엑셀이 한글을 깨지 않게
/// BOM 을 붙인다). xlsx 는 압축 · XML 을 손으로 짜야 해서(외부 묶음을 안 쓰는 규칙) CSV 로 둔다 — 엑셀 ·
/// Numbers · 구글 시트가 다 바로 연다.
///
/// 한 날 한 줄, **날짜 오름차순**(엑셀에서 아래로 쌓인다). 여러 줄로 적은 칸은 줄바꿈을 살려 큰따옴표로
/// 감싼다 — 엑셀은 따옴표 안의 줄바꿈을 한 칸 안의 줄로 연다. `지난 일기` 화면과 `내보내기` 화면이 이 한 곳을
/// 부른다 — 둘이 따로 지으면 칸이 어긋난다.
@MainActor
enum DiaryExport {
    static func csv(_ entries: [DiaryEntry], exportedOn now: Date = .now) -> CSVFile {
        // 기계가 읽는 날짜라 기기 달력 · 지역과 상관없이 같은 모양 (194번 D2) — 주간 기록 CSV 와 같다.
        let formatter = DateFormatter()
        formatter.calendar = .app
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.app.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var lines = ["날짜,요일,목표,실적,감사"]
        for entry in entries.sorted(by: { $0.day < $1.day }) where !entry.isGone {
            lines.append([
                formatter.string(from: entry.day),
                DateText.weekday(entry.day),
                cell(entry.goal), cell(entry.result), cell(entry.gratitude),
            ].joined(separator: ","))
        }
        return CSVFile(text: lines.joined(separator: "\n"),
                       name: "목실감 일기 \(formatter.string(from: now)).csv")
    }

    /// 큰따옴표는 두 번 쓰고 감싼다. 칸 안의 줄바꿈은 `\n` 하나로 맞춘다.
    private static func cell(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\r\n", with: "\n")
        return "\"" + flat.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
