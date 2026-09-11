import SwiftUI

/// 보기 전용일 때 **왜 못 고치는지**를 그 자리에 적는다.
///
/// 버튼을 그냥 없애면 "원래 없는 기능" 으로 읽혀서, 권한을 넓혀 달라고 할
/// 생각을 못 한다. 그래서 자리는 남기고 이유를 적는다.
struct ReadOnlyNote: View {
    var text = "보기 전용입니다. 고치려면 관리자에게 권한을 요청하세요."

    var body: some View {
        Label(text, systemImage: "lock")
            .font(.scaled(12))
            .foregroundStyle(Color.muted)
    }
}
