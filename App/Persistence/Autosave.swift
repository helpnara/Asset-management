import CoreData
import Foundation
import SwiftUI

/// **Core Data 는 스스로 저장하지 않는다.**
///
/// SwiftData 의 `ModelContext` 는 자동 저장이었다. 4차 1b-2 에서 갈아타면서
/// 그것이 사라졌는데 **아무것도 티가 나지 않았다** — 화면은 메모리에 있는
/// 값을 그대로 보여 주기 때문이다. 앱을 켜 둔 채로는 전부 정상으로 보이고,
/// 앱이 내려간 뒤에야 적은 것이 사라져 있다.
///
/// 심판 셋이 나란히 못 잡았다:
///
///  · CI 스크린샷 — 인메모리 저장소라 애초에 저장할 일이 없다
///  · 컴파일러 — 저장을 안 부르는 것은 오류가 아니다
///  · 1c 기기 확인 — 앱을 켠 채 한 바퀴 돌아서 전부 정상으로 보였다
///
/// 갈아탈 때 **"없어진 것"은 스크린샷에 안 나온다**는 것을 여기서 배웠다.
///
/// ## 언제 저장하나
///
/// 바뀔 때마다 바로 저장하면 한 글자 칠 때마다 디스크와 iCloud 로 간다.
/// 그래서 **잠깐 모았다가** 한 번에 쓴다. 그리고 앱이 내려갈 때는 모아 둔
/// 것이 남아 있으면 안 되므로 **그 자리에서 바로** 쓴다.
@MainActor
@Observable
final class Autosave {

    static let shared = Autosave()

    /// 마지막 저장이 실패했다면 그 이유. 더보기 → 동기화에 그대로 보여 준다.
    ///
    /// "저장되고 있다고 생각했는데 아니었다"가 이 앱에서 제일 위험한 상태라,
    /// 조용히 삼키지 않는다.
    private(set) var lastFailure: String?

    private var context: NSManagedObjectContext?
    private var pending: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    private init() {}

    /// 앱이 뜰 때 한 번 건다.
    func start(_ context: NSManagedObjectContext) {
        guard observer == nil else { return }
        self.context = context
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSave() }
        }
    }

    /// 앱이 내려가기 직전 · 잠글 때. 모아 둔 것을 그 자리에서 쓴다.
    func flush() {
        pending?.cancel()
        pending = nil
        saveNow()
    }

    /// **알림 안에서 바로 저장하지 않는다.** 저장은 다시 변경 알림을 부르고,
    /// 그 안에서 또 저장하면 재진입한다. 한 박자 뒤로 미루면서 겸사겸사
    /// 연속된 변경을 하나로 모은다.
    private func scheduleSave() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func saveNow() {
        guard let context else { return }

        // 새로 만든 것을 가구에 매다는 자리다 (docs/09-family-sharing.md 2단계).
        // 저장 직전이어야 한다 — 그래야 한 곳도 안 샌다.
        Household.attachNew(in: context)

        guard context.hasChanges else { return }
        do {
            try context.save()
            lastFailure = nil
        } catch {
            let ns = error as NSError
            lastFailure = "\(ns.domain) \(ns.code) "
                + (ns.localizedFailureReason ?? ns.localizedDescription)
        }
    }
}
