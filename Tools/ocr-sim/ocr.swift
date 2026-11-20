// Apple Vision 으로 캡처를 읽는다 — iPhone 의 글자 인식과 같은 엔진 (docs/25 J3 시뮬레이션).
// 기기 안에서만 돈다: 네트워크를 쓰지 않는다. macOS 러너에서:
//   swift Tools/ocr-sim/ocr.swift Tools/ocr-sim/shots/*.png
// 한 관측마다 한 줄 — `OCR<TAB>{json}`. 언어 보정을 켠 것(fix=1)과 끈 것(fix=0)을 둘 다 찍는다.
import Foundation
import ImageIO
import Vision

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("SKIP\t\(path)"); continue
    }
    for fix in [true, false] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.usesLanguageCorrection = fix
        let started = Date()
        try VNImageRequestHandler(cgImage: image).perform([request])
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        for observation in request.results ?? [] {
            guard let top = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox
            let row: [String: Any] = [
                "file": url.deletingPathExtension().lastPathComponent, "fix": fix ? 1 : 0,
                "text": top.string, "conf": Double(top.confidence),
                "x": Double(box.minX), "y": Double(box.minY), "w": Double(box.width), "h": Double(box.height),
            ]
            let data = try JSONSerialization.data(withJSONObject: row)
            print("OCR\t" + String(decoding: data, as: UTF8.self))
        }
        print("TIME\t\(url.lastPathComponent)\tfix=\(fix ? 1 : 0)\t\(ms) ms")
    }
}
