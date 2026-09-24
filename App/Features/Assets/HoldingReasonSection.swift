import CoreData
import SwiftUI

/// **이 종목을 왜 샀나** (186번). 종목 편집 시트 안의 한 구역.
///
/// 예전에는 `메모` 한 칸이었다. 둘이 문제였다 — 화면 어디에도 안 나와서 적고
/// 나면 다시 못 봤고, 칸이 하나라 고치면 옛 이유가 사라졌다. 3년 뒤에 아픈
/// 것은 처음 이유를 잊는 것이 아니라 **그 이유가 조용히 만료된 것**이라,
/// 줄이 쌓이는 꼴로 옮겼다.
///
/// 지우기 확인 창은 여기 두지 않는다 — 시트(`HoldingEditView`)가 들고 있다.
/// 줄마다 창을 들려 주면 떴다 사라지고 그냥 지워진다 (181번).
struct HoldingReasonSection: View {
    @ObservedObject var holding: Holding
    let pendingDelete: PendingDelete<HoldingNote>

    @Environment(\.managedObjectContext) private var context
    @Environment(\.canEdit) private var canEdit

    @State private var draft = ""
    @FocusState private var isWriting: Bool

    var body: some View {
        Section {
            if canEdit { writer }
            ForEach(holding.sortedNotes) { note in
                row(note)
                    .swipeDelete { pendingDelete.item = note }
            }
            if !holding.note.isEmpty { legacy }
        } header: {
            Text("왜 샀나")
        } footer: {
            Text(footerText)
        }
    }

    // MARK: - 적는 자리

    private var writer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("고른 이유 · 팔 조건", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($isWriting)
            if !trimmedDraft.isEmpty {
                Button("담기") { commit() }
                    .font(.scaled(13, weight: .semibold))
            }
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit() {
        HoldingNote.add(draft, to: holding, in: context)
        draft = ""
        isWriting = false
    }

    // MARK: - 쌓인 줄

    private func row(_ note: HoldingNote) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.stamp)
                .font(.figure(10))
                .foregroundStyle(Color.faint)
            Text(note.body)
                .font(.scaled(12.5))
                .foregroundStyle(Color.bodyText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - 예전 메모 (186번 이전에 `Holding.note` 에 적어 둔 것)

    /// **저절로 안 옮긴다.** 기기 넷이 같은 순간에 옮기면 같은 줄이 여럿
    /// 생긴다. 사람이 한 번 누르는 쪽이 안전하고, 무슨 일이 일어났는지도 보인다.
    private var legacy: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("예전 메모")
                .font(.scaled(10))
                .foregroundStyle(Color.faint)
            Text(holding.note)
                .font(.scaled(12.5))
                .foregroundStyle(Color.muted)
                .fixedSize(horizontal: false, vertical: true)
            if canEdit {
                Button("이력으로 옮기기") {
                    HoldingNote.add(holding.note, to: holding, in: context)
                    holding.note = ""
                }
                .font(.scaled(12, weight: .medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerText: String {
        if holding.sortedNotes.isEmpty && holding.note.isEmpty {
            return canEdit
                ? "고른 이유를 적어 두면 자산 탭과 주간 점검에 가장 최근 줄이 한 줄로 보입니다. 나중에 \"왜 이걸 샀지\" 에 답이 됩니다."
                : "아직 적힌 것이 없습니다."
        }
        return canEdit
            ? "생각이 바뀌면 고치지 말고 새로 적습니다 — 그래야 바뀐 과정이 남습니다. 판 종목은 지우지 말고 상태를 정리 완료 로 두면 이유가 그대로 남습니다."
            : "최신이 위입니다."
    }
}
