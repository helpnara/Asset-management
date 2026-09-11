import Core
import CoreData
import SwiftUI

/// **국민연금 얼마나 받을까** (D3). 가입 기간과 평균 소득으로 근사해
/// "은퇴 후 소득" 한 줄을 채운다.
///
/// 배우는 도구다 — 공단의 예상연금 조회가 정답이고, 여기 값은 "대략 이 정도"
/// 다. 모르면 0 을 넣고 아는 만큼 고친다 (사용자 결정 09-11).
struct NationalPensionEstimatorView: View {
    @ObservedObject var stream: IncomeStream
    @Environment(\.dismiss) private var dismiss

    @State private var firstYear: Int
    @State private var lastYear: Int
    @State private var incomeMinor: Int = 3_000_000
    /// 실제 가입 개월 수 (125번). 손대기 전에는 연도 폭 전부.
    @State private var monthsOverride: Int?
    /// 태어난 해 → 수령 개시 나이 (1969년생부터 65세).
    @State private var birthYear: Int
    @Fetched(sort: \Member.sortIndex) private var members: [Member]

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    init(stream: IncomeStream) {
        self.stream = stream
        let year = Calendar.current.component(.year, from: .now)
        _firstYear = State(initialValue: year - 15)
        _lastYear = State(initialValue: year + 10)
        _birthYear = State(initialValue: year - 45)
    }

    private var spanMonths: Int { max(0, lastYear - firstYear + 1) * 12 }
    private var months: Int { min(monthsOverride ?? spanMonths, spanMonths) }
    private var claimYear: Int { birthYear + NationalPension.claimAge(birthYear: birthYear) }

    private var estimate: NationalPension.Estimate? {
        NationalPension.estimate(averageMonthlyIncome: Money(minorUnits: incomeMinor, currency: .krw),
                                 firstYear: firstYear, lastYear: lastYear, months: months)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $firstYear, in: NationalPension.firstSchemeYear...currentYear) {
                        LabeledContent("처음 낸 해") { Text(verbatim: "\(firstYear)년").font(.figure(15)) }
                    }
                    Stepper(value: $lastYear, in: firstYear...(currentYear + 50)) {
                        LabeledContent("마지막으로 내는 해") { Text(verbatim: "\(lastYear)년").font(.figure(15)) }
                    }
                    // 공단 화면의 "총 N개월" (125번). 중간에 안 낸 기간이 있으면 폭보다 짧다.
                    HStack {
                        Text("실제 가입 개월 수")
                        Spacer()
                        TextField("개월", value: Binding(
                            get: { months },
                            set: { monthsOverride = $0 == spanMonths ? nil : max(0, $0) }
                        ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.figure(15))
                            .frame(maxWidth: 90)
                        Text("개월").foregroundStyle(Color.muted)
                    }
                    MoneyField(title: "가입 기간 평균 월소득", minorUnits: $incomeMinor)
                } header: {
                    Text("가입 기간과 소득")
                } footer: {
                    Text("공단 앱 '예상연금액 조회' 의 **총 예상가입기간(N개월)** 을 그대로 적으면 가장 가깝습니다 — 중간에 안 낸 달이 있으면 연도 폭보다 짧습니다. 월소득은 **오늘 돈 기준** 세전 기준소득월액이고, 상한 \(KoreanAmountFormatter.compact(Money(minorUnits: NationalPension.incomeCeilingMinor, currency: .krw))) 을 넘으면 상한으로 봅니다.")
                }

                Section {
                    Stepper(value: $birthYear, in: 1940...currentYear) {
                        LabeledContent("태어난 해") { Text(verbatim: "\(birthYear)년").font(.figure(15)) }
                    }
                    if members.contains(where: { $0.birthYear > 0 }) {
                        Menu {
                            ForEach(members.filter { $0.birthYear > 0 }) { member in
                                Button("\(member.name) · \(String(member.birthYear))년") { birthYear = member.birthYear }
                            }
                        } label: {
                            Label("구성원의 생년으로", systemImage: "person.2")
                        }
                    }
                    LabeledContent("받기 시작") {
                        Text(verbatim: "\(claimYear)년 (\(NationalPension.claimAge(birthYear: birthYear))세)")
                            .font(.figure(14))
                    }
                } header: {
                    Text("받는 시기")
                } footer: {
                    Text("1969년생부터 65세, 그 전은 4년마다 한 살씩 빠릅니다. 조기·연기 수령은 반영하지 않습니다.")
                }

                Section {
                    if let estimate {
                        LabeledContent("예상 월 수령액") {
                            Text(KoreanAmountFormatter.full(estimate.monthly))
                                .font(.figure(17, weight: .semibold))
                                .foregroundStyle(Color.ink)
                        }
                        LabeledContent("가입 기간") {
                            Text(verbatim: "\(months)개월 (\(estimate.years)년)").font(.figure(14))
                        }
                        LabeledContent("적용 소득대체율") {
                            Text("\(PercentFormatter.oneDecimal(Decimal(estimate.replacementBP) / 10_000))%")
                                .font(.figure(14))
                        }
                    } else {
                        Text("가입 기간이 \(NationalPension.minimumYears)년 미만이면 연금이 아니라 반환일시금입니다.")
                            .font(.scaled(12.5))
                            .foregroundStyle(Color.loss)
                    }
                } header: {
                    Text("추정")
                } footer: {
                    Text("기본연금액 = 비례상수 × (A값 + 본인 평균소득) × (1 + 0.05 × 20년 초과 연수). A값은 전체 가입자의 최근 3년 평균 월소득(2026년 \(KoreanAmountFormatter.full(Money(minorUnits: NationalPension.referenceAValueMinor, currency: .krw))))이고, 비례상수는 가입 연도마다 달라 2026년부터는 1.29(소득대체율 43%)입니다. 오늘 돈 기준이라 그대로 적으면 됩니다.")
                }

                Section {
                    Button {
                        apply()
                    } label: {
                        Label("이 값으로 채우기", systemImage: "arrow.down.doc")
                    }
                    .disabled(estimate == nil)
                } footer: {
                    Text("**세전 참고값입니다.** 공단 예상액과 개월 수를 맞추면 1~2% 안에 들어오지만, 소득 재평가·크레딧·조기·연기 수령은 반영하지 않습니다. 공단 앱에서 확인한 세후 값을 알게 되면 그 값으로 고치세요.")
                }
            }
            .navigationTitle("국민연금 얼마나 받을까")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
    }

    /// 수령 시작은 태어난 해가 정하는 개시 연도(마지막 납부 다음 해보다는 뒤), 종신,
    /// 물가 연동 — 국민연금이 그런 연금이다.
    private func apply() {
        guard let estimate else { return }
        stream.monthlyAmountMinor = estimate.monthly.minorUnits
        if stream.label.isEmpty { stream.label = "국민연금 (추정)" }
        stream.startYear = max(claimYear, lastYear + 1, currentYear)
        stream.endYear = 0
        stream.isInflationLinked = true
        dismiss()
    }
}
