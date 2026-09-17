import Core
import CoreData
import SwiftUI

/// **데이터 전부 지우기** (G3, 자리는 152번 2-8 에서 옮겼다).
///
/// 예전에는 내보내기 화면 맨 아래에 있었다. 백업을 받으러 들어간 화면에서
/// "전부 지우기" 를 만나는 것은 **반대 방향의 일이 한 화면에 있는 것**이라,
/// 더보기 → 앱 설정의 마지막 줄로 뺐다. 지우는 절차는 그대로다 —
/// 확인 창에 `전부 지우기` 를 직접 쳐야 버튼이 산다.
struct EraseAllView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// **관리자만이다.** iCloud 는 삭제까지 퍼뜨리므로 참가자가 자기 기기에서
    /// 지우면 관리자의 기록까지 사라진다 (40번 · 98번과 같은 이유).
    @Environment(\.canManageHousehold) private var canManageHousehold

    @State private var isConfirming = false
    @State private var phrase = ""
    private static let keyword = "전부 지우기"

    var body: some View {
        List {
            if canManageHousehold {
                Section {
                    Button(role: .destructive) {
                        phrase = ""
                        isConfirming = true
                    } label: {
                        Label("데이터 전부 지우기", systemImage: "trash")
                    }
                } footer: {
                    Text("구성원 · 계좌 · 종목 · 지난 기록 · 계획 · 일기까지 **전부** 지웁니다. iCloud 로 퍼져 가족의 기기에서도 사라지고, 되돌릴 수 없습니다. 가족 초대는 남습니다 — 끊으려면 더보기의 가족 에서 하세요.")
                }

                Section {
                    Text("지우기 전에 **더보기 → 내보내기 → 전체 백업 만들기** 로 한 부 받아 두세요. 나중에 같은 파일로 되돌릴 수 있습니다.")
                        .font(.scaled(12.5))
                        .foregroundStyle(Color.muted)
                }
            } else {
                Section {
                    Text("지우기는 관리자 기기에서만 할 수 있습니다. 참가자 기기에서 지우면 관리자의 기록까지 사라지기 때문입니다.")
                        .font(.scaled(12.5))
                        .foregroundStyle(Color.muted)
                }
            }
        }
        .navigationTitle("데이터 전부 지우기")
        .navigationBarTitleDisplayMode(.inline)
        .alert("정말 전부 지울까요?", isPresented: $isConfirming) {
            TextField("\(Self.keyword) 라고 입력", text: $phrase)
            Button("지우기", role: .destructive) {
                guard phrase.trimmingCharacters(in: .whitespaces) == Self.keyword else { return }
                BackupDocument.wipeAll(in: context)
                dismiss()
            }
            .disabled(phrase.trimmingCharacters(in: .whitespaces) != Self.keyword)
            Button("그만두기", role: .cancel) { phrase = "" }
        } message: {
            Text("되돌릴 수 없습니다. 확인하려면 \"\(Self.keyword)\" 라고 입력하세요.")
        }
    }
}
