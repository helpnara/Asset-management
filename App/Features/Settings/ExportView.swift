import Core
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 내보내기 — 1페이지 이미지와 CSV 백업.
///
/// CSV 는 **백업**이다. 가져오기는 만들지 않았지만(사용자가 직접 넣기로 했다)
/// 내보내기는 다르다. iCloud 가 꺼져 있거나 계정에 문제가 생겼을 때
/// 기록을 꺼낼 길이 하나도 없으면 몇 달치가 통째로 날아간다.
struct ExportView: View {
    @Query(sort: \Snapshot.weekAnchor) private var snapshots: [Snapshot]
    @Query(sort: \Member.sortIndex) private var members: [Member]
    @Query private var holdings: [Holding]
    @Query private var plans: [Plan]
    @Query(sort: \CashEvent.date) private var cashEvents: [CashEvent]
    @Query(sort: \IncomeStream.sortIndex) private var incomes: [IncomeStream]
    @Query(sort: \Principle.order) private var principles: [Principle]
    @Query(sort: \TodoItem.sortIndex) private var todos: [TodoItem]

    @Environment(\.modelContext) private var context

    @State private var isRendering = false
    @State private var rendered: PDFFile?
    @State private var backup: JSONFile?

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
        }
        .navigationTitle("내보내기")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - 1페이지

    @MainActor
    private func render() {
        isRendering = true
        defer { isRendering = false }

        let plan = plans.first
        let calendar = Calendar.current
        let rollup = Valuation.rollUp(holdings.compactMap { $0.position() }, base: .krw)
        let projection = plan?.projection(from: rollup.netWorth, cashEvents: cashEvents,
                                          incomes: incomes, members: members)

        let page = OnePagerView(
            title: plan?.title ?? "우리 가족 노후자금 준비",
            asOfNote: plan?.asOfNote ?? "",
            startedOn: plan?.startedOn,
            retirementYear: plan?.retirementYear ?? calendar.component(.year, from: .now) + 23,
            declaration: plan?.declaration ?? "",
            rollup: rollup,
            members: members,
            snapshots: snapshots,
            milestones: projection?.milestones ?? [],
            cashEvents: cashEvents.filter { !$0.isAlreadyReflected },
            principles: principles,
            todos: todos,
            usShare: rollup.countryShare("US"),
            nextReview: ReviewWeek.nextSaturday(after: .now, calendar: calendar)
        )

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
