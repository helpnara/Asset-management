import Core
import SwiftUI

/// A4 한 장. `ImageRenderer` 가 이걸 그려서 PNG 로 만든다.
///
/// **색은 `Paper` 고정 팔레트를 쓴다.** 화면이 다크여도 인쇄물은 흰 종이여야
/// 한다. 적응형 토큰(`Color.ink` 등)을 쓰면 다크 모드에서 검은 종이가 나온다.
///
/// 화면용 뷰를 그대로 쓰지 않는 이유는 **스크롤이 없기 때문**이다.
/// 한 장에 다 들어가야 하므로 무엇을 뺄지 먼저 정해야 한다 —
/// 뺀 것: 주간 점검 바, 시뮬레이션, 진단 카드. 남긴 것: 총액 · 구성원 · 최근 기록.
struct OnePagerView: View {
    let title: String
    let rollup: Rollup
    let members: [Member]
    let snapshots: [Snapshot]

    /// A4 비율(1:√2)에 맞춘 가로 폭. 세로는 내용에 맡긴다.
    private let width: CGFloat = 794

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("느 린 부 자 의 기 록")
                .font(.system(size: 10, weight: .medium))
                .tracking(3)
                .foregroundStyle(Paper.muted)
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Paper.ink)
                .padding(.top, 4)

            Rectangle().fill(Paper.ink).frame(height: 2).padding(.top, 12)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Won.abbreviated(rollup.netWorth, suffix: "원"))
                    .font(.figure(40, weight: .bold))
                    .foregroundStyle(Paper.ink)
                Text("가족 총자산")
                    .font(.system(size: 12))
                    .foregroundStyle(Paper.muted)
            }
            .padding(.top, 18)

            Text("자산 \(Won.abbreviated(rollup.assets, suffix: "원")) · 부채 \(Won.abbreviated(rollup.liabilities, suffix: "원")) · 투자자산 \(Won.abbreviated(rollup.investable, suffix: "원"))")
                .font(.figure(12))
                .foregroundStyle(Paper.muted)
                .padding(.top, 6)

            sectionTitle("구성원")
            ForEach(members) { member in
                row(member.name.isEmpty ? "이름 없음" : member.name,
                    Won.abbreviated(rollup.byMember[member.id] ?? .zero(.krw), suffix: "원"))
            }

            if !recent.isEmpty {
                sectionTitle("최근 기록")
                ForEach(recent, id: \.id) { snapshot in
                    row(dateText(snapshot.weekAnchor),
                        Won.abbreviated(Money(minorUnits: snapshot.netWorthMinor, currency: .krw),
                                        suffix: "원"))
                }
            }

            Spacer(minLength: 24)

            Text("입력한 가정에 따른 계산이며 미래 수익을 보장하지 않습니다. 시세를 외부에서 가져오지 않고 직접 적어 넣은 숫자입니다.")
                .font(.system(size: 9))
                .foregroundStyle(Paper.faint)
                .padding(.top, 20)
        }
        .padding(44)
        .frame(width: width, alignment: .leading)
        .background(Paper.sheet)
    }

    /// 최근 여덟 주. 한 장에 들어가는 만큼만 남긴다.
    private var recent: [Snapshot] {
        snapshots.suffix(8).reversed()
    }

    private func sectionTitle(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(Paper.muted)
                .padding(.bottom, 6)
            Rectangle().fill(Paper.rule).frame(height: 1)
        }
        .padding(.top, 26)
    }

    private func row(_ label: String, _ amount: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Paper.bodyText)
            Spacer()
            Text(amount)
                .font(.figure(13, weight: .medium))
                .foregroundStyle(Paper.ink)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Paper.rule.opacity(0.6)).frame(height: 1)
        }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일"
        return formatter.string(from: date)
    }
}
