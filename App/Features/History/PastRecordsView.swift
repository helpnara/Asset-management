import Core
import SwiftData
import SwiftUI

/// 지난 기록 직접 입력.
///
/// 2022년부터 투자해 왔는데 앱은 이번 주부터 시작한다면 궤적의 왼쪽 절반이 없다.
/// 계획선 대비 실적을 보는 앱에서 그건 절반만 보는 것이다.
///
/// CSV 가져오기 대신 이 화면을 둔다. 몇 주치를 한 줄씩 옮기는 일이라면
/// 파일 형식을 맞추는 것보다 손으로 넣는 편이 빠르고, 무엇보다 **틀린 값이
/// 조용히 들어오지 않는다** — 눈으로 보면서 넣기 때문이다.
///
/// 여기 넣는 것은 그 시점의 **총액**이다. 종목별 분해까지 되살릴 수는 없고,
/// 그건 애초에 궤적이 요구하는 것도 아니다.
struct PastRecordsView: View {
    // 금액 가리기는 UserDefaults 를 직접 읽는다. 여기서 @AppStorage 로 한 번
    // 더 붙잡아야 토글한 순간 이 화면이 다시 그려진다.
    @AppStorage(AmountPrivacy.key) private var hideAmounts = false

    @Environment(\.modelContext) private var context
    @Query(sort: \Snapshot.weekAnchor, order: .reverse) private var snapshots: [Snapshot]
    @Query private var sessions: [ReviewSession]

    @State private var editing: PastRecordDraft?

    var body: some View {
        List {
            if snapshots.isEmpty {
                Section {
                    Text("아직 기록이 없습니다. 오른쪽 위 + 로 과거 시점의 총자산을 넣으세요.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.muted)
                }
            }

            ForEach(snapshots) { snapshot in
                Button {
                    editing = PastRecordDraft(snapshot)
                } label: {
                    row(snapshot)
                }
            }
            .onDelete(perform: delete)

            Section {
                Text("여기 넣은 값은 궤적의 '실제 기록' 선에 그대로 찍힙니다. 매주 넣을 필요는 없습니다 — 분기에 한 점씩만 있어도 선은 그려집니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.faint)
            }
        }
        .navigationTitle("지난 기록")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = PastRecordDraft()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editing) { draft in
            PastRecordEditView(draft: draft) { save($0) }
        }
    }

    private func row(_ snapshot: Snapshot) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.weekAnchor, format: .dateTime.year().month().day())
                    .font(.system(size: 13))
                    .foregroundStyle(Color.ink)
                if snapshot.liabilitiesMinor != 0 {
                    Text("부채 " + Won.abbreviated(
                        Money(minorUnits: snapshot.liabilitiesMinor, currency: .krw), suffix: "원"))
                        .font(.figure(10))
                        .foregroundStyle(Color.faint)
                }
            }
            Spacer()
            Text(Won.abbreviated(
                Money(minorUnits: snapshot.netWorthMinor, currency: .krw), suffix: "원"))
                .font(.figure(13.5, weight: .medium))
                .foregroundStyle(Color.ink)
        }
    }

    // MARK: - 저장

    private func save(_ draft: PastRecordDraft) {
        let anchor = ReviewWeek.anchor(for: draft.date)

        // 같은 주에 이미 기록이 있으면 덮어쓴다. 주차가 궤적의 키라서
        // 한 주에 점이 둘이면 선이 꺾여 보인다.
        let snapshot = snapshots.first { $0.weekAnchor == anchor }
            ?? {
                let new = Snapshot(weekAnchor: anchor, netWorthMinor: 0,
                                   investableMinor: 0, liabilitiesMinor: 0)
                context.insert(new)
                return new
            }()

        snapshot.netWorthMinor = draft.netWorthMinor
        snapshot.investableMinor = draft.investableMinor
        snapshot.liabilitiesMinor = draft.liabilitiesMinor

        // 점검 기록도 함께 남긴다. 없으면 "기록한 주" 수와 궤적의 점 개수가
        // 어긋나고, 다음 주간 점검이 직전 값을 못 찾아 증감이 0으로 나온다.
        let session = sessions.first { $0.weekAnchor == anchor }
            ?? {
                let new = ReviewSession(weekAnchor: anchor, totalCount: 0)
                context.insert(new)
                return new
            }()

        session.completedAt = session.completedAt ?? draft.date
        session.isTotalOnly = true
        session.totalValueMinor = draft.netWorthMinor
        session.previousTotalValueMinor = snapshots
            .filter { $0.weekAnchor < anchor }
            .max { $0.weekAnchor < $1.weekAnchor }?
            .netWorthMinor ?? 0
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets where snapshots.indices.contains(index) {
            let anchor = snapshots[index].weekAnchor
            context.delete(snapshots[index])
            for session in sessions where session.weekAnchor == anchor && session.isTotalOnly {
                context.delete(session)
            }
        }
    }
}

/// 시트로 넘기는 편집용 값. `@Model` 을 시트 상태로 들고 다니지 않는다.
struct PastRecordDraft: Identifiable {
    let id = UUID()
    var date: Date
    var netWorthMinor: Int
    var investableMinor: Int
    var liabilitiesMinor: Int
    let isNew: Bool

    init() {
        // 지난 토요일. 오늘 날짜로 열어 두면 이번 주 점검과 헷갈린다.
        self.date = ReviewWeek.anchor(for: Date.now.addingTimeInterval(-7 * 86_400))
        self.netWorthMinor = 0
        self.investableMinor = 0
        self.liabilitiesMinor = 0
        self.isNew = true
    }

    init(_ snapshot: Snapshot) {
        self.date = snapshot.weekAnchor
        self.netWorthMinor = snapshot.netWorthMinor
        self.investableMinor = snapshot.investableMinor
        self.liabilitiesMinor = snapshot.liabilitiesMinor
        self.isNew = false
    }
}

struct PastRecordEditView: View {
    @State var draft: PastRecordDraft
    let onSave: (PastRecordDraft) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("시점", selection: $draft.date,
                               in: ...Date.now, displayedComponents: .date)
                } footer: {
                    Text("그 주 토요일 기준으로 저장됩니다. 같은 주에 이미 기록이 있으면 덮어씁니다.")
                }

                Section {
                    MoneyField(title: "순자산", minorUnits: $draft.netWorthMinor)
                } footer: {
                    Text("부채를 뺀 값입니다. 궤적의 '실제 기록' 선이 이 숫자를 잇습니다.")
                }

                Section {
                    MoneyField(title: "투자자산", minorUnits: $draft.investableMinor)
                    MoneyField(title: "부채", minorUnits: $draft.liabilitiesMinor)
                } header: {
                    Text("선택")
                } footer: {
                    Text("몰라도 됩니다. 0으로 두면 그 시점의 비중 분석만 비어 있고 궤적은 그대로 그려집니다.")
                }
            }
            .navigationTitle(draft.isNew ? "지난 기록 추가" : "지난 기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("저장") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.netWorthMinor == 0)
                }
            }
        }
    }
}
