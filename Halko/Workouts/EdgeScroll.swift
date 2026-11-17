import SwiftUI
import UIKit

// A page that scrolls on its own while something dragged on it is held near its top or bottom, faster closer to the
// edge. What is held stays under the finger: `drift`, how far the page went since the finger last moved, is added to
// where the finger was then. It moves the scroll view of the page itself, whose offset and insets are those it shows.
@Observable
final class EdgeScroll {
    private static let edge: CGFloat = 70
    // Each step, about a frame.
    private static let fastest: CGFloat = 14

    private(set) var isHolding = false
    // How far the page scrolled since the finger last moved.
    private(set) var drift: CGFloat = 0
    // The finger in the stack of what is dragged, as it last moved.
    @ObservationIgnored private var finger: CGFloat = 0
    // Where the page was scrolled then.
    @ObservationIgnored private var heldOffset: CGFloat = 0
    // Inside the stack of what is dragged, to find where it is in the page.
    @ObservationIgnored private weak var marker: UIView?

    // The finger moved, at `y` in the stack of what is dragged.
    func hold(at y: CGFloat) {
        finger = y
        heldOffset = scrollView?.contentOffset.y ?? 0
        if drift != 0 {
            drift = 0
        }
        if !isHolding {
            isHolding = true
        }
    }

    func release() {
        isHolding = false
        drift = 0
    }

    // While held near the top or the bottom of the page shown, scrolls it a step, short of its ends.
    fileprivate func step() {
        guard isHolding, let marker, let scrollView = scrollView else { return }
        let offset = scrollView.contentOffset.y
        let insets = scrollView.adjustedContentInset
        let y = marker.convert(CGPoint.zero, to: scrollView).y + finger + drift
        let top = offset + insets.top + Self.edge
        let bottom = offset + scrollView.bounds.height - insets.bottom - Self.edge
        let past = y < top ? y - top : y > bottom ? y - bottom : 0
        guard past != 0 else { return }
        let lowest = -insets.top
        let highest = max(lowest, scrollView.contentSize.height - scrollView.bounds.height + insets.bottom)
        let next = min(max(offset + min(max(past / Self.edge, -1), 1) * Self.fastest, lowest), highest)
        guard next != offset else { return }
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: next), animated: false)
        drift = next - heldOffset
    }

    fileprivate func attach(_ marker: UIView) {
        self.marker = marker
    }

    // The nearest one around the stack.
    private var scrollView: UIScrollView? {
        var view = marker?.superview
        while let current = view, !(current is UIScrollView) {
            view = current.superview
        }
        return view as? UIScrollView
    }
}

extension View {
    // Put on the stack of what is dragged, in the scroll view of the page: where the finger is measured.
    func edgeScroll(_ scroll: EdgeScroll) -> some View {
        modifier(EdgeScrollSpace(scroll: scroll))
    }
}

private struct EdgeScrollSpace: ViewModifier {
    let scroll: EdgeScroll

    func body(content: Content) -> some View {
        content
            .background {
                EdgeMarker(scroll: scroll)
                    .accessibilityHidden(true)
            }
            // Each frame while something is held.
            .task(id: scroll.isHolding) {
                guard scroll.isHolding else { return }
                while !Task.isCancelled {
                    scroll.step()
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
    }
}

// An empty view behind the stack, inside the scroll view of the page: finds it, and where the stack is in it.
private struct EdgeMarker: UIViewRepresentable {
    let scroll: EdgeScroll

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        scroll.attach(view)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
