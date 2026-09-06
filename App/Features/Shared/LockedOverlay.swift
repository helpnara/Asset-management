import SwiftUI
import UIKit

/// 잠금 화면. 인증을 통과하기 전까지 아무것도 보여주지 않는다.
///
/// **막다른 길을 만들지 않는다.** 생체 인증이 막히고 기기 암호도 없으면
/// 자기 기록에서 잠긴다 — 잠금을 끄려면 앱을 열어야 하는데 앱이 안 열린다.
/// 그래서 인증할 방법이 아예 없을 때만 잠금을 끄고 들어가는 길을 보여준다
/// (docs/08-feedback.md 4번).
struct LockedOverlay: View {
    @State private var lock = AppLock.shared
    @State private var isAsking = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color.faint)

            Text("느 린 부 자 의 기 록")
                .eyebrowStyle()

            Text("잠겨 있습니다")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)

            if let error = lock.lastError {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.loss)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Task {
                    isAsking = true
                    await lock.unlock()
                    isAsking = false
                }
            } label: {
                Text(isAsking ? "인증 중…" : "\(AppLock.biometryLabel)로 열기")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.onInk)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ink)
            .disabled(isAsking)
            .padding(.top, 4)

            if lock.isLockedOut {
                // 여기까지 왔다는 것은 기기 암호조차 없다는 뜻이다. 그런 기기는
                // 어차피 아무나 열 수 있으므로 이 잠금이 지키는 것이 없다.
                VStack(spacing: 8) {
                    Text("이 기기로는 본인 확인을 할 수 없습니다.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.muted)
                    Button("잠금을 끄고 들어가기") { lock.disableLockAndEnter() }
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.top, 10)
            } else if lock.lastError != nil {
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 13))
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .task {
            // 화면이 뜨자마자 한 번 물어본다. 버튼을 또 누르게 하지 않는다.
            guard !lock.isUnlocked, !isAsking else { return }
            isAsking = true
            await lock.unlock()
            isAsking = false
        }
    }
}
