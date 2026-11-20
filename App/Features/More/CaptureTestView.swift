import Core
import CoreData
import PhotosUI
import SwiftUI

/// **캡처 읽기 시험** (docs/25 J3, 11-20 사용자: *"착수하자. 시험 화면 만들어줘"*).
///
/// 증권사 앱의 보유 종목 화면 캡처를 골라, 기기 안의 글자 인식(Vision — 사진 앱의 텍스트 인식과 같은 엔진)으로
/// 읽고 **무엇을 어떻게 읽었는지만** 보여 준다. 실제 증권사 화면에서 "자동으로 채워질 칸이 얼마나 되나" 를 재려는 것.
///
/// - **아무것도 저장하지 않는다.** 종목 값 · 기록 · 설정 어디에도 쓰지 않는다.
/// - **그림은 읽고 나면 버린다.** 고른 것은 이 화면의 메모리에만 잠깐 있다.
/// - **밖으로 보내지 않는다.** 네트워크를 쓰지 않는다(ADR-0005). 사진은 시스템 선택 창으로 고른 것만 건네진다 —
///   사진 보관함 권한을 묻지 않는다.
///
/// 읽기 규칙은 `Core/CaptureParser` (리눅스에서도 시험된다), 가상 캡처 9장으로 다듬었다(`Tools/ocr-sim`).
struct CaptureTestView: View {
    @Fetched(sort: \Member.sortIndex) private var members: [Member]

    @State private var picks: [PhotosPickerItem] = []
    @State private var pages: [Page] = []
    @State private var isReading = false
    @State private var failures: [String] = []

    /// 앱에 등록된 종목 — 짝짓기에만 쓰는 값. 관리 객체를 넘기지 않는다(CLAUDE.md).
    struct Known: Sendable {
        let name: String
        let account: String
        let valueMinor: Int
    }

    struct Row: Identifiable {
        let id = UUID()
        let read: String
        let valueMinor: Int?
        let match: Known?
    }

    struct Page: Identifiable {
        let id = UUID()
        let number: Int
        let result: CaptureParser.Result
        let rows: [Row]
        let lines: [CaptureParser.Line]
        let milliseconds: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro
                PhotosPicker(selection: $picks, maxSelectionCount: 20, selectionBehavior: .ordered, matching: .images) {
                    Label(isReading ? "읽는 중…" : "캡처 고르기", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(PrimaryCapsule(fullWidth: true))
                .disabled(isReading)
                .padding(.horizontal, Card.margin)

                ForEach(failures, id: \.self) { message in
                    Text(message)
                        .font(.scaled(12))
                        .foregroundStyle(Color.loss)
                        .padding(.horizontal, Card.margin + 4)
                }
                if !pages.isEmpty {
                    summary
                    ForEach(pages) { page in pageCard(page) }
                }
            }
            .padding(.vertical, 16)
        }
        .background(Color.ground)
        .readableWidth()
        .reportsProgress("캡처 읽는 중", when: isReading)
        .navigationTitle("캡처 읽기 시험")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task { await read(items) }
        }
    }

    // MARK: - 조각

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("증권사 앱의 보유 종목 화면을 캡처해 골라 보세요. 계좌마다 여러 장이어도 됩니다.")
                .font(.scaled(13.5, weight: .medium))
                .foregroundStyle(Color.ink)
            Text("읽은 결과만 보여 주고 **아무것도 저장하지 않습니다.** 글자 인식은 이 기기 안에서만 하고, 그림은 읽은 뒤 바로 버립니다. 맞게 읽었는지 보고 결과를 알려 주시면 주간 점검에 붙일지 정합니다.")
                .font(.scaled(12))
                .foregroundStyle(Color.muted)
                .lineSpacing(3)
        }
        .padding(Card.inset)
        .cardSurface()
    }

    private var summary: some View {
        let items = pages.flatMap(\.rows)
        let withTotal = pages.filter { $0.result.totalMinor != nil }
        let balanced = withTotal.filter { $0.result.isBalanced == true }
        let matched = items.filter { $0.match != nil }
        return VStack(alignment: .leading, spacing: 6) {
            Text("캡처 \(pages.count)장 · 종목 \(items.count)개 읽음")
                .font(.scaled(14, weight: .semibold))
                .foregroundStyle(Color.ink)
            Text("검산 통과 \(balanced.count) / \(withTotal.count)장 (계좌 총액을 찾은 장) · 앱 종목과 짝 \(matched.count) / \(items.count)")
                .font(.figure(12))
                .foregroundStyle(Color.muted)
        }
        .padding(Card.inset)
        .cardSurface()
    }

    private func pageCard(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(page.number)번째 캡처")
                    .font(.scaled(14, weight: .bold))
                    .foregroundStyle(Color.ink)
                Spacer()
                switch page.result.isBalanced {
                case .some(true): StatusBadge(text: "검산 통과", foreground: .brand, background: .brandSoft)
                case .some(false): StatusBadge(text: "확인 필요", foreground: .caution, background: .goldSoft)
                case .none: StatusBadge(text: "총액 못 찾음")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    if let account = page.result.accountLine {
                        Text(account)
                            .font(.scaled(11.5))
                            .foregroundStyle(Color.faint)
                            .lineLimit(1)
                    }
                    Text("계좌 총액 \(page.result.totalMinor.map { Won.grouped($0) } ?? "—") · 읽은 합 \(Won.grouped(page.result.sumMinor))"
                         + differenceText(page.result))
                        .font(.figure(12))
                        .foregroundStyle(Color.muted)
                }
                .padding(.horizontal, Card.inset)
                .padding(.vertical, 12)

                ForEach(page.rows) { row in
                    Rectangle().fill(Color.rule).frame(height: 1).padding(.leading, Card.inset)
                    rowView(row)
                }

                Rectangle().fill(Color.rule).frame(height: 1).padding(.leading, Card.inset)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(page.lines.enumerated()), id: \.offset) { _, line in
                            Text(line.text)
                                .font(.scaled(11))
                                .foregroundStyle(Color.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("읽은 글자 \(page.lines.count)줄 · \(page.milliseconds)ms")
                        .font(.scaled(12))
                        .foregroundStyle(Color.muted)
                }
                .tint(Color.brand)
                .padding(.horizontal, Card.inset)
                .padding(.vertical, 12)
            }
            .cardSurface()
        }
    }

    /// 화면 총액이 현금을 품었으면 ` · 현금 n`, 총액과 합이 다르면 ` · 차이 n원` — 해외 종목 환산 반올림(종목 수만큼 원)은 검산 통과로 본다.
    private func differenceText(_ result: CaptureParser.Result) -> String {
        guard let total = result.totalMinor else { return "" }
        var text = ""
        if let cash = result.cashMinor, result.expectedSumMinor != result.sumMinor {
            text += " · 현금 \(Won.grouped(cash))"
        }
        if total != result.expectedSumMinor {
            text += " · 차이 \(Won.grouped(abs(total - result.expectedSumMinor)))원"
        }
        return text
    }

    private func rowView(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.read)
                    .font(.scaled(13.5, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                if let match = row.match {
                    Text("→ \(match.name) · \(match.account)")
                        .font(.scaled(11))
                        .foregroundStyle(Color.brand)
                        .lineLimit(1)
                } else {
                    Text("앱 종목과 짝 없음")
                        .font(.scaled(11))
                        .foregroundStyle(Color.caution)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.valueMinor.map { Won.grouped($0) } ?? "금액 못 고름")
                    .font(.figure(13.5, weight: .semibold))
                    .foregroundStyle(row.valueMinor == nil ? Color.caution : Color.ink)
                    .lineLimit(1)
                    .fixedSize()
                if let match = row.match {
                    Text("앱 \(Won.grouped(match.valueMinor))")
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

    // MARK: - 읽기

    private var known: [Known] {
        members.flatMap { member in
            member.sortedAccounts.flatMap { account in
                account.sortedHoldings.map { holding in
                    Known(name: holding.name,
                          account: account.name.isEmpty ? account.kind.label : account.name,
                          valueMinor: holding.valueMinor)
                }
            }
        }
    }

    private func read(_ items: [PhotosPickerItem]) async {
        isReading = true
        failures = []
        pages = []
        let candidates = known
        for (offset, item) in items.enumerated() {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failures.append("\(offset + 1)번째 그림을 열지 못했습니다."); continue
                }
                let started = Date()
                let lines = try await CaptureReader.recognize(data)
                let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
                let result = CaptureParser.parse(lines)
                let rows = result.items.map { item in
                    Row(read: item.name, valueMinor: item.valueMinor,
                        match: CaptureParser.match(item.name, among: candidates.map(\.name)).map { candidates[$0.index] })
                }
                pages.append(Page(number: offset + 1, result: result, rows: rows, lines: lines,
                                  milliseconds: milliseconds))
            } catch {
                failures.append("\(offset + 1)번째 그림을 읽지 못했습니다 — \(error.localizedDescription)")
            }
        }
        // 그림은 여기서 버린다 — 고른 표지(PhotosPickerItem)도 비운다. 남는 것은 화면의 결과뿐.
        picks = []
        isReading = false
    }
}
