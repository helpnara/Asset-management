import CoreData
import SwiftUI

/// 변경 이력 — 무엇이 언제 바뀌었나 (docs/08-feedback.md 29번).
///
/// `누가` 는 기기마다 정한 이름이다 (`ActorName`, 74번). **공유가 없어도
/// 쓸모가 있다** — 지난주에 내가 무엇을 고쳤는지 돌아볼 수 있다.
///
/// **1페이지에는 넣지 않는다.** 종이는 남에게 건네는 문서인데 이력에는
/// 금액이 남는다.
struct ChangeLogView: View {
    @Fetched(sort: \ChangeLog.at, order: .reverse) private var logs: [ChangeLog]
    /// 금액 가리기 (192번 D). 켜고 끌 때 다시 그리려고 지켜본다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    var body: some View {
        List {
            if logs.isEmpty {
                Section {
                    Text("아직 남은 이력이 없습니다.\n주간 점검을 마치거나 계좌·종목을 더하고 계획 값을 고치면 여기 쌓입니다.")
                        .font(.scaled(12.5))
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                }
            }

            ForEach(groups, id: \.day) { group in
                Section(dayText(group.day)) {
                    ForEach(group.logs) { log in
                        row(log)
                    }
                }
            }
        }
        .navigationTitle("변경 이력")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ log: ChangeLog) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(Self.timeFormatter.string(from: log.at))
                .font(.figure(11))
                .foregroundStyle(Color.faint)
                .frame(width: Font.scaledLength(48), alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(log.kind.label)
                        .font(.scaled(9, weight: .medium))
                        .foregroundStyle(Color.muted)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.raised, in: Capsule())
                    Text(Self.shown(log.subject, of: log.kind, isSubject: true, hidden: hideAmounts))
                        .font(.scaled(13, weight: .medium))
                        .foregroundStyle(Color.ink)
                }
                Text(Self.shown(log.summary, of: log.kind, isSubject: false, hidden: hideAmounts))
                    .font(.scaled(11.5))
                    .foregroundStyle(Color.bodyText)
            }
            Spacer(minLength: 6)
            // **누가** (74번). 가족 넷이 쓰면 이것 없이는 이력이 반쪽이다.
            if !log.actor.isEmpty {
                Text(log.actor)
                    .font(.scaled(10))
                    .foregroundStyle(Color.faint)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    /// **금액 가리기는 보여 줄 때 한다** (192번 D). 이력은 일부러 가리지 않은
    /// 원래 숫자로 저장한다 — 가린 채 저장하면 `••••` 가 영영 남는다(111번). 그런데
    /// 보여 줄 때 가리는 것이 빠져서, 가리기를 켜고 폰을 건네면 여기서 샜다.
    ///
    /// 금액이 들어가는 줄은 셋뿐이다 — 주간 점검(`이전 → 이번`), 평가액 고침
    /// (`이전 → 이번`), 축하(`총자산 3억 2,000만`, `3억을 넘었습니다`). 나머지 줄의
    /// 숫자(`종목 12건`, `4주 연속`)는 금액이 아니므로 건드리지 않는다.
    static func shown(_ text: String, of kind: ChangeKind, isSubject: Bool, hidden: Bool) -> String {
        guard hidden else { return text }
        switch kind {
        case .weeklyEntry, .valueEdit:
            return isSubject ? text : replace(amount, in: text)
        case .milestone:
            return replace(isSubject ? eokOnly : amount, in: text)
        case .structure, .planValue, .other:
            return text
        }
    }

    /// `3억 2,000만` · `1,234만` · `-5,000원` 을 한 덩어리로 잡는다.
    private static let amount = try? NSRegularExpression(
        pattern: "-?\\d[\\d,.]*\\s?(?:억|만|천|원)?(?:\\s?\\d[\\d,.]*\\s?(?:만|천|원))*")
    /// 축하 제목의 `3억` 만. `4주 연속` 의 4 는 금액이 아니다.
    private static let eokOnly = try? NSRegularExpression(pattern: "\\d[\\d,]*억")

    private static func replace(_ regex: NSRegularExpression?, in text: String) -> String {
        guard let regex else { return AmountPrivacy.mask(text) }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "••••")
    }

    private struct Group {
        let day: Date
        let logs: [ChangeLog]
    }

    /// 날짜별로 묶는다. 하루에 여러 줄이 쌓이므로 날짜가 머리글로 서야 읽힌다.
    private var groups: [Group] {
        let calendar = Calendar.current
        var order: [Date] = []
        var byDay: [Date: [ChangeLog]] = [:]
        for log in logs {
            let day = calendar.startOfDay(for: log.at)
            if byDay[day] == nil { order.append(day) }
            byDay[day, default: []].append(log)
        }
        return order.map { Group(day: $0, logs: byDay[$0] ?? []) }
    }

    private func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "오늘" }
        if calendar.isDateInYesterday(date) { return "어제" }
        return DateText.fullWithWeekday(date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
