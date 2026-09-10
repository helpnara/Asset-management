import SwiftUI

/// **현황판 카드의 순서와 표시 여부** (docs/08-feedback.md 83번, C6).
///
/// 목·실·감 카드가 맨 위에 못 박혀 있었다. 가족 총자산을 먼저 보고 싶은 사람도
/// 있다 — 순서는 사람마다 다르니 기기에 둔다 (`UserDefaults`, 동기화 안 함).
/// 총자산 카드는 끌 수 없다. 그것이 없는 현황판은 현황판이 아니다.
enum DashboardCard: String, CaseIterable, Identifiable {
    case diary
    case hero
    case weekly
    case attribution
    case monthly
    case roadmap
    case lifeEvents
    case trajectory
    case diagnostics
    case members
    case totals

    var id: String { rawValue }

    var label: String {
        switch self {
        case .diary: return "오늘의 목 · 실 · 감"
        case .hero: return "가족 총자산"
        case .weekly: return "이번 주 점검"
        case .attribution: return "얼마 넣어서 얼마 자랐나"
        case .monthly: return "지난달 회고"
        case .roadmap: return "전체 자산 로드맵"
        case .lifeEvents: return "인생 이벤트"
        case .trajectory: return "순자산 궤적"
        case .diagnostics: return "자산 진단"
        case .members: return "구성원"
        case .totals: return "가족 합계"
        }
    }

    /// 끌 수 없는 카드.
    var isRequired: Bool { self == .hero }

    static let orderKey = "dashboard.cardOrder"
    static let hiddenKey = "dashboard.hiddenCards"

    /// 저장된 순서를 읽는다. 모르는 이름은 버리고, 빠진 카드(나중에 생긴 것)는
    /// 기본 순서의 자리에 끼워 넣는다 — 새 카드가 설정 때문에 영영 안 보이면 안 된다.
    static func order(from raw: String) -> [DashboardCard] {
        let saved = raw.split(separator: ",").compactMap { DashboardCard(rawValue: String($0)) }
        guard !saved.isEmpty else { return allCases }
        var result = saved
        for (index, card) in allCases.enumerated() where !result.contains(card) {
            let anchor = allCases[..<index].last { result.contains($0) }
            if let anchor, let at = result.firstIndex(of: anchor) {
                result.insert(card, at: at + 1)
            } else {
                result.insert(card, at: 0)
            }
        }
        return result
    }

    static func hidden(from raw: String) -> Set<DashboardCard> {
        Set(raw.split(separator: ",").compactMap { DashboardCard(rawValue: String($0)) })
            .subtracting(allCases.filter(\.isRequired))
    }

    static func encode(_ cards: [DashboardCard]) -> String {
        cards.map(\.rawValue).joined(separator: ",")
    }

    static func encode(_ cards: Set<DashboardCard>) -> String {
        encode(allCases.filter { cards.contains($0) })
    }
}

/// 더보기 → 현황판 카드 순서.
struct DashboardCardsView: View {
    @AppStorage(DashboardCard.orderKey) private var orderRaw = ""
    @AppStorage(DashboardCard.hiddenKey) private var hiddenRaw = ""

    private var order: [DashboardCard] { DashboardCard.order(from: orderRaw) }
    private var hidden: Set<DashboardCard> { DashboardCard.hidden(from: hiddenRaw) }

    var body: some View {
        List {
            Section {
                ForEach(order) { card in
                    Toggle(isOn: Binding(
                        get: { !hidden.contains(card) },
                        set: { on in
                            var next = hidden
                            if on { next.remove(card) } else if !card.isRequired { next.insert(card) }
                            hiddenRaw = DashboardCard.encode(next)
                        }
                    )) {
                        Text(card.label)
                            .foregroundStyle(hidden.contains(card) ? Color.muted : Color.ink)
                    }
                    .disabled(card.isRequired)
                }
                .onMove { source, destination in
                    var next = order
                    next.move(fromOffsets: source, toOffset: destination)
                    orderRaw = DashboardCard.encode(next)
                }
            } footer: {
                Text("끌어서 순서를 바꾸고, 스위치로 카드를 숨깁니다. 가족 총자산은 숨길 수 없습니다. 이 기기에만 적용됩니다.")
            }

            Section {
                Button("기본 순서로 되돌리기") {
                    orderRaw = ""
                    hiddenRaw = ""
                }
                .disabled(orderRaw.isEmpty && hiddenRaw.isEmpty)
            }
        }
        // 손잡이가 늘 보이게 — 편집 버튼을 찾아 누르게 하지 않는다.
        .environment(\.editMode, .constant(.active))
        .navigationTitle("현황판 카드 순서")
        .navigationBarTitleDisplayMode(.inline)
    }
}
