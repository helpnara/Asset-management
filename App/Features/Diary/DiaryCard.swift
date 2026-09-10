import Core
import CoreData
import SwiftUI

/// **오늘의 목·실·감** — 현황판 맨 위 카드 (docs/05-roadmap.md 마지막 묶음 1).
///
/// 매일 여는 첫 화면에 오늘 한 줄을 적는 칸 셋: 목표 · 실적 · 감사. 토요일 주간
/// 점검과는 별개의 매일 루틴이다.
///
/// **`\.canEdit` 을 보지 않는다.** 일기는 가구의 자료가 아니라 **이 사람의**
/// 것이다 — `DiaryEntry` 는 가구에 매달리지 않아 공유 존으로 안 가고, 각자의
/// iCloud 개인 저장소에만 남는다. 보기 전용 참가자도 자기 일기는 쓴다.
///
/// 오늘 항목은 **첫 글자를 적을 때** 만든다. 열 때마다 만들면 아무것도 안 적은
/// 날이 빈 줄로 쌓인다.
///
/// **보기 모드 ↔ 편집 모드.** 기본은 보기다. `쓰기`/`편집` 이나 칸을 누르면
/// 입력칸이 되고 첫 빈 칸에 키보드가 올라온다. `완료` 로 닫는다. 키보드는
/// `RootView` 의 `scrollDismissesKeyboard(.interactively)` 로 끌어내려도 된다.
struct DiaryCard: View {
    @Environment(\.managedObjectContext) private var context
    @Fetched(sort: \DiaryEntry.day, order: .reverse) private var entries: [DiaryEntry]

    @State private var goal = ""
    @State private var result = ""
    @State private var gratitude = ""
    @State private var loadedDay: Date?

    /// **보기 모드가 기본이다.** 칸이 항상 입력칸이면 현황판을 열 때마다 키보드가
    /// 올라와 자산을 보기 불편하다 (2026-09-10 사용자). `편집` 으로 열고 `완료` 로
    /// 닫는다 — 닫을 때 포커스를 지워 키보드가 내려간다.
    @State private var isEditing = false
    @FocusState private var focus: Field?

    private enum Field: Hashable { case goal, result, gratitude }

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var todayEntry: DiaryEntry? { entries.first { $0.day == today } }
    private var pastCount: Int { entries.filter { $0.day != today }.count }

    /// 오늘(또는 어제)까지 이어진 날 수. 빈 항목(만들었다가 다 지운 날)은 안 센다.
    private var streak: Int {
        let written = entries
            .filter { !($0.goal.isEmpty && $0.result.isEmpty && $0.gratitude.isEmpty) }
            .map(\.day)
        return DiaryStreak.count(days: written, asOf: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("오늘의 목 · 실 · 감")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(Self.dayText(today))
                    .font(.figure(11))
                    .foregroundStyle(Color.muted)
                if streak > 1 {
                    Text("\(streak)일 연속")
                        .font(.figure(11, weight: .medium))
                        .foregroundStyle(Color.gain)
                }
                Spacer(minLength: 0)
                NavigationLink(value: DiaryDestination.list) {
                    Text(pastCount > 0 ? "지난 일기 \(pastCount)" : "지난 일기")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.muted)
                }
                if isEditing {
                    Button("완료") { finishEditing() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ink)
                } else {
                    Button(hasAnyText ? "편집" : "쓰기") { beginEditing() }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
            }
            if isEditing {
                line("목표", $goal, .goal)
                line("실적", $result, .result)
                line("감사", $gratitude, .gratitude)
            } else {
                // 보기 모드. 어디를 눌러도 편집으로 들어간다.
                VStack(alignment: .leading, spacing: 8) {
                    shown("목표", goal)
                    shown("실적", result)
                    shown("감사", gratitude)
                }
                .contentShape(Rectangle())
                .onTapGesture { beginEditing() }
            }
        }
        .padding(13)
        .background(Color.raised)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .navigationDestination(for: DiaryDestination.self) { _ in DiaryListView() }
        .onAppear(perform: load)
        // 날이 바뀐 채 앱이 떠 있었으면(자정을 넘김) 오늘 칸을 새로 읽는다.
        .onChange(of: today) { _, _ in load() }
        .onChange(of: goal) { _, value in write(\.goal, value) }
        .onChange(of: result) { _, value in write(\.result, value) }
        .onChange(of: gratitude) { _, value in write(\.gratitude, value) }
    }

    /// **위 끝 정렬.** `.firstTextBaseline` 로 두면 세로 축 텍스트필드가 라벨보다
    /// 한 줄 가까이 내려앉는다 (CI 스크린샷에서 확인). 위 끝을 맞추고 글자
    /// 크기 차이(11.5 · 13)만 라벨 쪽에서 한 점 내려 준다.
    private func line(_ label: String, _ text: Binding<String>, _ field: Field) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.muted)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 1)
            TextField("한 줄", text: text, axis: .vertical)
                .font(.system(size: 13))
                .foregroundStyle(Color.ink)
                .lineLimit(1...3)
                .focused($focus, equals: field)
        }
    }

    /// 보기 모드의 한 줄. 비었으면 흐린 글씨로 자리를 알린다.
    private func shown(_ label: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.muted)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 1)
            Text(text.isEmpty ? "아직 안 적음" : text)
                .font(.system(size: 13))
                .foregroundStyle(text.isEmpty ? Color.muted.opacity(0.6) : Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hasAnyText: Bool {
        !goal.isEmpty || !result.isEmpty || !gratitude.isEmpty
    }

    /// 편집으로 들어가며 **첫 빈 칸**에 커서를 둔다. 셋 다 찼으면 목표부터.
    private func beginEditing() {
        isEditing = true
        let first: Field = goal.isEmpty ? .goal : result.isEmpty ? .result : gratitude.isEmpty ? .gratitude : .goal
        // 입력칸이 화면에 놓인 다음 턴에 포커스해야 키보드가 올라온다.
        Task { @MainActor in focus = first }
    }

    private func finishEditing() {
        focus = nil
        isEditing = false
        // 오늘 것을 적었으면 오늘 알림은 필요 없다 — 트리거를 내일로 옮긴다.
        let written = hasAnyText
        Task { await DiaryNotifications.refresh(todayWritten: written) }
    }

    private func load() {
        guard loadedDay != today else { return }
        loadedDay = today
        goal = todayEntry?.goal ?? ""
        result = todayEntry?.result ?? ""
        gratitude = todayEntry?.gratitude ?? ""
    }

    /// 첫 글자에서 오늘 항목을 만들고, 그 뒤로는 그 항목에 적는다. 저장은
    /// `Autosave` 가 한다 — 여기서 `save()` 를 부르지 않는다.
    private func write(_ keyPath: ReferenceWritableKeyPath<DiaryEntry, String>, _ value: String) {
        guard loadedDay == today else { return }
        if let entry = todayEntry {
            if entry[keyPath: keyPath] != value { entry[keyPath: keyPath] = value }
            return
        }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let entry = DiaryEntry(context: context)
        entry.day = today
        entry[keyPath: keyPath] = value
    }

    static func dayText(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return formatter.string(from: day)
    }
}

enum DiaryDestination: Hashable {
    case list
}
