import Core
import Foundation
import SwiftUI

/// A4 한 장. `ImageRenderer` 가 이걸 PDF 로 그린다.
///
/// **원본 계획서의 A~H 블록을 한 장에 담는다** (docs/reference/one-pager-analysis.md,
/// docs/08-feedback.md 10번). 예전에는 총액·구성원 이름·최근 기록만 있어서
/// 원본에 한참 못 미쳤다.
///
/// **색은 `Paper` 고정 팔레트를 쓴다.** 화면이 다크여도 인쇄물은 흰 종이여야
/// 한다. 적응형 토큰(`Color.ink` 등)을 쓰면 다크 모드에서 검은 종이가 나온다.
///
/// 한 장에 다 넣기로 했으므로(사용자 결정) 글자가 작다. 대신 **무엇을 뺄지**를
/// 정해 두었다 — 뺀 것: 시뮬레이션, 주간 점검 진행 바, 변경 이력.
/// 변경 이력은 금액이 남으므로 남에게 건네는 문서에 들어가면 안 된다.
///
/// **구성원 카드는 2열이다** (docs/08-feedback.md 25·26번). 세로로 쌓으면
/// 한 장을 넘고, 무엇보다 카드 안에 성장 궤적을 넣을 자리가 없다.
/// 4인 가족이면 정확히 2×2 가 되고, 5명이면 3줄이 된다.
struct OnePagerView: View {
    let title: String
    let asOfNote: String
    let startedOn: Date?
    let retirementYear: Int
    let declaration: String
    let rollup: Rollup
    let members: [Member]
    let milestones: [Milestone]
    let cashEvents: [CashEvent]
    let principles: [Principle]
    let todos: [TodoItem]
    let usShare: Decimal?
    let krShare: Decimal?
    /// 구성원 카드의 성장 궤적. 계산은 밖에서 해서 넘긴다 — 이 뷰는 그리기만 한다.
    let memberSeries: [MemberSeries]
    let today: Date
    let nextReview: Date?

    /// 한 구성원의 미니 바차트 (docs/08-feedback.md 26번).
    ///
    /// 원본 PDF 가 구성원마다 일곱 시점의 예상 금액을 막대로 그렸다.
    /// 2차에서 카드의 다섯 조각 중 이것 하나만 빠뜨렸다.
    struct MemberSeries: Hashable, Identifiable {
        struct Bar: Hashable {
            let year: Int
            let minor: Int
            /// 그 해의 나이. 자녀 카드에만 적는다 — "2035년 = 13세" 가 보이면
            /// 그 시점이 무엇을 뜻하는지 바로 읽힌다.
            let age: Int?
        }
        let memberID: UUID
        let bars: [Bar]
        var id: UUID { memberID }
    }

    /// 1페이지에 싣는 운용 원칙 개수. 나머지는 다음 주에 실린다 (24번).
    private let principlesOnPage = 5

    /// 카드에 늘어놓을 종목 줄 수. 넘치면 `외 N건` 으로 접는다.
    private let holdingRowsPerCard = 6

    /// A4 가로 폭(595pt @72dpi). PDF 로 뽑으므로 포인트 단위가 그대로 종이다.
    private let width: CGFloat = 595

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            summaryRow
            roadmapRow
            memberBlock
            twoColumns
            Spacer(minLength: 8)
            footer
        }
        .padding(32)
        .frame(width: width, alignment: .leading)
        .background(Paper.sheet)
    }

    // MARK: - A. 헤더

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("느 린 부 자 의 기 록")
                .font(.system(size: 7, weight: .medium))
                .tracking(2.5)
                .foregroundStyle(Paper.muted)
            HStack(alignment: .lastTextBaseline) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Paper.ink)
                Spacer()
                Text(periodText)
                    .font(.figure(8))
                    .foregroundStyle(Paper.muted)
            }
            // 기준 시점 선언. **같은 자산을 두 번 세지 않기 위한 것**이라
            // 원본에서도 제목 바로 아래 있었다.
            if !asOfNote.isEmpty {
                Text(asOfNote)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Paper.bodyText)
                    .padding(.top, 1)
            }
            Rectangle().fill(Paper.ink).frame(height: 1.5).padding(.top, 6)
        }
    }

    private var periodText: String {
        let end = String(retirementYear)
        guard let startedOn else { return "~ \(end)" }
        return "\(Self.dayFormatter.string(from: startedOn)) ~ \(end)"
    }

    // MARK: - F. 가족 요약

    private var summaryRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("가족 총자산")
                    .font(.system(size: 7))
                    .foregroundStyle(Paper.muted)
                Text(Won.abbreviated(rollup.netWorth, suffix: "원"))
                    .font(.figure(24, weight: .bold))
                    .foregroundStyle(Paper.ink)
            }
            Spacer()
            figure("투자자산", Won.compact(rollup.investable))
            figure("비투자", Won.compact(rollup.assets - rollup.investable))
            figure("부채", Won.compact(rollup.liabilities))
            // **본인 부담을 따로 적는다** (27번). 회사 매칭까지 합친 숫자만 보면
            // 내 저축률을 부풀려 읽게 된다 — 진단은 이미 본인 부담만 센다.
            figure("월 적립", Won.compact(monthlyTotal), sub: "본인 \(Won.compact(ownContribution))")
            // **한국을 미국과 나란히 적는다** (27번). 미국만 적으면 나머지가
            // 전부 한국인 것처럼 읽히는데, 그 외 국가가 따로 있다.
            if let countryText {
                figure("한국 · 미국", countryText)
            }
        }
        .padding(.top, 12)
    }

    private func figure(_ label: String, _ value: String, sub: String? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 6.5))
                .foregroundStyle(Paper.muted)
            Text(value)
                .font(.figure(10, weight: .semibold))
                .foregroundStyle(Paper.ink)
            if let sub {
                Text(sub)
                    .font(.figure(6))
                    .foregroundStyle(Paper.muted)
            }
        }
    }

    private var monthlyTotal: Money {
        Money(minorUnits: members.reduce(0) {
            $0 + $1.monthlyContributionMinor + $1.employerMatchMinor
        }, currency: .krw)
    }

    /// 회사 매칭을 뺀 **본인 부담**만.
    private var ownContribution: Money {
        Money(minorUnits: members.reduce(0) { $0 + $1.monthlyContributionMinor }, currency: .krw)
    }

    /// `30 · 70%` — 한국과 미국을 한 칸에 나란히.
    private var countryText: String? {
        guard usShare != nil || krShare != nil else { return nil }
        let kr = krShare.map { "\(PercentFormatter.integer($0))" } ?? "–"
        let us = usShare.map { "\(PercentFormatter.integer($0))" } ?? "–"
        return "\(kr) · \(us)%"
    }

    // MARK: - B. 로드맵

    private var roadmapRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            blockTitle("전체 자산 로드맵")
            HStack(alignment: .top, spacing: 0) {
                ForEach(milestones, id: \.year) { milestone in
                    VStack(alignment: .leading, spacing: 1) {
                        // **연도 옆에 가장 나이**를 적는다 (27번). 연도만 있으면
                        // "그때 내가 몇 살인가" 를 머리로 계산해야 한다.
                        HStack(spacing: 3) {
                            Text(verbatim: "\(milestone.year)")
                                .font(.figure(7))
                                .foregroundStyle(Paper.faint)
                            if let age = headAge(inYear: milestone.year) {
                                Text(verbatim: "\(age)세")
                                    .font(.figure(6.5))
                                    .foregroundStyle(Paper.muted)
                            }
                        }
                        Text(Won.compact(milestone.balance))
                            .font(.figure(10, weight: .semibold))
                            .foregroundStyle(Paper.ink)
                        Text(milestone.kind.label)
                            .font(.system(size: 6.5))
                            .foregroundStyle(Paper.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 12)
    }

    /// 가장(첫 구성원)의 그 해 나이. 생일 달까지는 보지 않는다 — 로드맵은
    /// 해 단위라 `2035년 51세` 면 충분하다.
    private func headAge(inYear year: Int) -> Int? {
        guard let head = members.first else { return nil }
        let age = year - head.birthYear
        return age >= 0 ? age : nil
    }

    // MARK: - C. 구성원 카드 (2열)

    private var memberBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            blockTitle("구성원")
            // `LazyVGrid` 는 화면에 보이는 것만 그린다. PDF 는 한 번에 다
            // 그려져야 하므로 줄을 직접 짠다.
            ForEach(memberRows.indices, id: \.self) { index in
                let row = memberRows[index]
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row, id: \.id) { member in
                        memberCard(member)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // 홀수 명이면 마지막 줄의 빈 칸을 남겨 폭을 맞춘다.
                    if row.count == 1 {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    private var memberRows: [[Member]] {
        stride(from: 0, to: members.count, by: 2).map { start in
            Array(members[start..<min(start + 2, members.count)])
        }
    }

    private func memberCard(_ member: Member) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(member.name.isEmpty ? "이름 없음" : member.name)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Paper.ink)
                Text("\(member.age)세")
                    .font(.system(size: 7))
                    .foregroundStyle(Paper.faint)
                if member.taxResidency != .korea {
                    Text(member.taxResidency.label)
                        .font(.system(size: 6))
                        .foregroundStyle(Paper.muted)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 0.5)
                        .background(Paper.rule)
                }
                Spacer(minLength: 2)
                Text(Won.compact(rollup.byMember[member.id] ?? .zero(.krw)))
                    .font(.figure(9, weight: .semibold))
                    .foregroundStyle(Paper.ink)
            }

            Text(contributionText(member))
                .font(.figure(6.5))
                .foregroundStyle(Paper.muted)

            // 보유 종목 — 상태 태그가 중요하다. `동결`·`신규` 가 원본의 핵심이었다.
            // 칸이 좁아졌으므로 넘치는 것은 접는다. 한 장을 넘기지 않는 것이
            // 이 문서의 첫 번째 규칙이다.
            ForEach(visibleHoldings(of: member), id: \.id) { holding in
                HStack(spacing: 3) {
                    Text(holdingLabel(holding))
                        .font(.system(size: 6.5))
                        .foregroundStyle(Paper.bodyText)
                        .lineLimit(1)
                    if holding.status != .accumulating {
                        Text(holding.status.label)
                            .font(.system(size: 5.5))
                            .foregroundStyle(Paper.muted)
                            .padding(.horizontal, 2)
                            .background(Paper.rule)
                    }
                    Spacer(minLength: 2)
                    Text(Won.compact(holding.value))
                        .font(.figure(6.5))
                        .foregroundStyle(Paper.bodyText)
                }
            }
            if hiddenHoldingCount(of: member) > 0 {
                Text("외 \(hiddenHoldingCount(of: member))건")
                    .font(.system(size: 6))
                    .foregroundStyle(Paper.faint)
            }

            if let series = memberSeries.first(where: { $0.memberID == member.id }),
               series.bars.count > 1 {
                miniChart(series)
                    .padding(.top, 2)
            }

            if !member.note.isEmpty {
                Text("※ \(member.note)")
                    .font(.system(size: 6))
                    .foregroundStyle(Paper.muted)
                    .lineLimit(2)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Paper.sheet)
        .overlay {
            Rectangle().stroke(Paper.rule, lineWidth: 0.5)
        }
    }

    private func holdingLabel(_ holding: Holding) -> String {
        let account = holding.account
        let accountName = account.map { $0.name.isEmpty ? $0.kind.label : $0.name } ?? ""
        let name = holding.name.isEmpty ? "이름 없음" : holding.name
        return accountName.isEmpty ? name : "\(accountName) · \(name)"
    }

    private func allHoldings(of member: Member) -> [Holding] {
        member.sortedAccounts.flatMap(\.sortedHoldings)
    }

    private func visibleHoldings(of member: Member) -> [Holding] {
        Array(allHoldings(of: member).prefix(holdingRowsPerCard))
    }

    private func hiddenHoldingCount(of member: Member) -> Int {
        max(0, allHoldings(of: member).count - holdingRowsPerCard)
    }

    /// 성장 궤적 미니 바차트 (26번).
    ///
    /// **로드맵과 같은 해를 쓴다.** 그래야 1페이지 안에서 위의 로드맵 줄과
    /// 구성원 카드가 같은 시간축을 갖는다.
    private func miniChart(_ series: MemberSeries) -> some View {
        let maxValue = max(series.bars.map(\.minor).max() ?? 1, 1)
        return HStack(alignment: .bottom, spacing: 3) {
            ForEach(series.bars, id: \.year) { bar in
                VStack(spacing: 1) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(Paper.ink.opacity(0.75))
                        .frame(height: max(1, 26 * CGFloat(bar.minor) / CGFloat(maxValue)))
                    Text(verbatim: "\(bar.year % 100)")
                        .font(.figure(5.5))
                        .foregroundStyle(Paper.faint)
                    if let age = bar.age {
                        Text(verbatim: "\(age)세")
                            .font(.figure(5))
                            .foregroundStyle(Paper.faint)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 40)
    }

    /// 본인 부담과 회사 매칭을 나눠 적는다 — 원본이 그렇게 적었다.
    private func contributionText(_ member: Member) -> String {
        let own = Money(minorUnits: member.monthlyContributionMinor, currency: .krw)
        guard member.employerMatchMinor > 0 else { return "월 \(Won.compact(own))" }
        let match = Money(minorUnits: member.employerMatchMinor, currency: .krw)
        let total = Money(minorUnits: member.monthlyContributionMinor + member.employerMatchMinor,
                          currency: .krw)
        return "월 \(Won.compact(total)) (본인 \(Won.compact(own)) · 회사 \(Won.compact(match)))"
    }

    // MARK: - D · E · G — 두 칸으로 나눠 담는다

    private var twoColumns: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                if !principles.isEmpty {
                    // **몇 개 중 몇 개인지 적는다** (24번). 원칙은 계속 늘어나는데
                    // 종이는 한 장이라 다 실을 수 없다. 감추는 것이 아니라
                    // 주마다 돌아가며 싣는다는 것을 사람이 알 수 있어야 한다.
                    blockTitle(principleTitle)
                    ForEach(rotatedPrinciples) { principle in
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(principle.order). \(principle.title)")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(Paper.ink)
                            if !principle.detail.isEmpty {
                                Text(principle.detail)
                                    .font(.system(size: 6.5))
                                    .foregroundStyle(Paper.muted)
                            }
                        }
                        .padding(.bottom, 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                if !cashEvents.isEmpty {
                    blockTitle("목돈 흐름")
                    ForEach(cashEvents.sorted { $0.date < $1.date }) { event in
                        HStack {
                            Text("\(yearText(event.date)) \(event.label.isEmpty ? "목돈" : event.label)")
                                .font(.system(size: 7))
                                .foregroundStyle(Paper.bodyText)
                            Spacer()
                            Text(Won.compact(event.amount))
                                .font(.figure(7))
                                .foregroundStyle(Paper.ink)
                        }
                    }
                }
                if !todos.isEmpty {
                    blockTitle("유의 사항")
                        .padding(.top, 4)
                    ForEach(todos.filter { !$0.isDone }.sorted { $0.sortIndex < $1.sortIndex }) { todo in
                        HStack(alignment: .top, spacing: 3) {
                            Text(todo.title)
                                .font(.system(size: 7))
                                .foregroundStyle(Paper.bodyText)
                            Spacer()
                            if let due = todo.dueDate {
                                Text(dateText(due))
                                    .font(.figure(6.5))
                                    .foregroundStyle(Paper.muted)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 10)
    }

    private var principleTitle: String {
        guard principles.count > principlesOnPage else { return "운용 원칙" }
        return "운용 원칙   \(principles.count)개 중 \(principlesOnPage)개 (이번 주)"
    }

    /// 이번 주에 실을 다섯. 같은 주에는 늘 같은 다섯이다 (24번).
    private var rotatedPrinciples: [Principle] {
        let sorted = principles.sorted { $0.order < $1.order }
        let picked = PrincipleRotation.indices(count: sorted.count,
                                               take: principlesOnPage,
                                               on: today)
        return picked.compactMap { sorted.indices.contains($0) ? sorted[$0] : nil }
    }

    // MARK: - H. 푸터

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(Paper.rule).frame(height: 0.5)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(declaration)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Paper.ink)
                Spacer(minLength: 4)
                // **임박한 만기** — 원본 푸터의 세 칸 중 빠져 있던 것 (27·28번).
                if let maturityText {
                    Text(maturityText)
                        .font(.figure(7))
                        .foregroundStyle(Paper.ink)
                }
                if let nextReview {
                    Text("다음 점검 \(dateText(nextReview))")
                        .font(.figure(7))
                        .foregroundStyle(Paper.muted)
                }
            }
            Text("입력한 가정에 따른 계산이며 미래 수익을 보장하지 않습니다. 시세를 외부에서 가져오지 않고 직접 적어 넣은 숫자입니다.")
                .font(.system(size: 6))
                .foregroundStyle(Paper.faint)
        }
        .padding(.top, 8)
    }

    /// 앞으로 1년 안에 오는 만기 둘까지. 지난 것은 적지 않는다 —
    /// 종이는 "앞으로 무엇을 해야 하는가" 를 적는 자리다.
    private var maturityText: String? {
        let upcoming = members
            .flatMap(\.sortedAccounts)
            .filter { !$0.isArchived }
            .compactMap { account -> (String, Date)? in
                guard let date = account.maturesOn, date >= today,
                      let limit = Calendar.current.date(byAdding: .year, value: 1, to: today),
                      date <= limit
                else { return nil }
                return (account.weightLabel, date)
            }
            .sorted { $0.1 < $1.1 }
            .prefix(2)
        guard !upcoming.isEmpty else { return nil }
        return "임박한 만기 " + upcoming
            .map { "\($0.0) \(Self.dayFormatter.string(from: $0.1))" }
            .joined(separator: " · ")
    }

    // MARK: - 부품

    private func blockTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Paper.muted)
    }

    /// 날짜 포맷터는 한 번만 만든다. 카드마다 만들면 렌더가 눈에 띄게 느려진다.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    private func dateText(_ date: Date) -> String {
        Self.dayFormatter.string(from: date)
    }

    private func yearText(_ date: Date) -> String {
        String(Calendar.current.component(.year, from: date))
    }
}
