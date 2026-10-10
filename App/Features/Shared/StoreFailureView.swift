import SwiftUI
import UIKit

/// **저장소를 끝내 못 열었을 때의 화면** (docs/18-stage5-foundation.md 5-4 · R3).
///
/// 예전에는 `fatalError` 로 죽었다. 켤 때마다 죽으니 사용자는 이유도 모르고,
/// 문의할 길도, 자료를 챙길 길도 없었다.
///
/// **이 화면은 저장소 · 관리 객체를 하나도 쓰지 않는다.** 저장소를 못 열어 여기 왔는데
/// 여기서 저장소를 찾다 죽으면 같은 자리로 돌아간다. 쓰는 것은 파일 경로(복사만)와
/// 번들 정보뿐이다. **지우기 · 초기화 · 다시 받아오기 단추는 없다** — 못 연 파일이
/// 고칠 수 있는 파일일 수 있고, 지우면 그 길이 닫힌다.
struct StoreFailureView: View {
    let reason: String

    /// 저장소 파일의 사본. 원본은 읽기만 한다.
    @State private var copies: [URL] = []
    @State private var didCopyReason = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.scaled(34))
                    .foregroundStyle(Color.loss)
                    .padding(.top, 24)

                Text("기록을 열지 못했습니다")
                    .font(.scaled(22, weight: .semibold))
                    .foregroundStyle(Color.ink)

                Text("앱이 이 기기의 저장소를 열지 못했습니다. **기록은 지우지 않았습니다** — 이 화면은 저장소 파일에 손대지 않습니다. iCloud 동기화를 쓰고 있었다면 기록은 iCloud 에도 있습니다.")
                    .font(.scaled(14))
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                step(1, "앱을 완전히 닫았다가 다시 열어 보세요. 앱 전환기에서 위로 쓸어 올리면 닫힙니다.")
                step(2, "업데이트가 있는지 보세요. 새 판이 이 문제를 고쳤을 수 있습니다.")
                if let url = AppUpdate.updateURL {
                    Link(destination: url) {
                        Label("업데이트 확인", systemImage: "arrow.down.circle")
                            .font(.scaled(14, weight: .medium))
                    }
                    .padding(.leading, 26)
                }
                step(3, "그래도 같으면 아래 메일로 알려 주세요. 자세한 이유가 메일에 함께 들어갑니다.")
                if let url = mailURL {
                    Link(destination: url) {
                        Label("문의 메일 보내기", systemImage: "envelope")
                            .font(.scaled(14, weight: .medium))
                    }
                    .padding(.leading, 26)
                }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("저장소 사본 보관하기")
                        .font(.scaled(15, weight: .semibold))
                        .foregroundStyle(Color.ink)
                    Text("지금 저장소 파일을 복사해 파일 앱 등에 한 부 보관해 두세요. 원본은 그대로 둡니다. 사본에는 기록 전체가 들어 있으니 아무에게나 보내지 마세요.")
                        .font(.scaled(12.5))
                        .foregroundStyle(Color.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if copies.isEmpty {
                        Text("복사할 저장소 파일이 없습니다.")
                            .font(.scaled(12.5))
                            .foregroundStyle(Color.faint)
                    } else {
                        ShareLink(items: copies) {
                            Label("사본 \(copies.count)개 내보내기", systemImage: "square.and.arrow.up")
                                .font(.scaled(14, weight: .medium))
                        }
                    }
                }

                DisclosureGroup("자세한 이유") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reason)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.muted)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(didCopyReason ? "복사했습니다" : "이유 복사") {
                            UIPasteboard.general.string = diagnostic
                            didCopyReason = true
                        }
                        .font(.scaled(13))
                    }
                    .padding(.top, 6)
                }
                .font(.scaled(13))
                .tint(Color.ink)

                Text(Self.versionText)
                    .font(.figure(11))
                    .foregroundStyle(Color.faint)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.surface.ignoresSafeArea())
        .task { copies = Self.copyStoreFiles() }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.figure(13, weight: .semibold))
                .foregroundStyle(Color.muted)
                .frame(width: 16, alignment: .trailing)
            Text(text)
                .font(.scaled(14))
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 메일과 복사에 넣는 글 — 판 · 기기 · 이유. 금액은 들어 있지 않다.
    private var diagnostic: String {
        "느린 부자 \(Self.versionText) · iOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
            + "저장소를 열지 못함\n\n" + reason
    }

    private var mailURL: URL? {
        guard SupportContact.isConfigured else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = SupportContact.email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "느린 부자 \(Self.versionText) 저장소를 열지 못함"),
            // 메일 앱이 받는 길이에 한계가 있다 — 이유는 앞부분만.
            URLQueryItem(name: "body", value: "\n\n— " + String(diagnostic.prefix(1500))),
        ]
        return components.url
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    /// 저장소 파일(개인 · 공유, 각각 `-wal` · `-shm` 까지)을 임시 폴더로 **복사**한다.
    /// SQLite 는 세 파일이 한 벌이라 하나만 가져가면 최근 기록이 빠진다.
    private static func copyStoreFiles() -> [URL] {
        let manager = FileManager.default
        let folder = URL.temporaryDirectory
            .appendingPathComponent("느린부자-저장소-사본-\(Int(Date.now.timeIntervalSince1970))")
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var result: [URL] = []
        for base in [Persistence.storeURL, Persistence.sharedStoreURL] {
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: base.path(percentEncoded: false) + suffix)
                guard manager.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
                let target = folder.appendingPathComponent(source.lastPathComponent)
                if (try? manager.copyItem(at: source, to: target)) != nil { result.append(target) }
            }
        }
        return result
    }
}
