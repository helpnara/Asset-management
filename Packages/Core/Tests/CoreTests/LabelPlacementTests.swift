import Foundation
import Testing
@testable import Core

/// **그림 위 글씨가 서로 피해 가는가** (docs/08-feedback.md 209번).
///
/// 빌드 135 의 크게 보기에서 가까운 인생 이벤트 셋이 바닥 한 자리에 포개지고, 목표 글씨가 오늘
/// 세로선에 꿰였다. 글씨를 놓는 셈을 `Core` 로 옮겨 여기서 누른다. 기댓값은 같은 셈을 파이썬으로
/// 따로 짜서 대조했다.
@Suite("LabelPlacement — 겹치지 않게 글씨 놓기")
struct LabelPlacementTests {

    typealias Box = LabelPlacement.Box
    let bounds = Box(minX: 0, minY: 0, width: 300, height: 200)

    @Test("가까운 이벤트 둘은 제 선 옆에 한 줄씩 쌓인다")
    func nearbyEventsStack() {
        let boxes = LabelPlacement.place([
            .init(anchor: .verticalBottom(x: 100, lanes: 4), width: 80, height: 12),
            .init(anchor: .verticalBottom(x: 110, lanes: 4), width: 80, height: 12),
        ], in: bounds, ink: [])
        // 첫째는 바닥 줄(200 - 2 - 12), 둘째는 한 줄 위(186 - 16).
        #expect(boxes[0] == Box(minX: 103, minY: 186, width: 80, height: 12))
        #expect(boxes[1] == Box(minX: 113, minY: 170, width: 80, height: 12))
    }

    @Test("가로선 글씨는 그림이 있는 쪽을 비켜 간다")
    func horizontalAvoidsInk() {
        // 선 바로 위 왼쪽 절반에 무거운 선이 지나간다 — 위 후보들이 그것을 덮으니 아래로.
        let ink = LabelPlacement.trace([(x: 0, y: 92), (x: 150, y: 92)], weight: 4)
        let boxes = LabelPlacement.place([
            .init(anchor: .horizontal(y: 100), width: 60, height: 12),
        ], in: bounds, ink: ink)
        #expect(boxes[0] == Box(minX: 4, minY: 102, width: 60, height: 12))
    }

    @Test("점 글씨는 아무것도 없으면 바로 위 가운데")
    func pointDefaultsAbove() {
        let boxes = LabelPlacement.place([
            .init(anchor: .point(x: 150, y: 100), width: 40, height: 10),
        ], in: bounds, ink: [])
        #expect(boxes[0] == Box(minX: 130, minY: 84, width: 40, height: 10))
    }

    @Test("위가 그림 끝이면 점을 덮지 않는 옆으로")
    func pointNearTopGoesBeside() {
        let boxes = LabelPlacement.place([
            .init(anchor: .point(x: 150, y: 8), width: 40, height: 10),
        ], in: bounds, ink: LabelPlacement.marker(x: 150, y: 8))
        #expect(boxes[0] == Box(minX: 156, minY: 3, width: 40, height: 10))
    }

    @Test("놓을 곳이 없으면 덜 중요한(뒤의) 글씨를 뺀다")
    func dropsWhenFull() {
        let small = Box(minX: 0, minY: 0, width: 100, height: 20)
        let boxes = LabelPlacement.place([
            .init(anchor: .point(x: 50, y: 10), width: 90, height: 12),
            .init(anchor: .point(x: 50, y: 10), width: 90, height: 12),
        ], in: small, ink: [])
        #expect(boxes[0] == Box(minX: 5, minY: 0, width: 90, height: 12))
        #expect(boxes[1] == nil)
    }

    @Test("이벤트가 아무리 붙어 있어도 놓인 글씨끼리는 안 겹치고 그림 밖으로 안 나간다")
    func crowdedEventsNeverOverlap() {
        let requests = (0..<12).map { index in
            LabelPlacement.Request(anchor: .verticalBottom(x: 20 + Double(index) * 7, lanes: 5), width: 70, height: 12)
        }
        let placed = LabelPlacement.place(requests, in: bounds, ink: []).compactMap { $0 }
        #expect(placed.count == 6)
        for (index, box) in placed.enumerated() {
            #expect(box.minX >= bounds.minX && box.maxX <= bounds.maxX)
            #expect(box.minY >= bounds.minY && box.maxY <= bounds.maxY)
            for other in placed[(index + 1)...] {
                #expect(!box.overlaps(other, gap: LabelPlacement.gap))
            }
        }
    }

    @Test("선은 3포인트마다 점으로 끊고 끝점을 더한다 · 망가진 좌표는 건너뛴다")
    func traceSamples() {
        #expect(LabelPlacement.trace([(x: 0, y: 0), (x: 30, y: 0)], weight: 1).count == 11)
        #expect(LabelPlacement.trace([(x: 0, y: 0), (x: .nan, y: 0)], weight: 1).isEmpty)
        #expect(LabelPlacement.marker(x: .infinity, y: 0).isEmpty)
    }

    @Test("그림보다 큰 글씨는 놓지 않는다")
    func tooLargeIsDropped() {
        let boxes = LabelPlacement.place([
            .init(anchor: .point(x: 10, y: 10), width: 400, height: 12),
        ], in: bounds, ink: [])
        #expect(boxes[0] == nil)
    }
}
