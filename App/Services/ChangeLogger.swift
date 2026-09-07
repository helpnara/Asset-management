import Foundation
import SwiftData
import UIKit

/// 무엇이 언제 바뀌었는지 남긴다 (docs/08-feedback.md 29번).
///
/// `ChangeLog` 모델은 2차부터 있었는데 **쓰는 곳이 하나도 없어서 늘 비어 있었다.**
/// "공유가 없어도 쓸모가 있다 — 지난주에 내가 무엇을 고쳤는지 돌아볼 수 있다" 고
/// 주석에 적어 놓고 그 쓸모를 안 만든 것이다. 4차(가족 공유)를 기다릴 이유가
/// 없다 — 지금부터 쌓아야 그때 볼 이력이 있다.
///
/// **전부 기록하지 않는다.** 주간 점검 · 구성 변경(계좌·종목·구성원 추가와 삭제) ·
/// 계획 값 변경 셋만 남긴다. 모든 편집을 남기면 금세 쓸모없이 길어지고,
/// 정작 "무엇이 달라졌나" 를 못 찾는다.
@MainActor
enum ChangeLogger {

    /// 남겨 두는 최대 줄 수. 주간 점검이 한 주에 한 줄이라도 몇 해면 쌓인다.
    /// 넘치면 오래된 것부터 지운다 — 이력이 저장 공간을 갉아먹으면 안 된다.
    private static let limit = 500

    /// 누가 고쳤나. 공유 전에는 이 기기다.
    ///
    /// 기기 이름에는 사람 이름이 들어가는 일이 많다. **기기 안과 개인 iCloud 에만**
    /// 남고 저장소에는 절대 커밋되지 않는다 (CLAUDE.md).
    static var actor: String { UIDevice.current.name }

    static func record(_ kind: ChangeKind, subject: String, summary: String,
                       in context: ModelContext) {
        guard !subject.isEmpty || !summary.isEmpty else { return }
        context.insert(ChangeLog(kind: kind, subject: subject, summary: summary, actor: actor))
        prune(context)
    }

    /// 계좌·종목·구성원이 늘거나 줄었을 때.
    static func structureChanged(_ what: String, _ how: String, in context: ModelContext) {
        record(.structure, subject: what, summary: how, in: context)
    }

    /// 계획 값 변경. **한 줄로 뭉친다.**
    ///
    /// 금액 칸은 글자 하나를 칠 때마다 값이 달라지므로 그대로 남기면 `410만`
    /// 하나 고치는 데 이력이 일곱 줄 생긴다. 몇 분 안의 계획 변경은 **같은
    /// 한 줄에 항목만 더한다** — 사람이 느끼기에도 그게 한 번의 편집이다.
    static func planChanged(labels: [String], in context: ModelContext) {
        guard !labels.isEmpty else { return }
        var descriptor = FetchDescriptor<ChangeLog>(
            predicate: #Predicate { $0.kindRaw == "planValue" },
            sortBy: [SortDescriptor(\.at, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        let recent = (try? context.fetch(descriptor))?.first
        if let recent, Date.now.timeIntervalSince(recent.at) < mergeWindow {
            var names = recent.summary
                .replacingOccurrences(of: " 을(를) 고쳤습니다", with: "")
                .components(separatedBy: " · ")
                .filter { !$0.isEmpty }
            for label in labels where !names.contains(label) { names.append(label) }
            recent.summary = names.joined(separator: " · ") + " 을(를) 고쳤습니다"
            recent.at = .now
            return
        }
        record(.planValue, subject: "계획",
               summary: labels.joined(separator: " · ") + " 을(를) 고쳤습니다",
               in: context)
    }

    /// 이 시간 안의 계획 변경은 한 번으로 본다.
    private static let mergeWindow: TimeInterval = 180

    private static func prune(_ context: ModelContext) {
        var descriptor = FetchDescriptor<ChangeLog>(sortBy: [SortDescriptor(\.at, order: .reverse)])
        descriptor.fetchLimit = limit * 2
        guard let logs = try? context.fetch(descriptor), logs.count > limit else { return }
        for log in logs.dropFirst(limit) { context.delete(log) }
    }
}
