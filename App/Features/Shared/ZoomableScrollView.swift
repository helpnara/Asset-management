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
        if size != scroll.naturalSize {
            scroll.naturalSize = size
            hosting.view.frame = CGRect(origin: .zero, size: size)
            scroll.setNeedsLayout()
        }
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
    var naturalSize: CGSize = .zero
    private var lastBoundsWidth: CGFloat = 0
    private let inset: CGFloat = 12

    override func layoutSubviews() {
        super.layoutSubviews()
        guard naturalSize.width > 0, bounds.width > 0 else { return }
        if bounds.width != lastBoundsWidth {
            // 화면 폭이 바뀌었다(처음 · 회전). 폭 맞춤을 다시 잡고 거기서 시작한다.
            lastBoundsWidth = bounds.width
            let fit = max(0.05, (bounds.width - inset * 2) / naturalSize.width)
            minimumZoomScale = fit
            maximumZoomScale = fit * 4
            zoomScale = fit
            contentOffset = CGPoint(x: -inset, y: -inset)
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
