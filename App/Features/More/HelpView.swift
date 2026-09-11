import Core
import SwiftUI

/// **도움말 · 용어집** (docs/05-roadmap.md G1).
///
/// 남에게 건네면 설명할 사람이 없다. 화면마다 "왜 이 기준인가" 는 진단 카드
/// 안에 이미 접혀 있으니, 여기는 **앱을 처음 여는 사람이 30초 안에 읽을
/// 것**과 **자주 헷갈리는 말**만 둔다. 실제 금액은 어디에도 없다.
struct HelpView: View {

    struct Entry: Identifiable {
        let term: String
        let meaning: String
        var id: String { term }
    }

    private static let howItWorks: [Entry] = [
        Entry(term: "매주 토요일, 직접 적는다",
              meaning: "시세를 가져오지 않습니다. 증권사·은행 앱에서 본 숫자를 내 손으로 옮겨 적는 것이 이 앱의 전부이고, 그래서 숫자를 믿을 수 있습니다. 해외 종목도 원화로 환산해 적습니다."),
        Entry(term: "계획선 위인가 아래인가",
              meaning: "계획 탭의 가정(월 적립 · 기대수익률 · 은퇴 연도)으로 그린 선이 계획선, 매주 적은 총액을 이은 선이 실적선입니다. 현황판의 궤적은 둘을 겹쳐 보입니다."),
        Entry(term: "가족이 함께 본다",
              meaning: "관리자가 초대하면 가족 각자의 아이폰에서 같은 기록을 봅니다. 참가자는 관리자가 허락한 구성원의 종목만 고칠 수 있습니다. 더보기 → 가족 에서 관리합니다."),
        Entry(term: "모르면 0",
              meaning: "은퇴 후 소득·생활비처럼 아직 모르는 값은 0 으로 두세요. 그 값이 필요한 진단은 \"입력 필요\" 로 표시되고, 나머지는 정상으로 계산됩니다."),
    ]

    private static let glossary: [Entry] = [
        Entry(term: "목 · 실 · 감", meaning: "매일 한 줄씩 적는 목표 · 실적 · 감사. 주간 점검과는 별개로, 돈이 아니라 하루를 기록합니다."),
        Entry(term: "주간 점검", meaning: "토요일에 종목 값을 훑어 적는 일. 끝내면 그 주의 총액이 궤적의 점 하나로 남습니다."),
        Entry(term: "매주 · 월 1회 · 고정", meaning: "종목마다 얼마나 자주 물어볼지. 예적금은 월 1회, 전월세보증금처럼 안 변하는 돈은 고정으로 두면 점검이 짧아집니다."),
        Entry(term: "기준값과 변동", meaning: "이번 주 처음 값을 고치는 순간, 그 전 값이 기준값이 됩니다. 변동은 지금 값 − 기준값입니다. 같은 주에 여러 번 고쳐도 기준값은 그대로입니다."),
        Entry(term: "오늘 돈 기준", meaning: "물가를 뺀 값. \"65세부터 월 150만원\" 은 지금 물가로 말한 것이라, 앱이 물가상승률만큼 알아서 키웁니다. 은퇴 후 소득·생활비는 전부 이 기준으로 적습니다."),
        Entry(term: "4% 규칙", meaning: "연 생활비의 25배가 있으면 해마다 4% 씩 꺼내 써도 원금이 오래 버틴다는 경험칙. 은퇴 필요 자금의 결승선입니다."),
        Entry(term: "기대수익률", meaning: "주식 · ETF 가 한 해 평균 얼마나 자랄지에 대한 가정. 채권 · 금 · 예적금 · 부동산은 각자의 값으로 따로 굴립니다. 보장이 아니라 가정입니다."),
        Entry(term: "지킴 · 주의 · 조치 · 입력 필요", meaning: "자산 진단의 네 상태. 조치는 위반이 아니라 \"할 일이 있다\" 입니다. 규칙은 막지 않고 알립니다."),
        Entry(term: "세제혜택 계좌", meaning: "IRP · 연금저축 · ISA. 같은 돈을 넣어도 세액공제만큼 먼저 붙으니 이 순서로 채우라고 진단이 알려 줍니다. 한도는 해가 바뀌면 사라집니다."),
        Entry(term: "관리자 · 참가자", meaning: "관리자는 처음 만든 사람 — 계획과 가족을 관리합니다. 참가자는 초대받은 가족으로, 허락된 구성원의 종목만 고칩니다."),
        Entry(term: "월간 회고", meaning: "매달 1일, 지난달에 얼마가 들어가고 얼마가 자랐는지 한 장으로 돌아봅니다. 더보기 → 월간 · 연간 회고."),
        Entry(term: "1페이지", meaning: "계획 전체를 종이 한 장에 담은 문서. 냉장고에 붙이거나 가족에게 보내는 용도입니다. 더보기 → 1페이지 문서."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(Self.howItWorks) { row($0) }
            } header: {
                Text("이 앱은 이렇게 씁니다")
            }

            Section {
                ForEach(Self.glossary) { row($0) }
            } header: {
                Text("용어")
            } footer: {
                Text("진단 규칙마다 \"왜 이 기준인가\" 는 자산 진단 화면의 각 카드 안에 있습니다.")
            }
        }
        .navigationTitle("도움말 · 용어집")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.term)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text(entry.meaning)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
