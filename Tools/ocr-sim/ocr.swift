// Apple Vision 으로 캡처를 읽는다 — iPhone 의 글자 인식과 같은 엔진 (docs/25 J3 시뮬레이션).
// 기기 안에서만 돈다: 네트워크를 쓰지 않는다. macOS 러너에서:
//   swift Tools/ocr-sim/ocr.swift Tools/ocr-sim/shots/*.png
// 한 관측마다 한 줄 — `OCR<TAB>{json}`. 언어 보정을 켠 것(fix=1)과 끈 것(fix=0)을 둘 다 찍는다.
// GitHub 러너는 가상 머신이라 정밀 인식이 `CRImageReaderError.unknownError` 를 낸다
// (`AppleM2ScalerParavirtDriver` 가 없다 — 11-20 탐침 6). 그림을 미리 줄여 넘기는 길 ·
// 새 Swift API(`RecognizeTextRequest`) 를 차례로 시도하고, 끝내 안 되면 빠른 인식으로 — `mode` 에 남긴다.
import CoreGraphics
import Foundation
import ImageIO
import Vision

func scaled(_ image: CGImage, _ factor: Double) -> CGImage? {
    let w = Int(Double(image.width) * factor), h = Int(Double(image.height) * factor)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()
}

struct Line { let text: String; let conf: Double; let box: CGRect }

func legacy(_ image: CGImage, fix: Bool, accurate: Bool) throws -> [Line] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = accurate ? .accurate : .fast
    request.recognitionLanguages = ["ko-KR", "en-US"]
    request.usesLanguageCorrection = fix
    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
    return (request.results ?? []).compactMap { o in
        o.topCandidates(1).first.map { Line(text: $0.string, conf: Double($0.confidence), box: o.boundingBox) }
    }
}

func modern(_ image: CGImage, fix: Bool) async throws -> [Line] {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = [Locale.Language(identifier: "ko-KR"), Locale.Language(identifier: "en-US")]
    request.usesLanguageCorrection = fix
    let results = try await request.perform(on: image)
    return results.compactMap { o in
        o.topCandidates(1).first.map {
            let b = o.boundingBox
            return Line(text: $0.string, conf: Double($0.confidence),
                        box: CGRect(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height))
        }
    }
}

for path in CommandLine.arguments.dropFirst() {
    let url = URL(fileURLWithPath: path)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { print("SKIP\t\(path)"); continue }
    for fix in [true, false] {
        var lines: [Line] = []
        var mode = ""
        let started = Date()
        let attempts: [(String, () async throws -> [Line])] = [
            ("accurate", { try legacy(image, fix: fix, accurate: true) }),
            ("accurate-half", { guard let s = scaled(image, 0.5) else { return [] }; return try legacy(s, fix: fix, accurate: true) }),
            ("accurate-swiftapi", { try await modern(image, fix: fix) }),
            ("fast", { try legacy(image, fix: fix, accurate: false) }),
        ]
        for (name, run) in attempts {
            do { lines = try await run(); mode = name; break }
            catch { print("FAIL\t\(url.lastPathComponent)\tfix=\(fix ? 1 : 0)\t\(name)\t\(error)") }
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        for line in lines {
            let row: [String: Any] = [
                "file": url.deletingPathExtension().lastPathComponent, "fix": fix ? 1 : 0, "mode": mode,
                "text": line.text, "conf": line.conf,
                "x": Double(line.box.minX), "y": Double(line.box.minY), "w": Double(line.box.width), "h": Double(line.box.height),
            ]
            let data = try JSONSerialization.data(withJSONObject: row)
            print("OCR\t" + String(decoding: data, as: UTF8.self))
        }
        print("TIME\t\(url.lastPathComponent)\tfix=\(fix ? 1 : 0)\t\(mode)\t\(ms) ms\t\(lines.count) 줄")
    }
}
