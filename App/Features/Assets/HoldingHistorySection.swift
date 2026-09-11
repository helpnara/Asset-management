import Charts
import Core
import CoreData
import SwiftUI

/// **종목 하나의 지난 값** (A3). 종목 편집 시트 안의 한 구역.
///
/// 궤적 · 몇 주 전과 비교 · 잘못 넣은 값을 지난주 값으로 되돌리기 — 셋 다
/// 여기서 한다. 줄을 누르면 "이 값으로 되돌릴까요?" 를 묻는다.
struct HoldingHistorySection: View {
    @ObservedObject var holding: Holding
    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEdit) private var canEdit
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @State private var records: [HoldingRecord] = []
    @State private var restoring: HoldingRecord?

    var body: some View {
        Section {
            if records.isEmpty {
                Text("아직 없습니다. 주간 점검을 끝낼 때마다 그 주의 값이 한 줄씩 남습니다.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.muted)
            } else {
                if records.count >= 3 { chart }
                ForEach(records.suffix(8).reversed()) { record in
                    row(record)
                }
            }
        } header: {
            Text("지난 값")
        } footer: {
            if !records.isEmpty {
                Text(canEdit
                     ? "줄을 누르면 그 주의 값으로 되돌립니다. 최근 \(min(records.count, 8))주를 보이고, 궤적은 \(records.count)주입니다."
                     : "최근 \(min(records.count, 8))주입니다.")
            }
        }
        .onAppear { records = HoldingRecord.history(of: holding.id, in: context) }
        .alert("이 값으로 되돌릴까요?",
               isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
               presenting: restoring) { record in
            Button("되돌리기") {
                guard record.valueMinor != holding.valueMinor else { return }
                holding.rollBaselineIfNewWeek()
                holding.valueMinor = record.valueMinor
                restoring = nil
            }
            Button("그만두기", role: .cancel) { restoring = nil }
        } message: { record in
            Text("\(Self.week(record.weekAnchor)) 의 \(KoreanAmountFormatter.full(Money(minorUnits: record.valueMinor, currency: .krw))) 으로 평가액을 바꿉니다. 이번 주 기준값은 그대로입니다.")
        }
    }

    private var chart: some View {
        Chart(records) { record in
            LineMark(x: .value("주", record.weekAnchor), y: .value("값", record.valueMinor))
                .foregroundStyle(Color.dad)
                .interpolationMethod(.monotone)
            PointMark(x: .value("주", record.weekAnchor), y: .value("값", record.valueMinor))
                .foregroundStyle(Color.dad)
                .symbolSize(14)
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minor = value.as(Int.self) {
                        Text(hideAmounts ? "••" : KoreanAmountFormatter.compact(Money(minorUnits: minor, currency: .krw)))
                            .font(.figure(9))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: false)
                    .font(.figure(9))
            }
        }
        .frame(height: 110)
        .padding(.vertical, 4)
    }

    private func row(_ record: HoldingRecord) -> some View {
        let previous = records.last { $0.weekAnchor < record.weekAnchor }
        let delta = previous.map { record.valueMinor - $0.valueMinor }
        return Button {
            guard canEdit else { return }
            restoring = record
        } label: {
            HStack(spacing: 8) {
                Text(Self.week(record.weekAnchor))
                    .font(.figure(12))
                    .foregroundStyle(Color.muted)
                Spacer()
                if let delta, delta != 0 {
                    Text(Won.abbreviated(Money(minorUnits: delta, currency: .krw), sign: .always))
                        .font(.figure(11))
                        .foregroundStyle(delta > 0 ? Color.gain : Color.loss)
                }
                Text(Won.full(Money(minorUnits: record.valueMinor, currency: .krw)))
                    .font(.figure(13, weight: record.valueMinor == holding.valueMinor ? .semibold : .regular))
                    .foregroundStyle(Color.ink)
            }
        }
        .buttonStyle(.plain)
    }

    private static func week(_ date: Date) -> String {
        date.formatted(.dateTime.year(.twoDigits).month(.defaultDigits).day())
    }
}
