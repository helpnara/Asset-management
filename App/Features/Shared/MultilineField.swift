import SwiftUI
import UIKit

/// **여러 줄 입력칸 — 외부 키보드의 Return 도 줄을 바꾼다** (203번).
///
/// `TextField(axis: .vertical)` 는 화면 키보드의 Return 으로는 줄을 바꾸지만, 아이패드에 붙인
/// 외부 키보드의 Return 은 "입력 끝" 으로 받아 아무 일도 하지 않았다(목 · 실 · 감, 10-22 사용자).
/// `TextEditor`(속은 `UITextView`)는 어느 키보드든 줄을 바꾼다.
///
/// 대신 `TextEditor` 는 제 높이를 모르고 안쪽 여백이 있다. 그래서 같은 글자를 투명한 `Text` 로
/// 깔아 높이를 정하고(줄 수 상한까지, 넘으면 편집기 안에서 스크롤), 편집기는 그 위에 얹는다.
/// 편집기의 안쪽 여백(위아래 8 · 좌우 5)만큼 바깥으로 당겨 글자 자리를 예전 입력칸과 맞춘다.
/// 글꼴 · 글자색은 바깥에서 준 것을 그대로 따른다.
struct MultilineField: View {
    let placeholder: String
    @Binding var text: String
    /// 이만큼까지 커지고, 넘으면 안에서 스크롤한다.
    var maxLines = 4

    private static let inset = EdgeInsets(top: 8, leading: 5, bottom: 8, trailing: 5)

    var body: some View {
        // 끝이 줄바꿈이면 `Text` 는 그 빈 줄을 그리지 않는다 — 공백 하나로 줄을 세운다.
        Text(text.isEmpty || text.hasSuffix("\n") ? text + " " : text)
            .lineLimit(maxLines)
            .padding(Self.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(0)
            .accessibilityHidden(true)
            .overlay {
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel(placeholder)
            }
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(Color(uiColor: .placeholderText))
                        .lineLimit(1)
                        .padding(Self.inset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(EdgeInsets(top: -Self.inset.top, leading: -Self.inset.leading,
                                bottom: -Self.inset.bottom, trailing: -Self.inset.trailing))
    }
}
