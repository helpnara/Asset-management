import Core
import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: \Member.sortIndex) private var members: [Member]
    @Query private var holdings: [Holding]

    private var rollup: Rollup {
        Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Rectangle().fill(Color.ink).frame(height: 2)

                    if members.isEmpty {
                        emptyState
                    } else {
                        hero
                        Rectangle().fill(Color.rule).frame(height: 1)
                            .padding(.horizontal, 20)
                        weeklyBar
                        memberBreakdown
                        totals
                    }
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("느 린 부 자 의 기 록").eyebrowStyle()
            Text("우리 가족 노후자금 준비")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("가 족 총 자 산").eyebrowStyle().padding(.bottom, 7)
            Text(KoreanAmountFormatter.abbreviated(rollup.netWorth, suffix: "원"))
                .font(.figure(38, weight: .semibold))
                .foregroundStyle(Color.ink)
            if !rollup.liabilities.isZero {
                Text("자산 \(KoreanAmountFormatter.abbreviated(rollup.assets)) · 부채 \(KoreanAmountFormatter.abbreviated(rollup.liabilities))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.muted)
                    .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var weeklyBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("아직 점검 기록이 없습니다")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
                Text("매주 토요일에 알려드립니다")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Color.surface)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var memberBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("구성원", trailing: "\(members.count)명")
            Rectangle().fill(Color.rule).frame(height: 1)
            ForEach(members) { member in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(member.name.isEmpty ? "이름 없음" : member.name)
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(Color.ink)
                            Text("\(member.roleNote.isEmpty ? "" : member.roleNote + " · ")\(member.age)세")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.faint)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(KoreanAmountFormatter.abbreviated(rollup.byMember[member.id] ?? .zero(.krw)))
                        .font(.figure(15, weight: .semibold))
                        .foregroundStyle(Color.member(member.colorIndex))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                Rectangle().fill(Color.rule).frame(height: 1)
            }
        }
    }

    private var totals: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("가족 합계")
            Rectangle().fill(Color.rule).frame(height: 1)
            totalRow("투자자산", rollup.investable)
            totalRow("총자산", rollup.assets, emphasized: true)
            if !rollup.liabilities.isZero {
                totalRow("부채", rollup.liabilities)
            }
            countrySplit
        }
        .padding(.bottom, 28)
    }

    @ViewBuilder
    private var countrySplit: some View {
        let korea = rollup.countryShare("KR")
        let usa = rollup.countryShare("US")
        if let korea, let usa, !rollup.investable.isZero {
            VStack(spacing: 7) {
                HStack {
                    Text("한국 \(percentText(korea))")
                    Spacer()
                    Text("미국 \(percentText(usa))")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Color.muted)

                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.mom)
                            .frame(width: proxy.size.width * fraction(korea))
                        Rectangle().fill(Color.dad)
                    }
                }
                .frame(height: 5)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }

    private func fraction(_ value: Decimal) -> CGFloat {
        CGFloat(NSDecimalNumber(decimal: value).doubleValue)
    }

    private func percentText(_ value: Decimal) -> String {
        let tenths = NSDecimalNumber(decimal: value * 1000).intValue
        return "\(tenths / 10).\(abs(tenths % 10))"
    }

    private func totalRow(_ label: String, _ money: Money, emphasized: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: emphasized ? .medium : .regular))
                    .foregroundStyle(emphasized ? Color.ink : Color.muted)
                Spacer()
                Text(KoreanAmountFormatter.full(money))
                    .font(.figure(12.5, weight: emphasized ? .bold : .medium))
                    .foregroundStyle(Color.ink)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            Rectangle().fill(Color.rule).frame(height: 1)
        }
    }

    private func sectionHeader(_ title: String, trailing: String = "") -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.ink)
            Spacer()
            Text(trailing)
                .font(.system(size: 10))
                .foregroundStyle(Color.faint)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("아직 등록된 자산이 없습니다")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.ink)
            Text("자산 탭에서 구성원을 먼저 추가하세요.\n한 명 · 한 종목만 넣어도 합계가 그려집니다.")
                .font(.system(size: 12.5))
                .foregroundStyle(Color.muted)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .padding(.top, 40)
    }
}
