import Core
import CoreData
import StoreKit
import SwiftUI

/// 점검 완료 — 입력의 보상.
///
/// 손으로 적는 수고에 값을 붙이는 자리다. 끝낸 직후 이번 주 변화와
/// 연속 기록을 즉시 보여준다 (ADR-0005).
struct ReviewCompleteView: View {
    @Fetched(sort: \Member.sortIndex) private var driftMembers: [Member]
    @Fetched(sort: \Plan.createdAt) private var driftPlans: [Plan]

    /// 목표에서 벗어난 종목 수. 가족 전체를 센다.
    private var driftCount: Int {
        let tolerance = driftPlans.first?.driftTolerance ?? Allocation.Tolerance()
        return driftMembers.reduce(0) { $0 + $1.driftingHoldingCount(tolerance: tolerance) }
    }

    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    let session: ReviewSession

    @Environment(\.dismiss) private var dismiss
    /// 별점 창은 **축하가 있는 주에만** 띄운다 (docs/10 §3-4). 아무 때나 띄우면
    /// 별 셋, 기쁜 순간에 띄우면 별 다섯이다. 애플이 1년에 세 번으로 막으므로
    /// 우리 쪽에서도 90일에 한 번만 청한다.
    @Environment(\.requestReview) private var requestReview
    @Fetched private var sessions: [ReviewSession]
    @Fetched private var snapshots: [Snapshot]
    @Fetched(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    /// 이 주의 축하 (88번).
    @Fetched(sort: \ChangeLog.at, order: .reverse) private var logs: [ChangeLog]
    @Fetched(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]

    /// 화면의 모든 숫자를 이 스냅샷 하나에서 읽는다.
    /// 현재 값과 섞으면 과거 점검을 열었을 때 총액과 구성원별 합이 어긋난다.
    private var snapshot: Snapshot? {
        snapshots.first { $0.weekAnchor == session.weekAnchor }
    }

    private var streak: Int {
        ReviewWeek.streak(
            completedAnchors: sessions.filter(\.isComplete).map(\.weekAnchor),
            asOf: .now
        )
    }

    private var change: Money { Money(minorUnits: session.changeMinor, currency: .krw) }
    private var total: Money { Money(minorUnits: session.totalValueMinor, currency: .krw) }
    private var isFirstEver: Bool { session.previousTotalValueMinor == 0 }

    private static let reviewAskedKey = "review.lastAskedAt"

    /// 축하 화면이 뜬 지 1.5초 뒤, 90일에 한 번.
    private func askForReviewIfDue() async {
        let last = UserDefaults.standard.object(forKey: Self.reviewAskedKey) as? Date ?? .distantPast
        guard Date.now.timeIntervalSince(last) > 90 * 86_400 else { return }
        guard SampleData.isActive == false else { return }
        try? await Task.sleep(for: .seconds(1.5))
        UserDefaults.standard.set(Date.now, forKey: Self.reviewAskedKey)
        requestReview()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headline
                    Rectangle().fill(Color.rule).frame(height: 1)
                    celebrations
                    streakSection
                    memberSection
                    footer
                }
            }
            .background(Color.canvas)
            .navigationTitle("점검 완료")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("이 번 주 변 화").eyebrowStyle().padding(.bottom, 7)

            if isFirstEver {
                Text(Won.abbreviated(total, suffix: "원"))
                    .font(.figure(34, weight: .semibold))
                    .foregroundStyle(Color.ink)
                Text("첫 기록입니다. 다음 주부터 증감이 보입니다.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 9)
            } else {
                Text(Won.abbreviated(change, suffix: "원", sign: .always))
                    .font(.figure(34, weight: .semibold))
                    .foregroundStyle(session.changeMinor < 0 ? Color.loss : Color.gain)
                Text("\(driftMembers.count > 1 ? "가족 총자산" : "총자산") \(Won.abbreviated(total)) · \(session.enteredCount)건 입력")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 9)

                // **계획선 위인가 아래인가** (docs/08-feedback.md 46번).
                // 숫자를 막 적고 난 이 순간이 그 사실을 볼 가장 좋은 자리다 —
                // 로드맵 M2 도 "점검 완료 화면 포함" 이라고 적어 두었는데
                // 37번에서는 현황판에만 붙이고 여기를 빠뜨렸다.
                if let gap = planGap {
                    Text(gap.text)
                        .font(.figure(12.5, weight: .medium))
                        .foregroundStyle(gap.isAhead ? Color.gain : Color.loss)
                        .padding(.top, 6)
                }

                if driftCount > 0 {
                    // 이번 주 입력으로 비중이 어긋난 것이 있으면 여기서 한 번 더
                    // 말한다. 점검을 마치고 나가는 길목이라 놓치기 어렵다
                    // (docs/08-feedback.md 14번).
                    Text("비중이 어긋난 종목 \(driftCount)개")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.loss)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    /// 이 점검 시점의 총액을 계획선과 견준다. 지난 점검을 열어 봐도
    /// **그때 기준**으로 맞게 나온다 — 화면의 다른 숫자와 같은 규칙이다.
    private var planGap: PlanTrack.Gap? {
        let projection = PlanTrack.projection(plan: driftPlans.first, snapshots: snapshots,
                                              cashEvents: cashEvents, incomes: incomes,
                                              members: driftMembers)
        return PlanTrack.gap(projection, actual: total, at: session.weekAnchor)
    }

    /// 이 점검 주에 넘긴 선들. 지난 점검을 열어 봐도 그 주의 것이 나온다.
    @ViewBuilder
    private var celebrations: some View {
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: session.weekAnchor) ?? session.weekAnchor
        let items = logs.filter { $0.kind == .milestone && $0.at >= session.weekAnchor && $0.at < weekEnd }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Color.clear.frame(height: 0)
                    .task { await askForReviewIfDue() }
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("🎉")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.subject)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.ink)
                            Text(item.summary)
                                .font(.system(size: 11))
                                .foregroundStyle(Color.muted)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gainSoft)
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }

    private var streakSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("연속 기록")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Text("\(streak)주")
                    .font(.figure(13, weight: .bold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 12)

            HStack(spacing: 4) {
                ForEach(0..<min(max(streak, 1), 16), id: \.self) { offset in
                    Rectangle()
                        .fill(Color.ink.opacity(0.25 + 0.75 * Double(offset + 1) / Double(max(streak, 1))))
                        .frame(width: 9, height: 9)
                        .cornerRadius(1.5)
                }
                Spacer()
            }
            .padding(.horizontal, 20)

            Text(streak <= 1
                 ? "다음 토요일에 또 적으면 연속 기록이 시작됩니다."
                 : "\(streak)주째 거르지 않았습니다.")
                .font(.system(size: 10))
                .foregroundStyle(Color.faint)
                .padding(.horizontal, 20)
                .padding(.top, 9)
        }
    }

    @ViewBuilder
    private var memberSection: some View {
        let lines = snapshot?.sortedLines ?? []
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("구성원별")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.ink)
                    Spacer()
                    Text("이 점검 시점 기준")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.faint)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 8)

                Rectangle().fill(Color.rule).frame(height: 1)

                ForEach(lines) { line in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.memberName.isEmpty ? "이름 없음" : line.memberName)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.ink)
                            // 이 주에 그 사람 몫이 적혔나, 몇 주째인가 (C8).
                            Text(memberLine(line.memberID))
                                .font(.system(size: 9.5))
                                .foregroundStyle(Color.faint)
                        }
                        Spacer()
                        Text(Won.abbreviated(Money(minorUnits: line.valueMinor, currency: .krw)))
                            .font(.figure(12.5, weight: .medium))
                            .foregroundStyle(Color.member(line.sortIndex))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    Rectangle().fill(Color.rule).frame(height: 1)
                }
            }
        }
    }

    /// 이 점검 시점 기준이다 — 지난 점검을 열어 봐도 그때의 연속 주가 나온다.
    private func memberLine(_ memberID: UUID) -> String {
        let entered = session.enteredMemberIDSet.contains(memberID)
        let streak = ReviewSession.memberStreak(memberID, sessions: sessions, asOf: session.weekAnchor)
        if !entered { return streak > 0 ? "이번 주 안 적음 · 지난 \(streak)주 연속" : "이번 주 안 적음" }
        return streak > 1 ? "\(streak)주 연속" : "이번 주 적음"
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Text("현황판에서 보기")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.onInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 3))
            }
            Text("다음 점검 \(nextReviewText) 토요일")
                .font(.system(size: 10))
                .foregroundStyle(Color.faint)
        }
        .padding(20)
    }

    private var nextReviewText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd"
        return formatter.string(from: ReviewWeek.nextSaturday(after: .now))
    }

}
