import SwiftUI
import UIKit

/// **UIKit 의 확대 스크롤** 을 SwiftUI 에 씌운 것 (139번).
///
/// SwiftUI 의 `MagnifyGesture` + `scaleEffect` 는 손가락을 움직일 때마다 뷰를
/// 다시 배치해서 뚝뚝 끊겼고, 손가락 사이가 아니라 왼쪽 위를 기준으로 커졌다.
/// `UIScrollView` 의 확대는 하드웨어가 하는 것이라 부드럽고, 손가락 사이를
/// 기준으로 커지며, 끝에서 튕긴다 — 사진 앱의 그 느낌이다.
///
/// 안에 넣는 내용은 **제 크기로 그려진다** (`sizeThatFits`). 폭 맞춤 배율이
/// 최소 확대이고 그 4배가 최대다. 두 번 두드리면 2.5배와 폭 맞춤을 오간다.
struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    let content: Content
    /// 안 내용의 폭. 폭 맞춤 배율 = (화면 폭 − 여백) ÷ 이 값.
    let contentWidth: CGFloat

    init(contentWidth: CGFloat, @ViewBuilder content: () -> Content) {
        self.contentWidth = contentWidth
        self.content = content()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ZoomingScrollView {
        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.safeAreaRegions = []
        context.coordinator.hosting = hosting

        let scroll = ZoomingScrollView()
        scroll.delegate = context.coordinator
        scroll.bouncesZoom = true
        scroll.alwaysBounceVertical = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        scroll.contentView = hosting.view
        scroll.addSubview(hosting.view)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }

    func updateUIView(_ scroll: ZoomingScrollView, context: Context) {
        guard let hosting = context.coordinator.hosting else { return }
        hosting.rootView = content
        let size = hosting.sizeThatFits(in: CGSize(width: contentWidth, height: .greatestFiniteMagnitude))
        // 크기만 알려 준다. 틀은 스크롤이 폭 맞춤을 다시 잡으며 스스로 놓는다 —
        // 확대된 뒤에 `frame` 을 바로 만지면 변환이 풀려 오른쪽 아래로 밀렸다 (142번).
        scroll.naturalSize = size
    }

    @MainActor
    final class Coordinator: NSObject, UIScrollViewDelegate {
        var hosting: UIHostingController<Content>?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { hosting?.view }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            (scrollView as? ZoomingScrollView)?.centerContent()
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scroll = recognizer.view as? ZoomingScrollView else { return }
            let fit = scroll.minimumZoomScale
            if scroll.zoomScale > fit * 1.05 {
                scroll.setZoomScale(fit, animated: true)
            } else {
                let target = fit * 2.5
                let point = recognizer.location(in: hosting?.view)
                let size = CGSize(width: scroll.bounds.width / target, height: scroll.bounds.height / target)
                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                  width: size.width, height: size.height)
                scroll.zoom(to: rect, animated: true)
            }
        }
    }
}

/// 폭 맞춤 배율을 스스로 정하고, 내용이 화면보다 좁으면 가운데 놓는 스크롤.
final class ZoomingScrollView: UIScrollView {
    var contentView: UIView?
    /// 내용의 제 크기. 바뀌면(처음 · 높이를 잰 뒤) 폭 맞춤을 다시 잡는다.
    var naturalSize: CGSize = .zero {
        didSet { if naturalSize != oldValue { needsFit = true; setNeedsLayout() } }
    }
    private var needsFit = true
    private var lastBoundsWidth: CGFloat = 0
    private let inset: CGFloat = 12

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let contentView, naturalSize.width > 0, bounds.width > 0 else { return }
        if bounds.width != lastBoundsWidth {
            // 화면 폭이 바뀌었다(처음 · 회전). 폭 맞춤을 다시 잡는다.
            lastBoundsWidth = bounds.width
            needsFit = true
        }
        if needsFit {
            needsFit = false
            let fit = max(0.05, (bounds.width - inset * 2) / naturalSize.width)
            minimumZoomScale = fit
            maximumZoomScale = fit * 4
            zoomScale = fit
            // 확대는 변환이라 `bounds` 가 제 크기, `frame` 이 보이는 크기다. 둘을 함께 놓는다.
            contentView.bounds = CGRect(origin: .zero, size: naturalSize)
            let shown = CGSize(width: naturalSize.width * fit, height: naturalSize.height * fit)
            contentView.frame = CGRect(origin: .zero, size: shown)
            contentSize = shown
            centerContent()
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
            return
        }
        centerContent()
    }

    /// 내용이 화면보다 좁으면 가운데, 세로는 위에서 시작. 여백은 인셋으로.
    func centerContent() {
        guard let contentView else { return }
        let width = contentView.frame.width
        let horizontal = max(inset, (bounds.width - width) / 2)
        contentInset = UIEdgeInsets(top: inset, left: horizontal, bottom: inset, right: horizontal)
    }
}
