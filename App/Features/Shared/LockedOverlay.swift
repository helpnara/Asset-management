import SwiftUI

/// 잠금 화면. 인증을 통과하기 전까지 아무것도 보여주지 않는다.
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
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.ink)
            .disabled(isAsking)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .task {
            // 화면이 뜨자마자 한 번 물어본다. 버튼을 또 누르게 하지 않는다.
            guard !lock.isUnlocked, !isAsking else { return }
            isAsking = true
            await lock.unlock()
            isAsking = false
        }
    }
}
