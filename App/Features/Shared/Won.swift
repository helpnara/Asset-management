import Core
import SwiftUI

/// 화면에 금액을 쓸 때 통과시키는 문. **금액 가리기가 켜져 있으면 `••••` 로 바뀐다.**
///
/// `KoreanAmountFormatter` 는 `Core` 에 있고 `Core` 는 사용자 설정을 몰라야 한다
/// (ADR-0002 — 그 경계가 깨지면 원격에서 검증할 수 있는 범위가 사라진다).
/// 그래서 가리기는 앱 쪽 이 얇은 껍데기에서 한다.
///
/// **예외 둘.** 입력 칸(`MoneyField`)은 가리지 않는다 — 입력 중에 가려지면 고칠 수
/// 없다. 알림 본문도 여기를 쓰지 않는다 — 잠금 화면에 뜨는 글이라 별도 설정을 따른다.
enum Won {
    static func abbreviated(
        _ money: Money,
        suffix: String = "",
        sign: KoreanAmountFormatter.SignStyle = .negativeOnly
    ) -> String {
        AmountPrivacy.mask(KoreanAmountFormatter.abbreviated(money, suffix: suffix, sign: sign))
    }

    static func compact(
        _ money: Money,
        sign: KoreanAmountFormatter.SignStyle = .negativeOnly
    ) -> String {
        AmountPrivacy.mask(KoreanAmountFormatter.compact(money, sign: sign))
    }

    static func full(
        _ money: Money,
        suffix: String = "원",
        sign: KoreanAmountFormatter.SignStyle = .negativeOnly
    ) -> String {
        AmountPrivacy.mask(KoreanAmountFormatter.full(money, suffix: suffix, sign: sign))
    }

    static func grouped(_ value: Int) -> String {
        AmountPrivacy.mask(KoreanAmountFormatter.grouped(value))
    }
}
