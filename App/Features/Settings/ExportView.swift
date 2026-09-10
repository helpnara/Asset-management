import Core
import CoreData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 내보내기 — 1페이지 이미지와 CSV 백업.
///
/// CSV 는 **백업**이다. 가져오기는 만들지 않았지만(사용자가 직접 넣기로 했다)
/// 내보내기는 다르다. iCloud 가 꺼져 있거나 계정에 문제가 생겼을 때
/// 기록을 꺼낼 길이 하나도 없으면 몇 달치가 통째로 날아간다.
struct ExportView: View {
    @Fetched(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]
    @Fetched(sort: \Member.sortIndex) private var members: [Member]
    @Fetched private var holdings: [Holding]
    @Fetched(sort: \Plan.createdAt) private var plans: [Plan]
    @Fetched(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Fetched(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Fetched(sort: \Principle.order) private var principles: [Principle]
    @Fetched(sort: \TodoItem.sortIndex) private var todos: [TodoItem]

    @Environment(\.managedObjectContext) private var context
    /// **되돌리기는 관리자만이다.** iCloud 는 삭제까지 퍼뜨리므로, 참가자가
    /// 자기 기기에서 되돌리면 관리자의 기록까지 갈아 끼운다 (40번).
    @Environment(\.canManageHousehold) private var canManageHousehold

    @State private var isRendering = false
    @State private var rendered: PDFFile?
    @State private var backup: JSONFile?

    /// 되돌리기 (docs/08-feedback.md 40번).
    @State private var isPickingBackup = false
    @State private var pending: BackupDocument?
    @State private var restoreProblem: String?

    var body: some View {
        List {
            Section {
                Button {
                    render()
                } label: {
                    HStack {
                        Label("1페이지 PDF 만들기", systemImage: "doc.richtext")
                        Spacer()
                        if isRendering { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isRendering || members.isEmpty)

                if let rendered {
                    ShareLink(item: rendered, preview: SharePreview(rendered.name)) {
                        Label("공유 · 저장", systemImage: "square.and.arrow.up")
                    }
                }

                // **뽑기 전에 눈으로 본다.** 한 장에 들어가는지는 렌더를 봐야
                // 알 수 있고, 원격 세션에서는 CI 스크린샷이 이 화면을 찍는다.
                NavigationLink(value: MoreView.Destination.onePagerPreview) {
                    Label("한 장 미리보기", systemImage: "doc.text.magnifyingglass")
                }
            } header: {
                Text("1페이지")
            } footer: {
                Text("현재 값으로 A4 한 장을 그립니다. **PDF 라 인쇄해도 선명하고 글자를 고를 수 있습니다.** 화면이 어두운 모드여도 종이는 흰색으로 나옵니다.")
            }

            Section {
                ShareLink(item: snapshotCSV,
                          preview: SharePreview("주간 기록.csv")) {
                    Label("주간 기록 CSV", systemImage: "tablecells")
                }
                ShareLink(item: holdingsCSV,
                          preview: SharePreview("보유 종목.csv")) {
                    Label("보유 종목 CSV", systemImage: "list.bullet.rectangle")
                }
            } header: {
                Text("보기용 백업")
            } footer: {
                Text("스프레드시트로 열어 보는 용도입니다. 주간 기록과 보유 종목만 담깁니다.")
            }

            Section {
                Button {
                    let document = BackupDocument.make(from: context)
                    backup = JSONFile(data: document.encoded(), name: document.suggestedFileName)
                } label: {
                    Label("전체 백업 만들기", systemImage: "shippingbox")
                }

                if let backup {
                    ShareLink(item: backup, preview: SharePreview(backup.name)) {
                        Label("공유 · 저장", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("전체 백업")
            } footer: {
                Text("구성원 · 계좌 · 종목 · 계획 · 목돈 · 연금 · 할 일 · 마일스톤 · 주간 기록까지 **전부** 한 파일에 담습니다. 지금 이 기록의 사본은 이 아이폰 하나뿐이니, 앱을 업데이트하기 전에 한 번씩 받아 파일 앱이나 메일로 보내 두세요. 금액은 가리지 않고 그대로 나갑니다 — 백업이니까요.")
            }

            // **되돌리기** (docs/08-feedback.md 40번).
            // 내보내기만 있고 되돌리기가 없었다. iCloud 는 삭제까지 동기화하므로
            // 잘못 지운 것을 되찾을 길이 하나도 없었다.
            if canManageHousehold {
                Section {
                    Button(role: .destructive) {
                        isPickingBackup = true
                    } label: {
                        Label("백업 파일에서 되돌리기", systemImage: "arrow.counterclockwise")
                    }
                } header: {
                    Text("되돌리기")
                } footer: {
                    Text("백업 파일을 골라 **이 기기의 기록을 통째로 갈아 끼웁니다.** 지금 들어 있는 것은 전부 지워지고, iCloud 로도 그렇게 퍼집니다. 되돌리기 전에 **먼저 지금 상태로 백업을 하나 만들어 두세요** — 위의 `전체 백업 만들기` 입니다.")
                }
            }
        }
        .fileImporter(isPresented: $isPickingBackup,
                      allowedContentTypes: [.json]) { result in
            load(result)
        }
        .alert("이 백업으로 되돌릴까요?",
               isPresented: Binding(get: { pending != nil },
                                    set: { if !$0 { pending = nil } }),
               presenting: pending) { document in
            Button("되돌리기", role: .destructive) {
                BackupDocument.restore(document, into: context)
                pending = nil
            }
            Button("그만두기", role: .cancel) { pending = nil }
        } message: { document in
            Text(summary(of: document))
        }
        .alert("이 파일은 읽을 수 없습니다",
               isPresented: Binding(get: { restoreProblem != nil },
                                    set: { if !$0 { restoreProblem = nil } }),
               presenting: restoreProblem) { _ in
            Button("확인", role: .cancel) { restoreProblem = nil }
        } message: { problem in
            Text(problem)
        }
        .navigationTitle("내보내기")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 되돌리기

    /// 고른 파일을 읽어 **확인 창까지만** 띄운다. 되돌리기는 사람이 한 번 더
    /// 눌러야 일어난다 — 잘못 누르면 몇 달치가 사라지는 일이다.
    private func load(_ result: Result<URL, Error>) {
        guard case let .success(url) = result else {
            restoreProblem = "파일을 열지 못했습니다."
            return
        }
        // 파일 앱에서 고른 파일은 보안 범위 안에 있다. 열쇠를 쥐었다 놓아야 읽힌다.
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else {
            restoreProblem = "파일을 읽지 못했습니다."
            return
        }
        guard let document = BackupDocument.decode(data) else {
            restoreProblem = "이 앱이 만든 백업 파일이 아니거나 형식이 다릅니다. 전체 백업 만들기로 만든 .json 파일을 골라 주세요."
            return
        }
        pending = document
    }

    /// 무엇이 들어오는지 세어서 보여준다. "정말 되돌릴까요?" 만으로는
    /// 무엇으로 바뀌는지 알 수 없다.
    private func summary(of document: BackupDocument) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일"
        let accountCount = document.members.reduce(0) { $0 + $1.accounts.count }
        let holdingCount = document.members.reduce(0) { sum, member in
            sum + member.accounts.reduce(0) { $0 + $1.holdings.count }
        }
        let counts = "구성원 \(document.members.count)명 · 계좌 \(accountCount)개 · 종목 \(holdingCount)개 · 주간 기록 \(document.snapshots.count)주"
        return formatter.string(from: document.exportedAt) + " 백업\n\n" + counts
            + "\n\n지금 이 기기에 있는 기록은 전부 지워지고 이 파일의 내용으로 바뀝니다. 되돌릴 수 없습니다."
    }

    // MARK: - 1페이지

    @MainActor
    private func render() {
        isRendering = true
        defer { isRendering = false }

        let plan = plans.first
        // 미리보기와 **같은 함수**로 만든다. 따로 만들면 조용히 어긋난다.
        let page = OnePagerBuilder.make(plan: plan, members: members, holdings: holdings,
                                        cashEvents: cashEvents, incomes: incomes,
                                        principles: principles, todos: todos, snapshots: snapshots)

        // **PDF 로 뽑는다.** 원본이 PDF 였고, 인쇄가 선명하고 글자를 고를 수 있다.
        // `ImageRenderer` 가 CGPDFContext 에 그려 주므로 뷰는 하나로 쓴다.
        let renderer = ImageRenderer(content: page)
        // `CGDataConsumer` 는 `NSMutableData` 로만 받는다.
        let buffer = NSMutableData()
        renderer.render { size, draw in
            guard let consumer = CGDataConsumer(data: buffer) else { return }
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return }
            context.beginPDFPage(nil)
            draw(context)
            context.endPDFPage()
            context.closePDF()
        }
        let data = buffer as Data
        guard !data.isEmpty else { return }
        rendered = PDFFile(data: data, name: "\(plan?.title ?? "노후자금") 1페이지.pdf")
    }

    // MARK: - CSV

    /// 스프레드시트가 열 때 깨지지 않도록 큰따옴표를 두 번 쓰고 감싼다.
    private func cell(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private var snapshotCSV: CSVFile {
        var lines = ["주차,순자산,투자자산,부채"]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        for snapshot in snapshots {
            lines.append([
                formatter.string(from: snapshot.weekAnchor),
                "\(snapshot.netWorthMinor)",
                "\(snapshot.investableMinor)",
                "\(snapshot.liabilitiesMinor)"
            ].joined(separator: ","))
        }
        return CSVFile(text: lines.joined(separator: "\n"), name: "주간 기록.csv")
    }

    private var holdingsCSV: CSVFile {
        var lines = ["구성원,계좌,종목,자산군,상장국가,평가액,입력주기"]
        for member in members {
            for account in member.sortedAccounts {
                for holding in account.sortedHoldings {
                    lines.append([
                        cell(member.name), cell(account.name), cell(holding.name),
                        cell(holding.assetClass.label), cell(holding.listingCountryCode),
                        "\(holding.valueMinor)", cell(holding.cadence.label)
                    ].joined(separator: ","))
                }
            }
        }
        return CSVFile(text: lines.joined(separator: "\n"), name: "보유 종목.csv")
    }
}

/// `ShareLink` 에 넘길 CSV. 엑셀이 한글을 깨지 않도록 BOM 을 붙인다.
struct CSVFile: Transferable {
    let text: String
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            // BOM 없이 보내면 엑셀이 한글을 깨서 연다. 실제로 흔한 실패다.
            Data([0xEF, 0xBB, 0xBF]) + Data(file.text.utf8)
        }
        .suggestedFileName { $0.name }
    }
}

/// 1페이지 PDF. 이미지가 아니라 PDF 인 이유는 인쇄가 선명하고 글자를
/// 고를 수 있기 때문이다 (docs/08-feedback.md 10번).
struct PDFFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName { $0.name }
    }
}

/// 전체 백업 파일. 되살리는 기능은 없지만, **꺼내 둘 수는 있어야 한다.**
struct JSONFile: Transferable {
    let data: Data
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.name }
    }
}
