import Core
import CoreData
import SwiftUI

/// **계획이 둘 이상일 때 하나만 남기는 화면** (docs/08-feedback.md 167번).
///
/// 계획은 가구에 하나여야 한다. 그런데 백업 되돌리기는 `id` 와 만든 시각을
/// 그대로 베껴 넣으므로, 되돌리기 뒤에 예전 것이 iCloud 로 되돌아오면 **같은
/// 계획이 두 객체**가 된다. 두 기기가 `createdAt` 동점을 서로 다르게 풀어
/// 각자 다른 것을 고치고 있었다 — 그래서 "제목은 안 오고 수익률은 온다" 로
/// 보였다. 새 기기의 첫 실행이 가져오기 전에 만든 빈 계획도 하나 더 있었다.
///
/// **어느 것을 남길지는 사람이 고른다.** 둘 다 고친 적이 있으면 앱은 어느
/// 값이 맞는지 모른다. 값을 나란히 보여 주고 "이 계획만 남기기" 를 누르게
/// 한다. 지운 것은 iCloud 로 퍼지므로 다른 기기도 같은 하나를 보게 된다.
struct PlanCleanupView: View {
    @Environment(\.managedObjectContext) private var context
    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]
    @State private var pendingKeep: Plan?

    var body: some View {
        Form {
            Section {
                Text(plans.count > 1
                     ? "계획이 \(plans.count)개입니다. 기기마다 다른 계획을 보고 고치고 있을 수 있습니다. 값을 견줘 보고 맞는 것 하나만 남기세요. 나머지는 지워지고, 지운 것은 다른 기기에도 1~2분 뒤 반영됩니다."
                     : "계획이 하나입니다. 정리할 것이 없습니다.")
                    .font(.scaled(12.5))
                    .foregroundStyle(Color.muted)
            }
            ForEach(Array(Plan.ordered(plans).enumerated()), id: \.element.objectID) { index, plan in
                Section {
                    row("제목", plan.title.isEmpty ? "(비어 있음)" : plan.title)
                    row("기준 시점", plan.asOfNote.isEmpty ? "(비어 있음)" : plan.asOfNote)
                    row("은퇴 연도", "\(plan.retirementYear)년")
                    row("월 적립", Won.compact(Money(minorUnits: plan.monthlyContributionMinor, currency: .krw)))
                    row("연 기대수익률", percent(plan.annualReturnBP))
                    row("은퇴 후 수익률", percent(plan.postRetirementReturnBP))
                    row("월 생활비", Won.compact(Money(minorUnits: plan.monthlySpendingMinor, currency: .krw)))
                    row("목표 금액", Won.compact(Money(minorUnits: plan.targetAmountMinor, currency: .krw)))
                    if plans.count > 1 {
                        Button("이 계획만 남기기") { pendingKeep = plan }
                    }
                } header: {
                    Text(index == 0 ? "계획 \(index + 1) · 지금 화면이 쓰는 계획" : "계획 \(index + 1)")
                } footer: {
                    Text(stamp(plan))
                        .font(.figure(11))
                        .foregroundStyle(Color.faint)
                }
            }
        }
        .navigationTitle("계획 정리")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("이 계획만 남기고 나머지 \(max(plans.count - 1, 0))개를 지울까요? 되돌릴 수 없습니다.",
                            isPresented: Binding(get: { pendingKeep != nil },
                                                 set: { if !$0 { pendingKeep = nil } }),
                            titleVisibility: .visible) {
            Button("남기고 나머지 지우기", role: .destructive) {
                if let keep = pendingKeep { keepOnly(keep) }
                pendingKeep = nil
            }
            Button("취소", role: .cancel) { pendingKeep = nil }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.figure(13))
                .multilineTextAlignment(.trailing)
        }
    }

    /// 만든 · 고친 시각과 id 꼬리. 진단 정보의 줄과 같은 꼴이라 견주기 쉽다.
    private func stamp(_ plan: Plan) -> String {
        let made = plan.createdAt.formatted(date: .numeric, time: .standard)
        let edited = plan.updatedAt.map { $0.formatted(date: .numeric, time: .standard) } ?? "고친 적 없음"
        return "만든 \(made) · 고친 \(edited) · id 꼬리 \(plan.id.uuidString.suffix(4))"
    }

    private func percent(_ basisPoints: Int) -> String {
        PercentFormatter.oneDecimal(Decimal(basisPoints) / 10_000) + "%"
    }

    /// 고른 것만 남기고 지운다. 이력에 남겨 나중에 "왜 값이 이렇지?" 의 답이 되게 한다.
    private func keepOnly(_ keep: Plan) {
        let others = plans.filter { $0.objectID != keep.objectID }
        guard !others.isEmpty else { return }
        for plan in others { context.delete(plan) }
        ChangeLogger.record(.other, subject: "계획 정리",
                            summary: "계획 \(plans.count)개 중 하나를 남기고 \(others.count)개를 지웠습니다",
                            in: context)
        try? context.save()
    }
}
