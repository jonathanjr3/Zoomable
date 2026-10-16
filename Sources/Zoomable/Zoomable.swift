//
//  Zoomable.swift
//
//
//  Created by Ceylo on 11/12/2021.
//

import SwiftUI
import UIKit

public enum ZoomLevel: Sendable {
    case fit
    case fill
    /// minimum between `fill` and `scaledFit(scale: maxScaledFit)`.
    case boundedFill(maxScaledFit: Float)
    /// `scale` x `fit`.
    case scaledFit(scale: Float)
}

/// Displays any SwiftUI content in a zoomable, scrollable container.
///
/// The content must have an intrinsic size (e.g. a non-resizable `Image`).
/// Double tap toggles between the primary and secondary zoom levels, zooming
/// towards the tapped point. Rotating the device resets the zoom.
public struct Zoomable<Content: View>: UIViewControllerRepresentable {
    private let content: Content
    private var initialZoomLevel: ZoomLevel = .fit
    private var primaryZoomLevel: ZoomLevel = .fit
    private var secondaryZoomLevel: ZoomLevel = .scaledFit(scale: 2)
    private var maximumZoomScale: CGFloat = 10
    private var showsIndicators = true
    private var isDisabled = false
    private var isZoomed: Binding<Bool>?

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public func initialZoomLevel(_ zoomLevel: ZoomLevel) -> Self {
        var copy = self
        copy.initialZoomLevel = zoomLevel
        return copy
    }

    public func primaryZoomLevel(_ zoomLevel: ZoomLevel) -> Self {
        var copy = self
        copy.primaryZoomLevel = zoomLevel
        return copy
    }

    public func secondaryZoomLevel(_ zoomLevel: ZoomLevel) -> Self {
        var copy = self
        copy.secondaryZoomLevel = zoomLevel
        return copy
    }

    /// The maximum scale of the content, relative to its original size. Defaults to 10.
    public func maximumZoomScale(_ scale: CGFloat) -> Self {
        var copy = self
        copy.maximumZoomScale = scale
        return copy
    }

    /// Shows or hides the scroll indicators. Defaults to `true`.
    public func scrollIndicators(_ visible: Bool) -> Self {
        var copy = self
        copy.showsIndicators = visible
        return copy
    }

    /// Temporarily disables pinch, double tap and scrolling, e.g. while a
    /// navigation swipe or transition is running.
    public func zoomDisabled(_ isDisabled: Bool) -> Self {
        var copy = self
        copy.isDisabled = isDisabled
        return copy
    }

    /// Reports whether the content is currently zoomed in beyond the primary zoom level.
    public func isZoomed(_ binding: Binding<Bool>) -> Self {
        var copy = self
        copy.isZoomed = binding
        return copy
    }

    public func makeUIViewController(context: Context) -> ZoomableViewController {
        ZoomableViewController(
            rootView: AnyView(content),
            initialZoomLevel: initialZoomLevel,
            primaryZoomLevel: primaryZoomLevel,
            secondaryZoomLevel: secondaryZoomLevel
        )
    }

    public func updateUIViewController(_ viewController: ZoomableViewController, context: Context) {
        viewController.hostingController.rootView = AnyView(content)
        viewController.scrollView.maximumZoomScale = maximumZoomScale
        viewController.scrollView.showsHorizontalScrollIndicator = showsIndicators
        viewController.scrollView.showsVerticalScrollIndicator = showsIndicators
        viewController.isInteractionEnabled = !isDisabled
        viewController.onZoomedChange = { [isZoomed] zoomed in
            if isZoomed?.wrappedValue != zoomed {
                isZoomed?.wrappedValue = zoomed
            }
        }
    }
}

public final class ZoomableViewController: UIViewController, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    let hostingController: UIHostingController<AnyView>
    private var contentView: UIView { hostingController.view }
    private let originalContentSize: CGSize
    private let initialZoomLevel: ZoomLevel
    private let primaryZoomLevel: ZoomLevel
    private let secondaryZoomLevel: ZoomLevel
    private var lastBoundsSize: CGSize = .zero
    private let doubleTapRecognizer = UITapGestureRecognizer()

    var onZoomedChange: ((Bool) -> Void)?

    var isInteractionEnabled = true {
        didSet {
            scrollView.isScrollEnabled = isInteractionEnabled
            scrollView.pinchGestureRecognizer?.isEnabled = isInteractionEnabled
            doubleTapRecognizer.isEnabled = isInteractionEnabled
        }
    }

    init(
        rootView: AnyView,
        initialZoomLevel: ZoomLevel,
        primaryZoomLevel: ZoomLevel,
        secondaryZoomLevel: ZoomLevel
    ) {
        // Type-erased so the view controller itself doesn't need to be generic.
        let erased = UIHostingController(rootView: rootView)
        erased.sizingOptions = .intrinsicContentSize
        self.hostingController = erased
        self.originalContentSize = erased.view.intrinsicContentSize
        self.initialZoomLevel = initialZoomLevel
        self.primaryZoomLevel = primaryZoomLevel
        self.secondaryZoomLevel = secondaryZoomLevel
        scrollView.maximumZoomScale = 10
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self

        doubleTapRecognizer.addTarget(self, action: #selector(doubleTap))
        doubleTapRecognizer.numberOfTapsRequired = 2
        doubleTapRecognizer.numberOfTouchesRequired = 1
        scrollView.addGestureRecognizer(doubleTapRecognizer)

        addChild(hostingController)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        view.addSubview(scrollView)
        hostingController.didMove(toParent: self)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The first layout and any later size change (e.g. rotation) restart from
        // the initial zoom level, since the previous zoom/offset no longer makes sense.
        if scrollView.bounds.size != lastBoundsSize, scrollView.bounds.size != .zero {
            lastBoundsSize = scrollView.bounds.size
            resetZoom()
        }
        centerSmallContents()
    }

    private func resetZoom() {
        guard originalContentSize.width > 0, originalContentSize.height > 0 else { return }
        scrollView.minimumZoomScale = zoomToFit(size: originalContentSize)
        scrollView.zoomScale = 1
        scrollView.contentSize = originalContentSize
        scrollView.zoomScale = max(scrollView.minimumZoomScale, initialScale)
        centerSmallContents()
        scrollView.contentOffset = CGPoint(
            x: -scrollView.contentInset.left,
            y: -scrollView.contentInset.top
        )
        notifyZoomChange()
    }

    private func centerSmallContents() {
        let contentSize = contentView.frame.size
        let offsetX = max((scrollView.bounds.width - contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
    }

    private func notifyZoomChange() {
        let zoomed = scrollView.zoomScale > primaryScale + 1e-3
        onZoomedChange?(zoomed)
    }

    // MARK: UIScrollViewDelegate
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }

    public func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerSmallContents()
        notifyZoomChange()
    }

    // MARK: - Zoom levels
    private func zoomToFit(size: CGSize) -> CGFloat {
        let widthRatio = scrollView.bounds.width / size.width
        let heightRatio = scrollView.bounds.height / size.height
        return min(widthRatio, heightRatio)
    }

    private func zoomToFill(size: CGSize) -> CGFloat {
        let widthRatio = scrollView.bounds.width / size.width
        let heightRatio = scrollView.bounds.height / size.height
        return max(widthRatio, heightRatio)
    }

    private func scale(for zoomLevel: ZoomLevel) -> CGFloat {
        switch zoomLevel {
        case .fit:
            zoomToFit(size: originalContentSize)
        case .fill:
            zoomToFill(size: originalContentSize)
        case let .boundedFill(maxScaledFit):
            min(CGFloat(maxScaledFit) * zoomToFit(size: originalContentSize), zoomToFill(size: originalContentSize))
        case let .scaledFit(scale):
            CGFloat(scale) * zoomToFit(size: originalContentSize)
        }
    }

    private var initialScale: CGFloat { scale(for: initialZoomLevel) }
    private var primaryScale: CGFloat { scale(for: primaryZoomLevel) }
    private var secondaryScale: CGFloat { scale(for: secondaryZoomLevel) }

    @objc private func doubleTap(_ recognizer: UITapGestureRecognizer) {
        let currentScale = scrollView.zoomScale
        let inPrimaryScale = abs(currentScale - primaryScale) < 1e-3
        let newScale = min(
            max(scrollView.minimumZoomScale, inPrimaryScale ? secondaryScale : primaryScale),
            scrollView.maximumZoomScale
        )
        guard abs(currentScale - newScale) > 1e-3 else { return }

        // Zoom towards the tapped point: show a rect centered on it that, at
        // `newScale`, exactly fills the scroll view.
        let tapPoint = recognizer.location(in: contentView)
        let visibleSize = CGSize(
            width: scrollView.bounds.width / newScale,
            height: scrollView.bounds.height / newScale
        )
        let rect = CGRect(
            x: tapPoint.x - visibleSize.width / 2,
            y: tapPoint.y - visibleSize.height / 2,
            width: visibleSize.width,
            height: visibleSize.height
        )
        scrollView.zoom(to: rect, animated: true)
    }
}
