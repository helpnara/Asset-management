import SwiftUI

/// 첫 실행에 한 번만 뜬다.
///
/// 존재 이유는 하나다 — **알림 권한을 여기서 묻는다.** 이 앱은 외부에서 자료를
/// 가져오지 않으므로 토요일 알림이 유일한 시작 계기다. 권한을 묻지 않으면
/// iOS 는 알림을 조용히 버리고, 사용자는 앱을 열 이유를 영영 못 받는다.
/// 설정 화면 깊숙이 묻어 두면 아무도 찾지 않는다.
struct WelcomeView: View {
    let onFinish: () -> Void

    @State private var isAsking = false
    @State private var didAsk = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)

            Text("느 린 부 자 의 기 록")
                .eyebrowStyle()
            Text("매주 토요일,\n숫자 하나씩 적어 갑니다")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color.ink)
                .lineSpacing(6)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 18) {
                point("직접 적습니다",
                      "시세를 외부에서 가져오지 않습니다. 손으로 적는 그 수고가 계획 대비 실적을 체감하게 합니다.")
                point("토요일에 부릅니다",
                      "정한 요일·시각에 알림이 옵니다. 알림에서 총액만 먼저 적고 넘어갈 수도 있습니다.")
                point("은퇴까지 이어 그립니다",
                      "적어 넣은 기록이 계획선 위인지 아래인지 궤적으로 보여 줍니다.")
            }
            .padding(.top, 28)

            Spacer(minLength: 24)

            VStack(spacing: 10) {
                Button {
                    Task {
                        isAsking = true
                        await ReviewNotifications.requestAuthorization()
                        isAsking = false
                        didAsk = true
                        onFinish()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isAsking { ProgressView().controlSize(.small).tint(.white) }
                        Text("토요일 알림 받기")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.ink)
                .disabled(isAsking || didAsk)

                Button("나중에 하기") { onFinish() }
                    .font(.system(size: 13))
                    .foregroundStyle(Color.muted)
                    .disabled(isAsking)

                // 거절해도 막다른 길이 아니라는 것을 먼저 알려 준다.
                Text("나중에 [더보기 → 주간 점검 알림]에서 켤 수 있습니다.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.faint)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private func point(_ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.dad)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
