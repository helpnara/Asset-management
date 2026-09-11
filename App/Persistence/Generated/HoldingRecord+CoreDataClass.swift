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

import Core
import CoreData
import Foundation

/// **종목 하나의 그 주 값** (docs/05-roadmap.md A3, 빌드 67).
///
/// `SnapshotLine` 은 구성원 단위라 "이 ETF 가 석 달 동안 어떻게 움직였나",
/// "3주 전 값이 얼마였지", "잘못 넣은 값을 지난주 값으로" 가 전부 불가능했다.
/// 점검을 끝낼 때 종목마다 한 줄씩 남긴다 — 고정 종목까지 전부. 종목을 지워도
/// 줄은 남는다 (이름을 복사해 둔다).
///
/// `Snapshot` 에 안 매단다. 주차의 키는 `weekAnchor` 하나면 되고, 같은 주
/// 기록이 둘이 되는 문제(96번)를 여기까지 끌고 오지 않으려는 것이다.
@objc(HoldingRecord)
class HoldingRecord: NSManagedObject, Identifiable {

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        weekAnchor = Date.now
        holdingID = UUID()
        memberID = UUID()
    }
}
