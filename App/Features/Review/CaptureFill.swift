import Core
import CoreData
import SwiftUI

// MARK: - 캡처로 채우기 (222번, docs/25 7~8 단계)
//
// 11-20 사용자: *"계좌별로 캡처 화면을 여러 개를 쭉 찍고 나서 그거를 한 번에 올리면 … 지금 앱에 등록되어 있는 계좌 …
// 화면에다가 등록하는 거야 그리고 없다라고 하면 그 부분을 입력하라고 표시"*. 11-21: *"착수하자. 모델에 칸 더해서 가족 모두 공유되게."*
//
// 흐름: 점검 화면 `캡처로 채우기` → 여러 장 고르기 → 기기 안에서 읽기(`CaptureReader`) → 계좌별로 묶기(`CaptureBatch`) →
// **이 시트에서 계좌 · 짝을 확인** → `점검에 채우기` → 점검 목록에 값이 들어가고(`write`, `나중에` 로 되돌릴 수 있다)
// 사람이 훑어보고 지금처럼 `완료`. 처음 한 번 고른 계좌 · 짝은 모델(`Account.captureKey` · `Holding.captureName`)에 적어
// 가족 모두 다음 캡처부터 저절로 맞춘다.
//
// **틀린 값이 조용히 들어가지 않게** — 검산(합 = 계좌 총액)이 안 맞는 계좌는 기본으로 채우지 않는다(`그래도 채우기`).
// 총액이 없는 화면은 채우되 줄마다 `캡처 · 확인` 띠지를 붙이고 다녀간 줄로 세지 않는다 — 커서가 그 줄로 간다.

/// 점검 목록의 줄이 캡처에서 어떻게 채워졌나 — 줄 띠지.
enum CaptureMark {
    /// 검산이 맞은 계좌에서 채움 — 다녀간 줄로 센다.
    case checked
    /// 총액이 없거나 `그래도 채우기` 로 채움 — 사람이 한 번 봐야 한다.
    case unchecked
    /// 이 계좌를 캡처로 채웠는데 캡처에 없던 종목 — 직접 적는다.
    case missing
}

/// 읽은 캡처 전체 — 시트가 고치고 `점검에 채우기` 가 받는다.
struct CaptureFillDraft: Identifiable {
    let id = UUID()
    var groups: [CaptureFillGroup]
    /// 열지 · 읽지 못한 그림 수.
    var failed: Int
}

/// 한 계좌로 묶인 캡처.
struct CaptureFillGroup: Identifiable {
    let id = UUID()
    /// 몇째 그림들인가(0 부터).
    let pages: [Int]
    let result: CaptureParser.Result
    /// 고른 계좌 — 앱이 고르고(`CaptureBatch.suggestAccount`) 사람이 바꿀 수 있다. nil = 아직 모름.
    var accountID: UUID?
    /// 검산이 안 맞아도 채운다 — 사람이 켜야 한다.
    var fillUnchecked = false
    /// 사람이 고른 짝(읽은 종목 순번 → 앱 종목, `.some(nil)` = 짝 없음으로 둠).
    var manual: [Int: UUID?] = [:]

    var canFill: Bool { result.isBalanced != false || fillUnchecked }

    /// 읽은 종목마다 짝 — 저절로 맞춘 것 위에 사람이 고른 것. 사람이 고른 종목은 다른 줄의 저절로 짝에서 뺀다.
    @MainActor
    func pairs(in account: Account?) -> [UUID?] {
        guard let account else { return Array(repeating: nil, count: result.items.count) }
        var pairs = CaptureBatch.pair(result.items, with: account.captureInfo.holdings)
        for (index, choice) in manual {
            if let choice {
                for other in pairs.indices where other != index && pairs[other] == choice && manual[other] == nil {
                    pairs[other] = nil
                }
            }
            pairs[index] = choice
        }
        return pairs
    }
}

extension Account {
    /// 짝짓기에 건네는 값 — 관리 객체를 Core 로 넘기지 않는다(CLAUDE.md).
    var captureInfo: CaptureBatch.AccountInfo {
        CaptureBatch.AccountInfo(id: id, captureKey: captureKey,
                                 holdings: sortedHoldings.map { .init(id: $0.id, name: $0.name, captureName: $0.captureName) },
                                 owner: owner?.name ?? "", name: name, institution: institution, kind: kind.label)
    }

    /// 시트의 계좌 고르기에 보이는 이름 — `아들 · 일반적립 · 가나증권`. **기관까지** 붙인다
    /// (11-21 사용자: *"아들 일반적립만 나오면 계좌 구분이 어려워"* — 같은 이름의 계좌가 증권사마다 있다).
    var captureLabel: String {
        var parts: [String] = []
        if let owner, !owner.name.isEmpty { parts.append(owner.name) }
        parts.append(name.isEmpty ? kind.label : name)
        if !institution.isEmpty { parts.append(institution) }
        return parts.joined(separator: " · ")
    }

    /// 계좌 고르기의 둘째 줄 — 이 캡처와 짝이 맞는 종목 수 · 기억한 계좌인지 · 그 계좌의 종목 이름 몇 개.
    /// 이름이 같은 계좌도 안에 든 종목으로 가린다.
    func captureHint(for result: CaptureParser.Result) -> String {
        let holdings = sortedHoldings
        let score = captureScore(for: result)
        var parts: [String] = []
        if !captureKey.isEmpty, captureKey == CaptureBatch.accountKey(result.accountLine) { parts.append("기억한 계좌") }
        if score.text >= 3 { parts.append("계좌 이름 맞음") }
        parts.append("이 캡처와 짝 \(score.pairs)개")
        let names = holdings.prefix(2).map { $0.name.isEmpty ? "이름 없음" : $0.name }.joined(separator: ", ")
        if holdings.isEmpty {
            parts.append("종목 없음")
        } else {
            parts.append(names + (holdings.count > 2 ? " 외 \(holdings.count - 2)" : ""))
        }
        return parts.joined(separator: " · ")
    }

    /// 이 캡처와 얼마나 맞나 — (짝 수, 계좌 줄 글자 점수). 계좌 고르기 목록을 맞는 순으로 늘어놓는 데 쓴다.
    func captureScore(for result: CaptureParser.Result) -> (pairs: Int, text: Int) {
        CaptureBatch.score(for: result, captureInfo)
    }
}

/// **읽은 결과를 확인하는 시트** — 계좌 · 짝을 고치고 `점검에 채우기`.
struct CaptureFillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @State var draft: CaptureFillDraft
    /// 고를 수 있는 계좌 — 이 기기에서 적을 수 있는 구성원의 것.
    let accounts: [Account]
    /// 이번 점검에 들어 있는 종목 — 여기 없는 종목은 채우지 않는다(고정 · 이달 이미 적은 월 1회).
    let queued: Set<UUID>
    let onApply: @MainActor (CaptureFillDraft) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("읽은 값을 점검 목록에 미리 채웁니다. 채운 뒤 훑어보고 `완료` 를 누르면 기록되고, `나중에` 로 나가면 되돌아갑니다. 처음 고른 계좌 · 짝은 기억해 가족 모두 다음부터 저절로 맞춥니다.")
                        .font(.scaled(12))
                        .foregroundStyle(Color.muted)
                        .lineSpacing(3)
                        .padding(.horizontal, Card.margin + 4)
                    ForEach($draft.groups) { $group in
                        groupCard($group)
                    }
                    if draft.failed > 0 {
                        Text("그림 \(draft.failed)장은 열지 못했습니다.")
                            .font(.scaled(12))
                            .foregroundStyle(Color.loss)
                            .padding(.horizontal, Card.margin + 4)
                    }
                }
                .padding(.vertical, 16)
            }
            .background(Color.ground)
            .readableWidth()
            .safeAreaInset(edge: .bottom, spacing: 0) { applyBar }
            .navigationTitle("캡처로 채우기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("닫기") { dismiss() }
                        .foregroundStyle(Color.muted)
                }
            }
        }
    }

    // MARK: - 조각

    private func account(_ id: UUID?) -> Account? { id.flatMap { id in accounts.first { $0.id == id } } }

    /// 채울 줄 수 — 계좌를 골랐고, 채울 수 있고, 짝이 있고, 이번 점검에 있고, 금액을 읽은 것.
    private var fillCount: Int {
        draft.groups.reduce(0) { count, group in
            guard group.canFill, let account = account(group.accountID) else { return count }
            let pairs = group.pairs(in: account)
            return count + group.result.items.indices.filter { index in
                guard let id = pairs[index] else { return false }
                return queued.contains(id) && group.result.items[index].valueMinor != nil
            }.count
        }
    }

    private var applyBar: some View {
        Button {
            onApply(draft)
            dismiss()
        } label: {
            Text(fillCount == 0 ? "채울 값이 없습니다" : "점검에 채우기 · \(fillCount)건")
        }
        .buttonStyle(PrimaryCapsule(fullWidth: true))
        .disabled(fillCount == 0)
        .padding(.horizontal, Card.margin)
        .padding(.vertical, 12)
        .background(Color.ground)
    }

    private func pagesLabel(_ pages: [Int]) -> String {
        let numbers = pages.map { $0 + 1 }
        if numbers.count > 1, numbers.last! - numbers.first! == numbers.count - 1 {
            return "\(numbers.first!)–\(numbers.last!)번째 캡처"
        }
        return numbers.map(String.init).joined(separator: " · ") + "번째 캡처"
    }

    @ViewBuilder
    private func badge(_ result: CaptureParser.Result) -> some View {
        switch result.isBalanced {
        case .some(true): StatusBadge(text: "검산 통과", foreground: .brand, background: .brandSoft)
        case .some(false): StatusBadge(text: "확인 필요", foreground: .caution, background: .goldSoft)
        case .none: StatusBadge(text: "총액 없음")
        }
    }

    private func totalsText(_ result: CaptureParser.Result) -> String {
        guard let total = result.totalMinor else { return "읽은 합 \(Won.grouped(result.sumMinor))" }
        var text = "계좌 총액 \(Won.grouped(total)) · 읽은 합 \(Won.grouped(result.sumMinor))"
        if let cash = result.cashMinor, result.expectedSumMinor != result.sumMinor {
            text += " · 현금 \(Won.grouped(cash))"
        }
        if total != result.expectedSumMinor {
            text += " · 차이 \(Won.grouped(abs(total - result.expectedSumMinor)))원"
        }
        return text
    }

    private func groupCard(_ group: Binding<CaptureFillGroup>) -> some View {
        let value = group.wrappedValue
        let chosen = account(value.accountID)
        let pairs = value.pairs(in: chosen)
        let missing = chosen.map { account in
            account.sortedHoldings.filter { queued.contains($0.id) && !pairs.contains($0.id) }
        } ?? []
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(pagesLabel(value.pages))
                    .font(.scaled(14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
                badge(value.result)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if let line = value.result.accountLine {
                        Text(line)
                            .font(.scaled(11.5))
                            .foregroundStyle(Color.faint)
                            .lineLimit(1)
                    }
                    accountMenu(group, result: value.result, chosen: chosen)
                    if chosen == nil {
                        Text("어느 계좌의 캡처인지 골라 주세요 — 한 번 고르면 기억합니다.")
                            .font(.scaled(11.5))
                            .foregroundStyle(Color.caution)
                    }
                    Text(totalsText(value.result))
                        .font(.figure(12))
                        .foregroundStyle(Color.muted)
                    switch value.result.isBalanced {
                    case .some(false):
                        Text("합이 계좌 총액과 달라 한 종목을 잘못 읽었을 수 있습니다. 그래서 이 계좌는 채우지 않습니다.")
                            .font(.scaled(11.5))
                            .foregroundStyle(Color.caution)
                        Toggle("그래도 채우기", isOn: group.fillUnchecked)
                            .font(.scaled(13))
                            .tint(Color.brand)
                    case .none:
                        Text("화면에 계좌 총액이 없어 검산하지 못했습니다. 채운 줄에 `캡처 · 확인` 이 붙습니다 — 한 번 보세요.")
                            .font(.scaled(11.5))
                            .foregroundStyle(Color.muted)
                    case .some(true):
                        EmptyView()
                    }
                }
                .padding(.horizontal, Card.inset)
                .padding(.vertical, 12)

                ForEach(Array(value.result.items.enumerated()), id: \.offset) { index, item in
                    Rectangle().fill(Color.rule).frame(height: 1).padding(.leading, Card.inset)
                    itemRow(item, index: index, pair: pairs[index], account: chosen, group: group)
                }

                if !missing.isEmpty, value.canFill {
                    Rectangle().fill(Color.rule).frame(height: 1).padding(.leading, Card.inset)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("캡처에 없는 종목 \(missing.count)개 — 점검에서 직접 적습니다")
                            .font(.scaled(12, weight: .medium))
                            .foregroundStyle(Color.ink)
                        Text(missing.map { $0.name.isEmpty ? "이름 없음" : $0.name }.joined(separator: " · "))
                            .font(.scaled(11.5))
                            .foregroundStyle(Color.muted)
                    }
                    .padding(.horizontal, Card.inset)
                    .padding(.vertical, 12)
                }
            }
            .cardSurface()
        }
    }

    /// **계좌 고르기** — 줄마다 `구성원 · 계좌 · 기관` 과 둘째 줄(계좌 이름 맞음 · 이 캡처와 짝 n개 · 종목 이름). 맞는 계좌가 위로.
    /// 메뉴 단추의 두 글자 줄은 iOS 가 제목 · 부제로 그린다.
    private func accountMenu(_ group: Binding<CaptureFillGroup>, result: CaptureParser.Result, chosen: Account?) -> some View {
        let ordered = accounts.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (lhs.element.captureScore(for: result), rhs.element.captureScore(for: result))
                return a != b ? (a.pairs, a.text) > (b.pairs, b.text) : lhs.offset < rhs.offset
            }
            .map(\.element)
        return Menu {
            ForEach(ordered) { account in
                Button {
                    group.wrappedValue.accountID = account.id
                } label: {
                    if account.id == chosen?.id {
                        Label {
                            Text(account.captureLabel)
                            Text(account.captureHint(for: result))
                        } icon: {
                            Image(systemName: "checkmark")
                        }
                    } else {
                        Text(account.captureLabel)
                        Text(account.captureHint(for: result))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(chosen?.captureLabel ?? "계좌 고르기")
                    .font(.scaled(13.5, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.scaled(11, weight: .semibold))
            }
            .foregroundStyle(chosen == nil ? Color.caution : Color.brand)
        }
    }

    private func itemRow(_ item: CaptureParser.Item, index: Int, pair: UUID?, account: Account?,
                         group: Binding<CaptureFillGroup>) -> some View {
        let holding = pair.flatMap { id in account?.sortedHoldings.first { $0.id == id } }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.scaled(13.5, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if let account {
                    Menu {
                        Button("짝 없음") { group.wrappedValue.manual[index] = .some(nil) }
                        ForEach(account.sortedHoldings) { candidate in
                            Button(candidate.name.isEmpty ? "이름 없음" : candidate.name) {
                                group.wrappedValue.manual[index] = .some(candidate.id)
                            }
                        }
                    } label: {
                        if let holding {
                            Text("→ \(holding.name)" + (queued.contains(holding.id) ? "" : " · 이번 점검에 없음"))
                                .font(.scaled(11.5))
                                .foregroundStyle(queued.contains(holding.id) ? Color.brand : Color.faint)
                                .lineLimit(1)
                        } else {
                            Text("앱 종목과 짝 없음 · 고르기")
                                .font(.scaled(11.5))
                                .foregroundStyle(Color.caution)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(item.valueMinor.map { Won.grouped($0) } ?? "금액 못 고름")
                    .font(.figure(13.5, weight: .semibold))
                    .foregroundStyle(item.valueMinor == nil ? Color.caution : Color.ink)
                    .lineLimit(1)
                    .fixedSize()
                if let holding {
                    Text("지금 \(Won.grouped(holding.valueMinor))")
                        .font(.figure(11))
                        .foregroundStyle(Color.faint)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, Card.inset)
        .padding(.vertical, 11)
    }
}
