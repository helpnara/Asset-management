// **이 파일은 이제 손으로 고친다.** 예전에는 생성물이었다.
//
// 4차 1b-2 로 `@Model` 이 사라지면서 원본이 `App/SlowRich.xcdatamodeld` 가
// 됐다. 그런데 모델 파일에는 주석 칸이 없다 — 아래 `///` 들은 "왜 이 칸이
// 있나" 를 적어 둔 이 저장소의 자산인데, 모델에서 다시 뽑으면 **전부
// 날아간다.** 그래서 `generate-managed-classes.py` 는 더 돌리지 않는다
// (돌리면 스스로 막는다).
//
// 칸을 더할 때는 **셋을 함께** 고친다:
//   App/SlowRich.xcdatamodeld · 이 파일 · Tools/cloudkit/slowrich.ckdb
// CI 가 서로 대조하므로 하나만 고치면 빌드가 막힌다.

import CoreData
import Foundation

/// **이 종목을 왜 샀고, 생각이 어떻게 바뀌었나** (186번).
///
/// 예전에는 `Holding.note` 한 칸에 적었는데 둘이 문제였다. 하나는 **화면
/// 어디에도 안 나왔다** — 읽는 곳이 `Backup` 뿐이라 적고 나면 편집 시트를
/// 다시 열어야만 보였다. 다른 하나는 **칸이 하나라 고치면 옛 이유가 사라진
/// 것**이다. 그런데 3년 뒤에 아픈 것은 처음 이유를 잊는 것이 아니라,
/// **그 이유가 조용히 만료됐는데 아무도 눈치채지 못한 것**이다.
///
/// 그래서 줄이 쌓이는 그릇으로 옮겼다. `Holding.note` 는 스키마에 그대로
/// 남겨 두되(CloudKit 에서 칸을 빼는 것은 아프다) 화면에서는 안 쓰고,
/// 이미 적어 둔 내용은 사용자가 버튼으로 **첫 줄로 옮긴다** — 저절로 옮기면
/// 기기 넷이 같은 일을 동시에 해서 줄이 겹칠 수 있다.
///
/// **판 종목은 지우지 말고 `정리 완료` 로 둔다.** 그러면 이유가 그대로 남는다.
/// `HoldingRecord` 처럼 이름을 복사해 두지 않는 것은 그래서다 — 지워진 종목의
/// 이유를 보여 줄 화면이 따로 없는데 줄만 남으면 읽을 길 없는 기록이 된다.
@objc(HoldingNote)
class HoldingNote: NSManagedObject, Identifiable {

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        at = Date.now
    }
}
