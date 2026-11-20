// Apple Vision 으로 캡처를 읽는다 — iPhone 의 글자 인식과 같은 엔진 (docs/25 J3 시뮬레이션).
// 기기 안에서만 돈다: 네트워크를 쓰지 않는다. macOS 러너에서:
//   swift Tools/ocr-sim/ocr.swift Tools/ocr-sim/shots/*.png
// 한 관측마다 한 줄 — `OCR<TAB>{json}`. 언어 보정을 켠 것(fix=1)과 끈 것(fix=0)을 둘 다 찍는다.
// 러너(가상 머신)에는 뉴럴 엔진이 없어 정밀 인식이 `CRImageReaderError` 를 낼 수 있다 —
// CPU 로만, 그래도 안 되면 빠른 인식으로 내려가며, 어느 쪽으로 읽었는지 `mode` 에 남긴다.
import Foundation
import ImageIO
import Vision

func recognize(_ image: CGImage, fix: Bool, accurate: Bool, cpuOnly: Bool) throws -> [VNRecognizedTextObservation] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = accurate ? .accurate : .fast
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.usesLanguageCorrection = fix
    if cpuOnly { request.usesCPUOnly = true }
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    return request.results ?? []
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("SKIP\t\(path)"); continue
    }
    for fix in [true, false] {
        var results: [VNRecognizedTextObservation] = []
        var mode = ""
        let started = Date()
        for (accurate, cpu, name) in [(true, false, "accurate"), (true, true, "accurate-cpu"), (false, true, "fast-cpu")] {
            do {
                results = try recognize(image, fix: fix, accurate: accurate, cpuOnly: cpu)
                mode = name; break
            } catch {
                print("FAIL\t\(url.lastPathComponent)\tfix=\(fix ? 1 : 0)\t\(name)\t\(error)")
            }
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        for observation in results {
            guard let top = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox
            let row: [String: Any] = [
                "file": url.deletingPathExtension().lastPathComponent, "fix": fix ? 1 : 0, "mode": mode,
                "text": top.string, "conf": Double(top.confidence),
                "x": Double(box.minX), "y": Double(box.minY), "w": Double(box.width), "h": Double(box.height),
            ]
            let data = try JSONSerialization.data(withJSONObject: row)
            print("OCR\t" + String(decoding: data, as: UTF8.self))
        }
        print("TIME\t\(url.lastPathComponent)\tfix=\(fix ? 1 : 0)\t\(mode)\t\(ms) ms\t\(results.count) 줄")
    }
}
