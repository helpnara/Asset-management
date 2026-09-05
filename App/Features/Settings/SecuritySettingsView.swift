import Core
import SwiftUI

/// 잠금 · 가리기 · 알림 금액 노출.
///
/// 셋은 목적이 다르다. **잠금은 남이 내 폰을 여는 것**을, **가리기는 어깨 너머를**,
/// **알림 설정은 잠금 화면에 뜨는 글**을 막는다. 한 스위치로 묶으면 하나를 켜려고
/// 나머지까지 켜게 된다.
struct SecuritySettingsView: View {
    @AppStorage("security.appLock") private var appLock = false
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false
    @AppStorage(ReviewSettings.notificationAmountKey) private var showsAmountInNotification = false

    var body: some View {
        Form {
            Section {
                Toggle("\(AppLock.biometryLabel)로 잠그기", isOn: $appLock)
                    .disabled(!AppLock.isBiometryAvailable)
            } header: {
                Text("앱 잠금")
            } footer: {
                if AppLock.isBiometryAvailable {
                    Text("앱을 열 때와 백그라운드에서 돌아올 때 인증합니다. 인증이 실패하면 기기 암호로 넘어갑니다.")
                } else {
                    Text("이 기기에서는 생체 인증을 쓸 수 없습니다. 설정 앱에서 Face ID 또는 암호를 먼저 등록하세요.")
                }
            }

            Section {
                Toggle("금액 가리기", isOn: $hideAmounts)
            } header: {
                Text("어깨 너머")
            } footer: {
                Text("화면의 모든 금액이 ••••로 바뀝니다. 입력 칸은 가리지 않습니다 — 입력 중에 가려지면 고칠 수 없습니다. 인증 없이 언제든 켜고 끌 수 있습니다.")
            }

            Section {
                Toggle("알림에 금액 표시", isOn: $showsAmountInNotification)
            } header: {
                Text("알림")
            } footer: {
                Text("주간 점검 알림에서 총액만 기록했을 때 그 금액을 알림에 보여줄지 정합니다. 알림은 잠긴 화면에도 뜹니다 — 기본은 표시하지 않음입니다.")
            }
        }
        .navigationTitle("잠금 · 가리기")
        .navigationBarTitleDisplayMode(.inline)
    }
}
