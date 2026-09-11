import CoreData
import SwiftUI
import UserNotifications

/// **목·실·감 알림** (docs/05-roadmap.md 마지막 묶음 1, 선택). 기본은 꺼짐.
///
/// 주간 점검 알림과 따로 둔다 — 주간 것은 가구의 의식이고 이건 개인의 습관이라
/// 켜고 끄는 사람이 다르다. 참가자도 자기 기기에서 켠다.
struct DiaryReminderSettingsView: View {
    @AppStorage(DiarySettings.enabledKey) private var enabled = false
    @AppStorage(DiarySettings.hourKey) private var hour = DiarySettings.defaultHour
    @AppStorage(DiarySettings.minuteKey) private var minute = DiarySettings.defaultMinute

    @Fetched(sort: \DiaryEntry.day, order: .reverse) private var entries: [DiaryEntry]
    @State private var status: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                Toggle("매일 알림", isOn: $enabled)
                if enabled {
                    Picker("시각", selection: $hour) {
                        ForEach(5...23, id: \.self) { Text("\($0)시").tag($0) }
                    }
                    Picker("분", selection: $minute) {
                        ForEach([0, 15, 30, 45], id: \.self) { Text("\($0)분").tag($0) }
                    }
                }
            } footer: {
                Text("그 시각 전에 오늘 것을 이미 적었으면 그날은 부르지 않습니다. 알림을 누르면 현황판의 오늘 칸이 열립니다.")
            }

            Section {
                switch status {
                case .authorized, .provisional, .ephemeral:
                    LabeledContent("알림 권한", value: "허용됨")
                case .denied:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("알림이 꺼져 있습니다")
                            .font(.scaled(13, weight: .medium))
                            .foregroundStyle(Color.loss)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("설정 열기", destination: url).font(.scaled(12.5))
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
            }
        }
        .navigationTitle("목 · 실 · 감 알림")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refresh() }
        .onChange(of: enabled) { _, on in
            Task {
                if on, status == .notDetermined {
                    await ReviewNotifications.requestAuthorization()
                }
                await refresh()
            }
        }
        .onChange(of: hour) { _, _ in Task { await refresh() } }
        .onChange(of: minute) { _, _ in Task { await refresh() } }
    }

    private func refresh() async {
        status = await ReviewNotifications.authorizationStatus()
        await DiaryNotifications.refresh(todayWritten: DiaryNotifications.todayWritten(entries))
    }
}
