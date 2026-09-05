import Core
import SwiftUI

/// M0 스캐폴딩 확인용 화면.
/// Core 패키지가 앱 타깃에 연결되었는지, 금액 포맷이 의도대로 나오는지 눈으로 확인한다.
/// M1에서 실제 현황판(docs/02-screens.md 2.2)으로 대체된다.
struct RootView: View {
    private let total = Money(302_731_078, currency: .krw)
    private let weeklyChange = Money(9_310_000, currency: .krw)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Color.ink).frame(height: 2)
            hero
            Rectangle().fill(Color.rule).frame(height: 1)
            weeklyBar
            Spacer()
        }
        .padding(.top, 8)
        .background(Color.white)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("2 0 2 6 . 0 8  ·  이 사 후 자 산").eyebrowStyle()
            Text("우리 가족 노후자금 준비")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("가 족 총 자 산").eyebrowStyle().padding(.bottom, 7)
            Text(KoreanAmountFormatter.abbreviated(total, suffix: "원"))
                .font(.figure(38, weight: .semibold))
                .foregroundStyle(Color.ink)
            HStack(spacing: 6) {
                Text("▲")
                Text(KoreanAmountFormatter.abbreviated(weeklyChange, suffix: "원", sign: .always))
                    .font(.figure(11.5, weight: .medium))
                Text("이번 주")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.muted)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Color.gain)
            .padding(.top, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var weeklyBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("이번 주 점검 · 토요일까지 D-2")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.ink)
                Text("12주 연속 기록 중 · 지난 점검 03.06")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.muted)
            }
            Spacer(minLength: 0)
            Text("지금 입력")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .overlay(Rectangle().stroke(Color.ink, lineWidth: 1))
        }
        .padding(13)
        .background(Color.surface)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }
}

#Preview {
    RootView()
}
