import Core
import SwiftData
import SwiftUI
import UserNotifications

struct MoreView: View {
    @Query private var sessions: [ReviewSession]
    @Query private var holdings: [Holding]

    var body: some View {
        NavigationStack {
            List {
                Section("점검") {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("주간 점검 알림", systemImage: "bell")
                    }
                    LabeledContent("연속 기록", value: "\(streak)주")
                    LabeledContent("기록한 주", value: "\(sessions.filter(\.isComplete).count)주")
                }

                Section("자산") {
                    LabeledContent("등록한 종목", value: "\(holdings.count)건")
                    LabeledContent("매주 입력", value: "\(holdings.filter { $0.cadence == .weekly }.count)건")
                    LabeledContent("월 1회 입력", value: "\(holdings.filter { $0.cadence == .monthly }.count)건")
                    LabeledContent("고정 (건너뜀)", value: "\(holdings.filter { $0.cadence == .fixed }.count)건")
                }

                Section {
                    Text("준비 중 — 운용 원칙 · 유의사항 · 1페이지 내보내기 · CSV")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.muted)
                }

                Section {
                    Text("시세를 외부에서 가져오지 않습니다. 매주 직접 적어 넣는 숫자가 이 앱의 기준입니다.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.faint)
                }
            }
            .navigationTitle("더보기")
            .navigationBarTitleDisplayMode(.inline)
        }
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
        await ReviewScheduling.refresh(holdings: holdings, sessions: sessions)
    }
}
