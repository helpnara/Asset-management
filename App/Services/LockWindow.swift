import SwiftUI
import UIKit

/// **잠금 · 가림막을 별도 창으로 띄운다** (docs/08-feedback.md 194번 P1 · P4).
///
/// 잠금 화면은 원래 `RootView` 와 같은 `ZStack` 안에 있었다. 그런데 시트 ·
/// 전체 화면 · 공유 시트 · 알림창은 UIKit 이 그 **위에** 따로 띄운다. 그래서
/// 주간 점검 시트를 연 채 홈에 다녀오면 Face ID 창 뒤로 시트 속 금액이 보였고,
/// 잠긴 앱에서 알림을 누르면 점검 화면이 잠금 위에 열렸다.
///
/// 이 창은 알림창보다 한 층 높다(`.alert + 1`). 앱 안에서 무엇이 떠 있든 덮는다.
/// 앱 화면 안의 잠금(`SlowRichApp` 의 `LockedOverlay`)은 그대로 둔다 — 이 창이
/// 붙기 전 첫 화면을 덮는 안전망이다.
@MainActor
final class LockWindow {
    static let shared = LockWindow()

    enum Cover: Equatable {
        /// 아무것도 안 덮는다.
        case none
        /// 앱 전환기 · 제어 센터에 올라간 동안의 가림막. 인증을 건드리지 않는다 —
        /// `.inactive` 는 Face ID 창이 뜰 때도 오므로, 거기서 잠그면 인증이 스스로
        /// 취소된다 (docs/08-feedback.md 4번). 그래서 가리기만 한다.
        case privacy
        /// 잠금 화면 — 인증 단추가 있다.
        case lock
    }

    private struct Entry {
        let window: UIWindow
        var cover: Cover
    }

    private var entries: [ObjectIdentifier: Entry] = [:]

    private init() {}

    func show(_ cover: Cover) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let live = Set(scenes.map { ObjectIdentifier($0) })
        // 닫힌 창(아이패드 여러 창)의 몫은 버린다.
        for key in entries.keys where !live.contains(key) {
            entries[key]?.window.isHidden = true
            entries[key] = nil
        }

        if cover == .lock {
            // 아래 시트에 키보드가 올라와 있으면 내린다 — 키보드 창은 이 창보다 높다.
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }

        for scene in scenes {
            let key = ObjectIdentifier(scene)
            guard cover != .none else {
                entries[key]?.window.isHidden = true
                entries[key] = nil
                continue
            }
            if var entry = entries[key] {
                // 같은 화면이면 다시 만들지 않는다 — 잠금 화면은 뜰 때 인증을 한 번
                // 묻는데(`.task`), 다시 만들면 그 물음이 겹친다.
                if entry.cover != cover {
                    entry.window.rootViewController = Self.controller(for: cover)
                    entry.cover = cover
                    entries[key] = entry
                }
                entry.window.isHidden = false
            } else {
                let window = UIWindow(windowScene: scene)
                window.windowLevel = .alert + 1
                window.backgroundColor = .clear
                window.rootViewController = Self.controller(for: cover)
                window.isHidden = false
                entries[key] = Entry(window: window, cover: cover)
            }
        }
    }

    private static func controller(for cover: Cover) -> UIViewController {
        let controller: UIViewController
        switch cover {
        case .lock: controller = UIHostingController(rootView: LockedOverlay())
        case .privacy, .none: controller = UIHostingController(rootView: PrivacyCover())
        }
        controller.view.backgroundColor = .clear
        return controller
    }
}

/// 앱 전환기 미리보기에 남는 그림. 금액 대신 이름만 보인다.
struct PrivacyCover: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.scaled(34, weight: .light))
                .foregroundStyle(Color.faint)
            Text("느 린 부 자")
                .eyebrowStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas)
        .ignoresSafeArea()
    }
}
