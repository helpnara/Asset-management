import SwiftUI

/// 지금 **남의 눈으로 보고 있다**는 띠 (docs/09-family-sharing.md 4단계).
///
/// 이 띠 없이 보기 전용으로 두면, 며칠 뒤에 열었을 때 버튼이 안 눌리는 것을
/// 고장으로 읽는다. 되돌아오는 길(`관리자로`)을 띠 안에 둔 것도 그래서다 —
/// 더보기까지 찾아 들어가게 하지 않는다.
struct RolePreviewBanner: View {
    let role: FamilyRole
    let exit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye")
                .font(.system(size: 12, weight: .semibold))
            Text("\(role.label) 화면으로 보는 중")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            Button("관리자로", action: exit)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Color.onInk)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color.dad)
        .accessibilityElement(children: .combine)
    }
}

/// 보기 전용일 때 **왜 못 고치는지**를 그 자리에 적는다.
///
/// 버튼을 그냥 없애면 "원래 없는 기능" 으로 읽혀서, 권한을 넓혀 달라고 할
/// 생각을 못 한다. 그래서 자리는 남기고 이유를 적는다.
struct ReadOnlyNote: View {
    var text = "보기 전용입니다. 고치려면 관리자에게 권한을 요청하세요."

    var body: some View {
        Label(text, systemImage: "lock")
            .font(.system(size: 12))
            .foregroundStyle(Color.muted)
    }
}
