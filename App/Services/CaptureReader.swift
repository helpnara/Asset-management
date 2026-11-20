import Core
import Foundation
import ImageIO
import Vision

/// **증권사 캡처의 글자를 기기 안에서 읽는다** (221 · 222번, docs/25). 캡처 읽기 시험과 점검의 `캡처로 채우기` 가 함께 쓴다.
///
/// - Vision 정밀 인식(사진 앱의 텍스트 인식과 같은 엔진) · 한국어 + 영어 · **기기 안에서만**(네트워크 없음, ADR-0005).
/// - 그림은 읽고 나면 버린다 — 돌려주는 것은 글자 줄(`CaptureParser.Line`, 값)뿐.
/// - GitHub 의 맥 러너(가상 머신)에서는 정밀 인식이 돌지 않는다(docs/25) — CI 는 이 길을 시험하지 못한다.
enum CaptureReader {
    enum ReadError: Error { case unreadable }

    /// 주 스레드 밖에서 돌고, 값만 돌려준다.
    nonisolated static func recognize(_ data: Data) async throws -> [CaptureParser.Line] {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ReadError.unreadable }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            return (request.results ?? []).compactMap { observation in
                guard let top = observation.topCandidates(1).first else { return nil }
                let box = observation.boundingBox   // 아래에서부터 — 위에서부터로 뒤집는다
                return CaptureParser.Line(text: top.string, x: Double(box.minX), top: Double(1 - box.maxY),
                                          width: Double(box.width), height: Double(box.height))
            }
        }.value
    }
}
