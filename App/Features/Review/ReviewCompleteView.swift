import Core
import SwiftData
import SwiftUI

/// 점검 완료 — 입력의 보상.
///
/// 손으로 적는 수고에 값을 붙이는 자리다. 끝낸 직후 이번 주 변화와
/// 연속 기록을 즉시 보여준다 (ADR-0005).
struct ReviewCompleteView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    let session: ReviewSession

    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [ReviewSession]
    @Query private var snapshots: [Snapshot]

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headline
                    Rectangle().fill(Color.rule).frame(height: 1)
                    streakSection
                    memberSection
                    footer
                }
            }
            .background(Color.white)
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
                Text("가족 총자산 \(Won.abbreviated(total)) · \(session.enteredCount)건 입력")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
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
                        Text(line.memberName.isEmpty ? "이름 없음" : line.memberName)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.ink)
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

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Text("현황판에서 보기")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Color.white)
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
