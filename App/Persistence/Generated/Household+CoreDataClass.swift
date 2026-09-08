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

/// **공유의 뿌리.** 가구 하나 = `CKShare` 한 장이다.
///
/// 이 엔티티는 화면에 안 나온다. 오로지 **모든 것을 하나에 매달기 위해**
/// 있다 — `share(_:to:)` 는 넘긴 객체와 **관계로 이어진 것**만 공유 존으로
/// 옮기기 때문이다.
///
/// 이게 없으면 어떻게 되나. 2단계 착수 전에 세어 보니 엔티티 15개가 관계
/// 3쌍으로만 이어져 있어 **덩어리가 열둘**이었다 (이 앱은 대부분을
/// `ownerID` 같은 UUID 칸으로 잇는다). 그 상태로 공유를 붙이면 공유한
/// 시점의 것만 넘어가고, **그 뒤에 만든 계좌·점검은 상대 화면에 조용히
/// 안 보인다.** 앱은 멀쩡히 돌기 때문에 아무도 모른다 —
/// 이 저장소가 제일 경계하는 실패다 (docs/09-family-sharing.md 2단계).
///
/// 삭제 규칙은 양쪽 다 `Nullify` 다. 뿌리가 지워져도 **자료는 살아남는다** —
/// 정리용 껍데기가 기록을 데려가서는 안 된다.
@objc(Household)
class Household: NSManagedObject, Identifiable {

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        createdAt = Date.now
    }
}
