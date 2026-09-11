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


extension Plan {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Plan> {
        NSFetchRequest<Plan>(entityName: "Plan")
    }

    @NSManaged var id: UUID

    @NSManaged var title: String

    /// 계획을 세운 해. 로드맵 타임라인의 왼쪽 끝.
    @NSManaged var startYear: Int

    /// 계획을 시작한 날. "언제부터 체계적으로 관리했는지" 를 1페이지에 적는다.
    /// 연도만으로는 그걸 알 수 없다 (docs/08-feedback.md 10번).
    @NSManaged var startedOn: Date?

    /// 기준 시점 라벨 — `2026.08 기준 · 이사 후 자산` 같은 선언.
    /// **같은 자산을 두 번 세지 않기 위한 것**이라 1페이지 머리에 크게 적는다.
    @NSManaged var asOfNote: String

    /// 1페이지 맨 아래 한 줄. `계획은 끝났다. 이제는 시간이 일한다.`
    @NSManaged var declaration: String

    /// 은퇴 목표 연도. 궤적은 여기서 멈춘다.
    @NSManaged var retirementYear: Int

    @NSManaged var monthlyContributionMinor: Int

    /// 연 기대수익률 (basis point). 800 = 8%
    @NSManaged var annualReturnBP: Int

    /// 적립액의 연 증가율. 연봉 상승률에 맞춘다.
    @NSManaged var contributionGrowthBP: Int

    @NSManaged var inflationBP: Int

    /// **은퇴 후 기대수익률** (basis point). 기본 500 = 5% — 은퇴하면 안전자산
    /// 비중을 높이므로 보수적으로 잡는다 (사용자 결정, docs/08-feedback.md 67번).
    /// 은퇴 뒤 계획 수익률을 따르는 투자 덩어리가 이 속도로 굴며, 현황판·
    /// 계획·시뮬레이션이 같이 읽는다.
    @NSManaged var postRetirementReturnBP: Int

    /// 저수익 자산의 기대수익률. 예적금·연금보험이 여기 붙는다.
    /// 계좌마다 따로 적으면 그 값이 이긴다 (`Account.expectedReturnBP`).
    @NSManaged var lowYieldReturnBP: Int

    /// 부동산 기대수익률. 기본은 물가상승률과 같게 둔다.
    @NSManaged var realEstateReturnBP: Int

    /// **채권** 종목의 기대수익률 (D6). 기본 350 = 3.5%. 투자 계좌 안에 있어도
    /// 채권은 주식 속도로 안 자란다 — 종목의 자산군이 채권이면 이 값으로 굴린다.
    /// 계좌에 수익률을 따로 적었으면 그 값이 이긴다.
    @NSManaged var bondReturnBP: Int

    /// **금 · 원자재** 종목의 기대수익률 (D6). 기본 300 = 3% — 긴 기간 금은
    /// 물가보다 조금 앞서는 정도였다. 위와 같은 규칙으로 붙는다.
    @NSManaged var commodityReturnBP: Int

    /// 은퇴 시점 목표 금액. 0이면 목표선을 그리지 않는다.
    @NSManaged var targetAmountMinor: Int

    /// 은퇴 후 한 달 생활비. 0이면 은퇴 필요 자금을 판단하지 않는다.
    @NSManaged var monthlySpendingMinor: Int

    /// 인출률. 400 = 4% (4% 규칙).
    @NSManaged var withdrawalRateBP: Int

    /// 세후 월 소득. 저축률 계산에만 쓴다.
    @NSManaged var monthlyIncomeMinor: Int

    /// 최소 저축률. 1000 = 10%.
    @NSManaged var savingsFloorBP: Int

    /// 부동산 · 전월세보증금 비중 상한. 3500 = 35%.
    @NSManaged var illiquidCapBP: Int

    /// 미국 목표 비중. 6000 = 60%.
    @NSManaged var usTargetBP: Int

    /// 목표에서 이만큼 벗어나도 조치로 보지 않는다. 500 = 5%p.
    @NSManaged var mixToleranceBP: Int

    /// 목표 비중 허용 오차 — 절대(퍼센트포인트). 기본 5%p.
    /// 목표 비중 허용 오차 (퍼센트포인트). 기본 ±3%p — 목표 20%인 종목은
    /// 17~23% 안이면 지키는 것으로 본다 (docs/08-feedback.md 20번).
    @NSManaged var driftToleranceBP: Int

    /// 목표 비중 허용 오차 — 상대(목표 대비). 기본 25%.
    /// 목표가 작은 종목에 절대값만 쓰면 영영 안 걸린다.
    /// ⚠️ **쓰지 않는다** (docs/08-feedback.md 38번).
    ///
    /// 20번에서 허용 오차를 퍼센트포인트 하나로 단순화하면서 상대 오차를
    /// 걷어냈다. 그런데 **지우지 않고 남겨 둔다** — CloudKit Production
    /// 스키마는 필드를 지울 수 없고(더하기만 된다), 모델에서만 지우면 저장소
    /// 마이그레이션 위험까지 진다. 안 쓰는 정수 하나가 남는 값은 0에 가깝다.
    /// 다음에 스키마를 크게 손볼 일이 있으면 그때 함께 뺀다.
    @NSManaged var driftRelativeBP: Int

    /// 꺼 둔 진단 규칙 (docs/08-feedback.md 47번). 쉼표로 이어 붙인 rawValue.
    ///
    /// **끈 것을 저장한다** — 켠 것을 저장하면 나중에 규칙이 늘었을 때
    /// 새 규칙이 꺼진 채로 태어난다. 빈 문자열이면 전부 켜져 있다는 뜻이다.
    @NSManaged var disabledDiagnosesRaw: String

    /// 세제혜택 계좌를 채우는 순서. 쉼표로 이어 붙인 `AccountKind` rawValue.
    /// 비어 있으면 기본 순서(IRP → 연금저축 → ISA)를 쓴다.
    @NSManaged var contributionOrderRaw: String

    /// 월 적립을 구성원별로 나눠 넣는가. 켜면 Member 의 몫을 합해서 쓴다.
    ///
    /// 합계 하나로도 궤적은 똑같이 그려진다. 나누는 이유는 "누가 얼마를 넣고
    /// 있는가"가 가족이 함께 보는 화면에서 의미를 갖기 때문이다.
    @NSManaged var usesMemberContributions: Bool

    /// 궤적을 어디까지 그릴 것인가. 은퇴 이후 인출 구간의 끝이다.
    /// 기본은 은퇴 후 35년 — 65세 은퇴면 100세까지 본다.
    @NSManaged var horizonYear: Int

    @NSManaged var createdAt: Date

    /// 마지막으로 고친 때. 계획은 한 번 세우고 계속 다듬는 것이라, 제목보다
    /// **언제 갱신했는지**가 알고 싶은 값이다 (docs/08-feedback.md 21번).
    ///
    /// `touch()` 로 찍는다. 화면이 값을 바꿀 때마다 부른다.
    @NSManaged var updatedAt: Date?
    /// 공유의 뿌리 (docs/09-family-sharing.md 2단계). `CKShare` 는 **관계로
    /// 이어진 것**만 공유 존으로 옮기므로, 이 한 줄이 없으면 나중에 만든 것이
    /// 상대 화면에 조용히 안 보인다. 옵셔널인 것은 CloudKit 제약이다.
    @NSManaged var household: Household?

}
