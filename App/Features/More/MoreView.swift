import CloudKit
import Core
import SwiftData
import SwiftUI
import UserNotifications

struct MoreView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @Query private var sessions: [ReviewSession]
    @Query private var holdings: [Holding]

    @State private var route = AppRoute.shared

    /// CI 스크린샷이 하위 화면까지 찍을 수 있도록 실행 인자로 밀어 넣는다.
    @State private var path: [Destination] = MoreView.initialPath

    enum Destination: Hashable {
        case history
        case principles
        case notifications
        case diagnostics
        case todos
        case milestones
        case security
        case export
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section("점검") {
                    NavigationLink(value: Destination.notifications) {
                        Label("주간 점검 알림", systemImage: "bell")
                    }
                    NavigationLink(value: Destination.security) {
                        Label("잠금 · 가리기", systemImage: "lock")
                    }
                    LabeledContent("연속 기록", value: "\(streak)주")
                    LabeledContent("기록한 주", value: "\(sessions.filter(\.isComplete).count)주")
                }

                Section("기록") {
                    NavigationLink(value: Destination.history) {
                        Label("지난 기록 직접 입력", systemImage: "calendar.badge.plus")
                    }
                    NavigationLink(value: Destination.diagnostics) {
                        Label("자산 진단", systemImage: "checklist")
                    }
                    NavigationLink(value: Destination.todos) {
                        Label("유의사항 · 할 일", systemImage: "note.text")
                    }
                    NavigationLink(value: Destination.principles) {
                        Label("운용 원칙", systemImage: "list.number")
                    }
                    NavigationLink(value: Destination.milestones) {
                        Label("내 마일스톤", systemImage: "flag")
                    }
                    NavigationLink(value: Destination.export) {
                        Label("1페이지 · 백업 내보내기", systemImage: "square.and.arrow.up")
                    }
                }


                Section("자산") {
                    LabeledContent("등록한 종목", value: "\(holdings.count)건")
                    LabeledContent("매주 입력", value: "\(holdings.filter { $0.cadence == .weekly }.count)건")
                    LabeledContent("월 1회 입력", value: "\(holdings.filter { $0.cadence == .monthly }.count)건")
                    LabeledContent("고정 (건너뜀)", value: "\(holdings.filter { $0.cadence == .fixed }.count)건")
                }

                SyncStatusSection()

                Section {
                    Text("시세를 외부에서 가져오지 않습니다. 매주 직접 적어 넣는 숫자가 이 앱의 기준입니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.faint)
                }
            }
            .navigationTitle("더보기")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: route.wantsDiagnostics, initial: true) { _, wants in
                guard wants else { return }
                route.wantsDiagnostics = false
                if path.last != .diagnostics { path.append(.diagnostics) }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .history: PastRecordsView()
                case .notifications: NotificationSettingsView()
                case .diagnostics: DiagnosticsView()
                case .todos: TodoListView()
                case .milestones: MilestoneListView()
                case .principles: PrincipleListView()
                case .security: SecuritySettingsView()
                case .export: ExportView()
                }
            }
        }
    }

    static var initialPath: [Destination] {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-startHistory") { return [.history] }
        if arguments.contains("-startDiagnostics") { return [.diagnostics] }
        if arguments.contains("-startTodos") { return [.todos] }
        if arguments.contains("-startPrinciples") { return [.principles] }
        return []
    }

    private var streak: Int {
        ReviewWeek.streak(
            completedAnchors: sessions.filter(\.isComplete).map(\.weekAnchor),
            asOf: .now
        )
    }
}

struct NotificationSettingsView: View {
    @AppStorage(ReviewSettings.weekdayKey) private var weekday = ReviewSettings.defaultWeekday
    @AppStorage(ReviewSettings.hourKey) private var hour = ReviewSettings.defaultHour
    @AppStorage(ReviewSettings.minuteKey) private var minute = ReviewSettings.defaultMinute
    @AppStorage(ReviewSettings.followUpKey) private var followUpEnabled = true

    @Query private var holdings: [Holding]
    @Query private var sessions: [ReviewSession]

    @State private var status: UNAuthorizationStatus = .notDetermined

    private let weekdayNames = ["일", "월", "화", "수", "목", "금", "토"]

    var body: some View {
        Form {
            Section {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    LabeledContent("알림 권한", value: "허용됨")
                case .denied:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("알림이 꺼져 있습니다")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.loss)
                        Text("토요일에 알려드릴 수 없습니다. 설정 앱에서 알림을 켜주세요.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Color.muted)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("설정 열기", destination: url).font(.system(size: 12.5))
                        }
                    }
                default:
                    Button("알림 허용하기") {
                        Task {
                            await ReviewNotifications.requestAuthorization()
                            await refresh()
                        }
                    }
                }
            } footer: {
                Text("이 앱은 외부에서 자료를 가져오지 않습니다. 알림이 점검을 시작하는 유일한 계기입니다.")
            }

            Section("점검일") {
                Picker("요일", selection: $weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text("\(weekdayNames[day - 1])요일").tag(day)
                    }
                }
                Picker("시각", selection: $hour) {
                    ForEach(5...22, id: \.self) { Text("\($0)시").tag($0) }
                }
                Picker("분", selection: $minute) {
                    ForEach([0, 15, 30, 45], id: \.self) { Text("\($0)분").tag($0) }
                }
            }

            Section {
                Toggle("다음날 한 번 더 알림", isOn: $followUpEnabled)
            } footer: {
                Text("점검일에 적지 않으면 다음날 같은 시각에 한 번만 더 부릅니다. 그것도 놓치면 조용히 넘어갑니다.")
            }

            Section {
                Text("알림에 금액을 보여줄지는 [잠금 · 가리기]에서 정합니다. 알림은 잠긴 화면에도 뜹니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
            }
        }
        .navigationTitle("주간 점검 알림")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: weekday) { _, _ in Task { await reschedule() } }
        .onChange(of: hour) { _, _ in Task { await reschedule() } }
        .onChange(of: minute) { _, _ in Task { await reschedule() } }
        .onChange(of: followUpEnabled) { _, _ in Task { await reschedule() } }
    }

    private func refresh() async {
        status = await ReviewNotifications.authorizationStatus()
    }

    private func reschedule() async {
        let input = ReviewScheduling.Input(holdings: holdings, sessions: sessions)
        await ReviewScheduling.refresh(input)
    }
}


/// iCloud 동기화 상태.
///
/// "켜져 있다고 생각했는데 아니었다"가 이 앱에서 제일 위험한 상태다. 몇 달치
/// 기록이 백업되고 있는 줄 알았는데 아니면 되돌릴 방법이 없다. 그래서 저장소가
/// 실제로 열린 모드와 iCloud 계정 상태를 둘 다 보여 준다.
struct SyncStatusSection: View {
    @State private var accountStatus: CKAccountStatus?

    var body: some View {
        Section {
            LabeledContent("저장 방식") {
                Text(modeLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(modeColor)
            }
            if case .cloudKit = Persistence.mode {
                LabeledContent("iCloud 계정", value: accountLabel)
            }
        } header: {
            Text("동기화")
        } footer: {
            Text(footer)
        }
        .task {
            guard case .cloudKit = Persistence.mode else { return }
            accountStatus = try? await CKContainer(identifier: Persistence.cloudKitContainerID)
                .accountStatus()
        }
    }

    private var modeLabel: String {
        switch Persistence.mode {
        case .cloudKit: return "iCloud 동기화"
        case .localOnly: return "이 기기에만 저장"
        case .inMemory: return "임시 (미리보기)"
        }
    }

    private var modeColor: Color {
        switch Persistence.mode {
        case .cloudKit: return .gain
        case .localOnly: return .loss
        case .inMemory: return .muted
        }
    }

    private var accountLabel: String {
        switch accountStatus {
        case .available: return "연결됨"
        case .noAccount: return "로그인 안 됨"
        case .restricted: return "제한됨"
        case .couldNotDetermine: return "확인 불가"
        case .temporarilyUnavailable: return "일시적으로 사용 불가"
        case nil: return "확인 중"
        @unknown default: return "알 수 없음"
        }
    }

    private var footer: String {
        switch Persistence.mode {
        case .cloudKit where accountStatus == .available:
            return "기록이 iCloud 개인 데이터베이스에 저장됩니다. 앱을 지우거나 기기를 바꿔도 남습니다. 애플도 내용을 볼 수 없습니다."
        case .cloudKit:
            return "설정 앱에서 iCloud에 로그인해야 동기화됩니다. 그전까지는 이 기기에만 저장됩니다."
        case .localOnly:
            return "iCloud를 붙이지 못했습니다. 기록은 이 기기에만 있고, 앱을 지우면 사라집니다. 앱을 다시 켜면 한 번 더 시도합니다."
        case .inMemory:
            return "가상 데이터입니다. 앱을 끄면 사라집니다."
        }
    }
}
