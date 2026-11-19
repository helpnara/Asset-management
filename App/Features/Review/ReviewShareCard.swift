import Core
import SwiftUI
import UIKit

/// **점검 완료를 그림 한 장으로** (219번 G, 11-19 사용자 — 가족 단톡에 올리기).
///
/// 회고의 `그림으로 공유`(`RetrospectiveCard` · `ImageRenderer`)와 같은 길이다. 그림은 **가리기를
/// 거치지 않는다** — 공유하려고 만든 것이니 숫자가 있어야 한다(회고와 같은 규칙, 단추 아래에 적는다).
/// 화면의 값은 관리 객체가 아니라 이 `Content` 로 받는다 — 그리는 동안 자료가 바뀌어도 어긋나지 않게.
struct ReviewShareCard: View {
    struct MemberLine: Identifiable {
        let id: UUID
        let name: String
        let value: Money
        let colorIndex: Int
    }

    struct Content {
        let weekAnchor: Date
        let isFirst: Bool
        let change: Money
        let total: Money
        let totalLabel: String
        let enteredCount: Int
        let gap: PlanTrack.Gap?
        let streak: Int
        let members: [MemberLine]
        let movers: WeeklyMovers.Result?
    }

    let content: Content

    // 종이는 흰 바탕에 검정이다 — 회고 그림과 같은 색.
    private let ink = Color(hex: 0x0B1017)
    private let muted = Color(hex: 0x5B6670)
    private let rule = Color(hex: 0xE3E7EA)
    private let gain = Color(hex: 0x2A7A66)
    private let loss = Color(hex: 0x8E4650)
    private let brand = Color(hex: 0x1F5640)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("주간 점검 · \(DateText.full(content.weekAnchor))")
                .font(.scaled(11, weight: .semibold))
                .foregroundStyle(muted)
                .padding(.bottom, 6)
            headline
            if let movers = content.movers, !movers.isEmpty {
                divider
                moverRows(movers)
            }
            if !content.members.isEmpty {
                divider
                memberRows
            }
            divider
            HStack {
                Text("연속 기록")
                    .font(.scaled(12))
                    .foregroundStyle(muted)
                Spacer()
                Text("\(content.streak)주")
                    .font(.figure(12, weight: .semibold))
                    .foregroundStyle(ink)
            }
            // 공유 그림 맨 아래 한 줄 (docs/10 §3-5) — 카톡으로 간 그림이 이 앱이 알려지는 길이다.
            HStack {
                Spacer()
                Text("느린 부자")
                    .font(.scaled(11, weight: .medium))
                    .foregroundStyle(brand)
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
    }

    private var divider: some View {
        Rectangle().fill(rule).frame(height: 1).padding(.vertical, 12)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            if content.isFirst {
                Text(KoreanAmountFormatter.abbreviated(content.total, suffix: "원"))
                    .font(.figure(30, weight: .semibold))
                    .foregroundStyle(ink)
                Text("첫 기록")
                    .font(.scaled(12))
                    .foregroundStyle(muted)
            } else {
                Text(KoreanAmountFormatter.abbreviated(content.change, suffix: "원", sign: .always))
                    .font(.figure(30, weight: .semibold))
                    .foregroundStyle(content.change.isNegative ? loss : gain)
                Text("\(content.totalLabel) \(KoreanAmountFormatter.abbreviated(content.total)) · \(content.enteredCount)건 입력")
                    .font(.figure(12))
                    .foregroundStyle(muted)
                if let gap = content.gap {
                    Text(Self.gapText(gap))
                        .font(.figure(12, weight: .medium))
                        .foregroundStyle(gap.isAhead ? gain : loss)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// 가리기를 거치지 않은 계획 대비 — `PlanTrack.Gap.text` 와 같은 말, 숫자만 그대로.
    static func gapText(_ gap: PlanTrack.Gap) -> String {
        let size = KoreanAmountFormatter.abbreviated(
            Money(minorUnits: abs(gap.delta.minorUnits), currency: .krw), suffix: "원")
        if gap.isWithinBand { return "계획선 위에 있습니다" }
        return gap.isAhead ? "계획보다 \(size) 앞서 있습니다" : "계획보다 \(size) 뒤에 있습니다"
    }

    private func moverRows(_ movers: WeeklyMovers.Result) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("많이 움직인 종목")
                .font(.scaled(12, weight: .semibold))
                .foregroundStyle(ink)
            ForEach(movers.gains + movers.losses) { item in
                HStack {
                    Text(item.name)
                        .font(.scaled(12))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Spacer()
                    Text(KoreanAmountFormatter.compact(item.delta, sign: .always))
                        .font(.figure(12, weight: .medium))
                        .foregroundStyle(item.delta.isNegative ? loss : gain)
                }
            }
        }
    }

    private var memberRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(content.members) { member in
                HStack(spacing: 6) {
                    Circle().fill(Color.member(member.colorIndex)).frame(width: 7, height: 7)
                    Text(member.name)
                        .font(.scaled(12))
                        .foregroundStyle(ink)
                    Spacer()
                    Text(KoreanAmountFormatter.compact(member.value))
                        .font(.figure(12, weight: .medium))
                        .foregroundStyle(ink)
                }
            }
        }
    }

    /// 그림으로 만들어 공유 시트를 띄운다 — 회고의 `share()` 와 같은 순서.
    @MainActor
    static func share(_ content: Content) {
        let renderer = ImageRenderer(content:
            ReviewShareCard(content: content)
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
