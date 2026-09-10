import Core
import CoreData
import SwiftUI
import UIKit

/// **월간 · 연간 회고** (docs/08-feedback.md 86 · 87번, C4 · C5).
///
/// "9월 요약: +N · 넣은 N · 자란 N · 점검 4/4주 · 조치 3→2" — 매주 점검의
/// 보상이 한 달 단위로도 있어야 계속 쓴다. 연간은 같은 틀의 연말 결산이다.
/// 계산은 `Retrospective.summarize` 가 하고, 이 화면과 공유용 그림이 같은 값을 쓴다.
struct RetrospectiveView: View {
    @Fetched(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]
    @Fetched private var sessions: [ReviewSession]
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]
    @Fetched(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Fetched(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Fetched(sort: \DiaryEntry.day, order: .reverse) private var diary: [DiaryEntry]
    @Fetched(sort: \ChangeLog.at, order: .reverse) private var logs: [ChangeLog]

    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @State private var scope: Retrospective.Scope = .month
    /// 월간은 지난달에서, 연간은 올해에서 시작한다 — 회고는 뒤를 본다.
    @State private var monthOffset = -1
    @State private var yearOffset = 0

    private var period: Retrospective.Period {
        Retrospective.Period.containing(.now, scope: scope,
                                        offset: scope == .month ? monthOffset : yearOffset)
    }

    private var summary: Retrospective.Summary {
        Retrospective.summarize(period: period, snapshots: snapshots, sessions: sessions,
                                members: members, plan: plans.first, cashEvents: cashEvents,
                                incomes: incomes, diary: diary, logs: logs)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("범위", selection: $scope) {
                    ForEach(Retrospective.Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                periodBar
                RetrospectiveCard(summary: summary)

                Button {
                    share()
                } label: {
                    Label("그림으로 공유", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(Color.ink)
                .disabled(!summary.hasRecords)

                Text("넣은 돈은 계획의 월 적립을 날수로 나눠 어림한 값입니다. 그림에는 금액이 그대로 나옵니다 — 가리기가 켜져 있어도요.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.faint)
                    .lineSpacing(3)
            }
            .padding(16)
        }
        .background(Color.ground)
        .navigationTitle("회고")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var periodBar: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(period.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.ink)
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(period.isCurrent())
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 4)
    }

    private func step(_ delta: Int) {
        if scope == .month { monthOffset += delta } else { yearOffset += delta }
    }

    /// 그림으로 만들어 공유 시트를 띄운다. 그림은 **가리기를 거치지 않는다** —
    /// 공유하려고 만든 것이니 숫자가 있어야 한다.
    private func share() {
        let renderer = ImageRenderer(content:
            RetrospectiveCard(summary: summary, forPrint: true)
                .frame(width: 420)
                .padding(20)
                .background(Color.white)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        guard let top = FamilyShareSheet.topViewController() else { return }
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
    }
}

/// 회고 한 장. 화면과 공유 그림이 같은 부품을 쓴다. `forPrint` 면 가리기를
/// 거치지 않고 종이 색으로 그린다.
struct RetrospectiveCard: View {
    let summary: Retrospective.Summary
    var forPrint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(summary.period.title).eyebrowStyle().padding(.bottom, 6)
            if summary.hasRecords {
                headline
                Rectangle().fill(rule).frame(height: 1).padding(.vertical, 12)
                attributionRows
                Rectangle().fill(rule).frame(height: 1).padding(.vertical, 12)
                reviewRows
                if !summary.members.isEmpty {
                    Rectangle().fill(rule).frame(height: 1).padding(.vertical, 12)
                    memberRows
                }
                if !summary.milestones.isEmpty {
                    Rectangle().fill(rule).frame(height: 1).padding(.vertical, 12)
                    milestoneRows
                }
            } else {
                Text("이 기간에는 기록이 없습니다")
                    .font(.system(size: 13))
                    .foregroundStyle(muted)
                    .padding(.vertical, 20)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(forPrint ? Color.white : Color.raised,
                    in: RoundedRectangle(cornerRadius: forPrint ? 0 : 12, style: .continuous))
    }

    // 종이는 흰 바탕에 검정이다. 화면은 팔레트를 따른다.
    private var ink: Color { forPrint ? Color(hex: 0x0B1017) : .ink }
    private var muted: Color { forPrint ? Color(hex: 0x5B6670) : .muted }
    private var rule: Color { forPrint ? Color(hex: 0xE3E7EA) : .rule }
    private var gain: Color { forPrint ? Color(hex: 0x2A7A66) : .gain }
    private var loss: Color { forPrint ? Color(hex: 0x8E4650) : .loss }

    private func money(_ value: Money, sign: KoreanAmountFormatter.SignStyle = .negativeOnly) -> String {
        forPrint ? KoreanAmountFormatter.compact(value, sign: sign) : Won.compact(value, sign: sign)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let change = summary.attribution?.change {
                Text((forPrint ? KoreanAmountFormatter.abbreviated(change, suffix: "원", sign: .always)
                               : Won.abbreviated(change, suffix: "원", sign: .always)))
                    .font(.figure(30, weight: .semibold))
                    .foregroundStyle(change.isNegative ? loss : gain)
            } else if let end = summary.endTotal {
                Text(forPrint ? KoreanAmountFormatter.abbreviated(end, suffix: "원") : Won.abbreviated(end, suffix: "원"))
                    .font(.figure(30, weight: .semibold))
                    .foregroundStyle(ink)
            }
            if let base = summary.baseTotal, let end = summary.endTotal {
                Text("\(money(base)) → \(money(end))")
                    .font(.figure(12))
                    .foregroundStyle(muted)
            } else if summary.endTotal != nil {
                Text("이 기간 앞의 기록이 없어 증감을 낼 수 없습니다")
                    .font(.system(size: 11))
                    .foregroundStyle(muted)
            }
            if let text = summary.planGapText {
                Text(text)
                    .font(.figure(12, weight: .medium))
                    .foregroundStyle(summary.planGapIsAhead ? gain : loss)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var attributionRows: some View {
        if let split = summary.attribution {
            HStack(spacing: 0) {
                stat("증감", money(split.change, sign: .always), split.change.isNegative ? loss : gain)
                stat("넣은 돈", money(split.contributed, sign: .always), ink)
                stat("자란 돈", money(split.gained, sign: .always), split.gained.isNegative ? loss : gain)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(muted)
            Text(value)
                .font(.figure(14, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var reviewRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            line("주간 점검", "\(summary.reviewedWeeks) / \(summary.weeksInPeriod)주"
                 + (summary.totalOnlyWeeks > 0 ? " · 총액만 \(summary.totalOnlyWeeks)주" : ""))
            line("목 · 실 · 감", "\(summary.diaryDays)일 적음")
            if summary.structureChanges + summary.planChanges > 0 {
                line("바꾼 것", "계좌·종목 \(summary.structureChanges)건 · 계획 \(summary.planChanges)건")
            }
        }
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(muted)
            Spacer()
            Text(value)
                .font(.figure(12, weight: .medium))
                .foregroundStyle(ink)
        }
    }

    private var memberRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(summary.members) { member in
                HStack(spacing: 6) {
                    Circle().fill(Color.member(member.colorIndex)).frame(width: 7, height: 7)
                    Text(member.name)
                        .font(.system(size: 12))
                        .foregroundStyle(ink)
                    Text("\(member.enteredWeeks)주 적음")
                        .font(.system(size: 9.5))
                        .foregroundStyle(muted)
                    Spacer()
                    if let change = member.change {
                        Text(money(change, sign: .always))
                            .font(.figure(12, weight: .medium))
                            .foregroundStyle(change.isNegative ? loss : gain)
                    }
                    if let end = member.end {
                        Text(money(end))
                            .font(.figure(12, weight: .medium))
                            .foregroundStyle(ink)
                            .frame(minWidth: 64, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var milestoneRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(summary.milestones, id: \.self) { title in
                HStack(spacing: 6) {
                    Text("🎉")
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink)
                }
            }
        }
    }
}
