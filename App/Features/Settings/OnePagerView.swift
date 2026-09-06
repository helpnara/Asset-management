import Core
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
struct OnePagerView: View {
    let title: String
    let asOfNote: String
    let startedOn: Date?
    let retirementYear: Int
    let declaration: String
    let rollup: Rollup
    let members: [Member]
    let snapshots: [Snapshot]
    let milestones: [Milestone]
    let cashEvents: [CashEvent]
    let principles: [Principle]
    let todos: [TodoItem]
    let usShare: Decimal?
    let nextReview: Date?

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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        return "\(formatter.string(from: startedOn)) ~ \(end)"
    }

    // MARK: - F. 가족 요약

    private var summaryRow: some View {
        HStack(alignment: .lastTextBaseline, spacing: 14) {
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
            figure("월 적립", Won.compact(monthlyTotal))
            if let usShare {
                figure("미국", "\(PercentFormatter.oneDecimal(usShare))%")
            }
        }
        .padding(.top, 12)
    }

    private func figure(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 6.5))
                .foregroundStyle(Paper.muted)
            Text(value)
                .font(.figure(10, weight: .semibold))
                .foregroundStyle(Paper.ink)
        }
    }

    private var monthlyTotal: Money {
        Money(minorUnits: members.reduce(0) {
            $0 + $1.monthlyContributionMinor + $1.employerMatchMinor
        }, currency: .krw)
    }

    // MARK: - B. 로드맵

    private var roadmapRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            blockTitle("전체 자산 로드맵")
            HStack(alignment: .top, spacing: 0) {
                ForEach(milestones, id: \.year) { milestone in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "\(milestone.year)")
                            .font(.figure(7))
                            .foregroundStyle(Paper.faint)
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

    // MARK: - C. 구성원 카드

    private var memberBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            blockTitle("구성원")
            ForEach(members) { member in
                memberCard(member)
            }
        }
        .padding(.top, 12)
    }

    private func memberCard(_ member: Member) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
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
                Spacer()
                Text(contributionText(member))
                    .font(.figure(7))
                    .foregroundStyle(Paper.muted)
                Text(Won.compact(rollup.byMember[member.id] ?? .zero(.krw)))
                    .font(.figure(9, weight: .semibold))
                    .foregroundStyle(Paper.ink)
            }

            // 보유 종목 — 상태 태그가 중요하다. `동결`·`신규` 가 원본의 핵심이었다.
            ForEach(member.sortedAccounts) { account in
                ForEach(account.sortedHoldings) { holding in
                    HStack(spacing: 4) {
                        Text("\(account.name.isEmpty ? account.kind.label : account.name) · \(holding.name.isEmpty ? "이름 없음" : holding.name)")
                            .font(.system(size: 7))
                            .foregroundStyle(Paper.bodyText)
                        if holding.status != .accumulating {
                            Text(holding.status.label)
                                .font(.system(size: 5.5))
                                .foregroundStyle(Paper.muted)
                                .padding(.horizontal, 2)
                                .background(Paper.rule)
                        }
                        Spacer()
                        Text(Won.compact(holding.value))
                            .font(.figure(7))
                            .foregroundStyle(Paper.bodyText)
                    }
                }
            }

            if !member.note.isEmpty {
                Text("※ \(member.note)")
                    .font(.system(size: 6.5))
                    .foregroundStyle(Paper.muted)
            }
        }
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Paper.rule).frame(height: 0.5)
        }
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
                    blockTitle("운용 원칙")
                    ForEach(principles.sorted { $0.order < $1.order }) { principle in
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

    // MARK: - H. 푸터

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            Rectangle().fill(Paper.rule).frame(height: 0.5)
            HStack {
                Text(declaration)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Paper.ink)
                Spacer()
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

    // MARK: - 부품

    private func blockTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .semibold))
            .tracking(1)
            .foregroundStyle(Paper.muted)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }

    private func yearText(_ date: Date) -> String {
        String(Calendar.current.component(.year, from: date))
    }
}
