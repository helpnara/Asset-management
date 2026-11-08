import Core
import SwiftUI
import UIKit

/// **날짜 칸 하나** (216번, 2026-11-08 사용자 — 느린 인연 1.1.9 의 날짜 입력을 옮김). 앱의 날짜 입력은 모두 이 꼴이다.
/// 왼쪽에 이름, 오른쪽에 지금 값(누르는 칩). 누르면 말풍선에 칸 달력이 뜨고 **날을 누르는 순간 닫히며 값이 들어간다**.
///
/// - `‹ 2026년 11월 ⌄ ›` — 화살표로 달을 넘기고, 제목을 누르면 열두 달 → 그 제목을 누르면 열두 해. 해 · 달을 고르는 것으로는
///   닫히지 않는다(해 → 달 → 날을 **한 번 열어** 끝낸다). 시스템 달력(`DatePicker`)은 해 · 달만 돌려도 고른 날이 바뀌어
///   "날을 누른 것" 과 "해 · 달을 바꾼 것" 을 가를 수 없다 — 그래서 칸 달력을 직접 그린다(느린 인연 이슈 83).
///
/// **저장하는 값은 시스템 달력과 같다.** 이 앱의 날짜는 주 기준일(토요일) · 일기의 하루 · 알림 날짜와 묶여 있어,
/// 느린 인연의 "그날 정오 UTC" 저장 규칙은 옮기지 않았다(옮기면 있던 자료가 어긋난다). 여기서는 **연 · 월 · 일만 바꾸고
/// 시각 부분은 원래 값 그대로** 둔다 — `DatePicker(displayedComponents: .date)` 가 하던 것과 같다. 달력은 `Calendar.app`
/// (그레고리력 · 기기 시간대, 194번 D2)으로 읽고 쓴다. 각 화면의 정리(일기는 그날 0시로 등)는 지금처럼 화면이 한다.
struct DateField: View {
    let title: String
    @Binding var date: Date
    /// 이 날보다 뒤는 고를 수 없다 — 지난 기록처럼 미래가 뜻이 없는 칸.
    var latest: Date?
    @State private var picking = false
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, date: Binding<Date>, latest: Date? = nil) {
        self.title = title
        self._date = date
        self.latest = latest
    }

    var body: some View {
        LabeledContent(title) {
            Button {
                // 입력 칸의 초점을 먼저 놓는다 — 말풍선이 닫힐 때 화면이 그 칸으로 튀지 않게 (느린 인연 이슈 61).
                Keyboard.dismiss()
                picking = true
            } label: {
                DateChip(text: DateText.full(date), enabled: isEnabled)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(title) \(DateText.full(date))"))
            .accessibilityHint(isEnabled ? "눌러서 고릅니다" : "")
            .popover(isPresented: $picking) {
                DayCalendar(selected: parts, latest: latestParts) { year, month, day in
                    set(year: year, month: month, day: day)
                }
                .padding(12)
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var parts: CalendarDay { CalendarDay(date) }
    private var latestParts: CalendarDay? { latest.map(CalendarDay.init) }

    /// 연 · 월 · 일만 바꾸고 시각(시 · 분 · 초)은 원래 값 그대로 — 시스템 날짜 고르개와 같은 저장.
    private func set(year: Int, month: Int, day: Int) {
        let calendar = Calendar.app
        var components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        components.year = year
        components.month = month
        components.day = min(day, CalendarDay.daysIn(year: year, month: month))
        if let next = calendar.date(from: components) { date = next }
        picking = false
    }
}

/// **해 · 달 칸 하나** (216번) — 구성원의 태어난 해 · 달처럼 날까지는 없는 칸. 칩 `1984년 3월` → 말풍선의 열두 달
/// (`‹ 1984년 ⌄ ›`, 제목을 누르면 열두 해) → **달을 누르는 순간 닫힌다**. 해를 고르는 것으로는 닫히지 않는다.
struct YearMonthField: View {
    let title: String
    @Binding var year: Int
    @Binding var month: Int
    let years: ClosedRange<Int>
    @State private var picking = false

    var body: some View {
        LabeledContent(title) {
            Button {
                Keyboard.dismiss()
                picking = true
            } label: {
                DateChip(text: "\(year)년 \(month)월", enabled: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(title) \(year)년 \(month)월"))
            .accessibilityHint("눌러서 고릅니다")
            .popover(isPresented: $picking) {
                MonthGrid(selectedYear: year, selectedMonth: month, years: years) { pickedYear, pickedMonth in
                    year = pickedYear
                    month = pickedMonth
                    picking = false
                }
                .padding(12)
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}

/// 날짜 칸의 값 칩 — 시스템 날짜 고르개의 작은 꼴과 비슷하게(옅은 바탕 · 강조색 글자).
struct DateChip: View {
    let text: String
    var enabled = true

    var body: some View {
        Text(verbatim: text)
            .font(.figure(15))
            .foregroundStyle(enabled ? Color.dad : Color.faint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.neutralSoft, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
    }
}

/// 시간대 없는 연 · 월 · 일 — 칸 달력이 주고받는 값. `Calendar.app` 으로 읽는다.
struct CalendarDay: Equatable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date) {
        let parts = Calendar.app.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// 그 달의 날 수.
    static func daysIn(year: Int, month: Int) -> Int {
        let calendar = Calendar.app
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return 28 }
        return range.count
    }

    /// 이 날이 `other` 보다 뒤인가 — 연 · 월 · 일 차례로 견준다.
    func isAfter(_ other: CalendarDay) -> Bool {
        (year, month, day) > (other.year, other.month, other.day)
    }
}

/// 고를 수 있는 해 — 1930년(구성원 생년과 같은 시작)부터 올해 + 80년(먼 목돈 · 만기)까지.
enum DateGrids {
    static var years: ClosedRange<Int> {
        let now = Calendar.app.component(.year, from: .now)
        return 1930...(now + 80)
    }
}

/// 떠 있는 키보드를 내린다 (느린 인연 이슈 61). 입력 칸에 초점이 남은 채 날짜 말풍선을 열고 닫으면
/// 화면이 그 입력 칸을 다시 보이려고 위아래로 튄다 — 고르기 **전에** 초점을 놓는다.
enum Keyboard {
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - 칸들

/// 칸 하나 — 누르기 쉬운 크기(44pt), 고른 것은 옅은 강조 바탕 · 강조색 굵은 글자. 못 고르는 칸은 흐리게.
private struct GridCell: View {
    let text: String
    let selected: Bool
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: text)
                .font(.scaled(15, weight: selected ? .semibold : .regular))
                .foregroundStyle(!enabled ? Color.faint : (selected ? Color.dad : Color.ink))
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Color.dadSoft : Color.neutralSoft, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 위쪽 넘기기 줄 — `‹ 2026년 ›`. `onTitle` 이 있으면 제목이 단추다(`2026년 3월 ⌄` — 눌러서 한 단계 위를 고른다).
private struct PagerHeader: View {
    let title: String
    let canGoBack: Bool
    let canGoForward: Bool
    let back: () -> Void
    let forward: () -> Void
    var onTitle: (() -> Void)?
    var titleHint = ""

    var body: some View {
        HStack {
            Button(action: back) {
                Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!canGoBack)
            .accessibilityLabel("이전")
            Spacer()
            if let onTitle {
                Button(action: onTitle) {
                    HStack(spacing: 4) {
                        Text(verbatim: title).font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
                        Image(systemName: "chevron.down").font(.scaled(11, weight: .semibold)).foregroundStyle(Color.dad)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(titleHint)
            } else {
                Text(verbatim: title).font(.scaled(16, weight: .semibold)).foregroundStyle(Color.ink)
            }
            Spacer()
            Button(action: forward) {
                Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("다음")
        }
        .foregroundStyle(Color.dad)
    }
}

/// 열두 해씩 — 넘기고 해를 누르면 그 해를 알린다.
private struct YearGrid: View {
    let selected: Int
    let range: ClosedRange<Int>
    let onPick: (Int) -> Void
    @State private var start: Int

    init(selected: Int, range: ClosedRange<Int>, onPick: @escaping (Int) -> Void) {
        self.selected = selected
        self.range = range
        self.onPick = onPick
        let anchor = min(max(selected, range.lowerBound), range.upperBound)
        self._start = State(initialValue: anchor - (anchor - range.lowerBound) % 12)
    }

    var body: some View {
        VStack(spacing: 8) {
            PagerHeader(title: "\(start) – \(min(start + 11, range.upperBound))",
                        canGoBack: start > range.lowerBound, canGoForward: start + 12 <= range.upperBound,
                        back: { start -= 12 }, forward: { start += 12 })
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(Array(start...min(start + 11, range.upperBound)), id: \.self) { year in
                    GridCell(text: "\(year)년", selected: year == selected) { onPick(year) }
                        .accessibilityLabel(Text(verbatim: "\(year)년"))
                }
            }
        }
        .frame(minWidth: 280)
    }
}

/// 열두 달 — 해를 넘기고 달을 누르면 그 연 · 월을 알린다. 제목(`2026년 ⌄`)을 누르면 열두 해에서 해를 고른다 —
/// 해를 골라도 알리지 않고(닫히지 않는다) 그 해의 열두 달로 돌아온다.
struct MonthGrid: View {
    let selectedYear: Int
    let selectedMonth: Int
    let years: ClosedRange<Int>
    let onPick: (Int, Int) -> Void
    @State private var year: Int
    @State private var choosingYear = false

    init(selectedYear: Int, selectedMonth: Int, years: ClosedRange<Int>, onPick: @escaping (Int, Int) -> Void) {
        self.selectedYear = selectedYear
        self.selectedMonth = selectedMonth
        self.years = years
        self.onPick = onPick
        self._year = State(initialValue: min(max(selectedYear, years.lowerBound), years.upperBound))
    }

    var body: some View {
        if choosingYear {
            YearGrid(selected: year, range: years) { picked in
                year = picked
                choosingYear = false
            }
        } else {
            VStack(spacing: 8) {
                PagerHeader(title: "\(year)년",
                            canGoBack: year > years.lowerBound, canGoForward: year < years.upperBound,
                            back: { year -= 1 }, forward: { year += 1 },
                            onTitle: { choosingYear = true }, titleHint: "눌러서 해를 고릅니다")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(1...12, id: \.self) { month in
                        GridCell(text: "\(month)월", selected: year == selectedYear && month == selectedMonth) {
                            onPick(year, month)
                        }
                        .accessibilityLabel(Text(verbatim: "\(year)년 \(month)월"))
                    }
                }
            }
            .frame(minWidth: 280)
        }
    }
}

/// **날짜 달력** — 해 → 달 → 날 차례로 고르고 **날을 누를 때만** 알린다(닫힌다).
///
/// - 날: `‹ 2026년 3월 ⌄ ›` — 화살표로 달을 넘기고, 제목을 누르면 열두 달로
/// - 달: `‹ 2026년 ⌄ ›` 열두 달 — 달을 누르면 그 달의 날로(닫히지 않는다), 제목을 누르면 열두 해로
/// - 해: 열두 해씩 — 해를 누르면 그 해의 열두 달로(닫히지 않는다)
///
/// 요일은 `Calendar.app`(한국어 · 일요일 시작). 오늘은 강조색 글자, 고른 날은 옅은 강조 바탕. `latest` 뒤의 날 · 달 · 해는 흐리게, 못 누른다.
struct DayCalendar: View {
    let selected: CalendarDay
    var latest: CalendarDay?
    let onPick: (Int, Int, Int) -> Void
    @State private var year: Int
    @State private var month: Int
    @State private var stage: Stage = .days

    private enum Stage { case days, months, years }

    init(selected: CalendarDay, latest: CalendarDay? = nil, onPick: @escaping (Int, Int, Int) -> Void) {
        self.selected = selected
        self.latest = latest
        self.onPick = onPick
        let range = DateGrids.years
        self._year = State(initialValue: min(max(selected.year, range.lowerBound), range.upperBound))
        self._month = State(initialValue: selected.month)
    }

    /// 고를 수 있는 해의 끝 — `latest` 가 있으면 그 해까지.
    private var years: ClosedRange<Int> {
        let range = DateGrids.years
        guard let latest else { return range }
        return range.lowerBound...max(range.lowerBound, min(range.upperBound, latest.year))
    }

    var body: some View {
        Group {
            switch stage {
            case .days: days
            case .months: months
            case .years:
                YearGrid(selected: year, range: years) { picked in
                    year = picked
                    stage = .months
                }
            }
        }
        .frame(minWidth: 300)
    }

    // MARK: 날

    private var days: some View {
        let calendar = Calendar.app
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) ?? .now
        let count = CalendarDay.daysIn(year: year, month: month)
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let today = CalendarDay(.now)
        return VStack(spacing: 6) {
            PagerHeader(title: "\(year)년 \(month)월",
                        canGoBack: !(year == years.lowerBound && month == 1),
                        canGoForward: !isMonthAfterLatest(year: year, month: month + 1),
                        back: { step(-1) }, forward: { step(1) },
                        onTitle: { stage = .months }, titleHint: "눌러서 해와 달을 고릅니다")
            dayGrid(lead: lead, count: count, today: today, symbols: weekdaySymbols(calendar))
        }
    }

    /// 요일 줄 + 날 칸 — 한 식이 길면 컴파일러가 형식을 제때 못 맞춰 떼어 둔다.
    private func dayGrid(lead: Int, count: Int, today: CalendarDay, symbols: [String]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(Color.muted)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .accessibilityHidden(true)
            }
            ForEach(0..<(lead + count), id: \.self) { slot in
                daySlot(slot - lead + 1, today: today)
            }
        }
    }

    @ViewBuilder
    private func daySlot(_ day: Int, today: CalendarDay) -> some View {
        if day < 1 {
            Color.clear.frame(minHeight: 40).accessibilityHidden(true)
        } else {
            let this = CalendarDay(year: year, month: month, day: day)
            DayCell(day: day,
                    selected: this == selected,
                    isToday: this == today,
                    enabled: !(latest.map { this.isAfter($0) } ?? false)) {
                onPick(year, month, day)
            }
            .accessibilityLabel(Text(verbatim: "\(year)년 \(month)월 \(day)일"))
        }
    }

    /// 요일 글자 — 이 앱의 달력(일요일 시작)부터.
    private func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return symbols }
        let start = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[start...] + symbols[..<start])
    }

    /// 그 달 1일이 `latest` 보다 뒤인가 — 앞으로 넘기기를 막는다.
    private func isMonthAfterLatest(year: Int, month: Int) -> Bool {
        guard let latest else { return year > years.upperBound || (year == years.upperBound && month > 12) }
        var y = year, m = month
        if m > 12 { m = 1; y += 1 }
        return CalendarDay(year: y, month: m, day: 1).isAfter(latest)
    }

    /// 달 넘기기 — 해가 바뀌면 해도 넘긴다.
    private func step(_ delta: Int) {
        var m = month + delta
        var y = year
        if m < 1 { m = 12; y -= 1 }
        if m > 12 { m = 1; y += 1 }
        guard years.contains(y) else { return }
        year = y
        month = m
    }

    // MARK: 달

    private var months: some View {
        VStack(spacing: 8) {
            PagerHeader(title: "\(year)년",
                        canGoBack: year > years.lowerBound, canGoForward: year < years.upperBound,
                        back: { year -= 1 }, forward: { year += 1 },
                        onTitle: { stage = .years }, titleHint: "눌러서 해를 고릅니다")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(1...12, id: \.self) { m in
                    GridCell(text: "\(m)월", selected: year == selected.year && m == selected.month,
                             enabled: !isMonthAfterLatest(year: year, month: m)) {
                        month = m
                        stage = .days
                    }
                    .accessibilityLabel(Text(verbatim: "\(year)년 \(m)월"))
                }
            }
        }
    }
}

/// 달력의 날 칸 — 고른 날은 옅은 강조 바탕 · 굵은 강조 글자, 오늘은 강조 글자, 못 고르는 날은 흐리게.
private struct DayCell: View {
    let day: Int
    let selected: Bool
    let isToday: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: "\(day)")
                .font(.figure(15, weight: selected || isToday ? .semibold : .regular))
                .foregroundStyle(!enabled ? Color.faint : (selected || isToday ? Color.dad : Color.ink))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selected ? Color.dadSoft : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
