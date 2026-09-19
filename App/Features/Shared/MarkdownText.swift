import SwiftUI

extension Text {
    /// **굵은 글씨가 있는 안내 글** (docs/08-feedback.md 171번 후속).
    ///
    /// `Text("…**굵게**…")` 는 글자 그대로 적었을 때만 마크다운을 읽고, 조건으로
    /// 고른 `String` 이나 변수로 넘긴 글은 별표를 그대로 찍는다. 그리고 `%**입`
    /// 처럼 문장부호 뒤 · 글자 앞의 닫는 별표는 마크다운 규칙상 안 닫힌다.
    /// 여기서는 `AttributedString(markdown:)` 으로 **항상** 읽어, 어떤 경로로
    /// 만든 글이든 굵은 글씨가 굵게 나온다.
    static func markdown(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }
}
