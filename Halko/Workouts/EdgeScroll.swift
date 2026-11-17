import SwiftUI

// A page that scrolls on its own while something dragged on it is held near its top or bottom, faster closer to the
// edge. What is held stays under the finger: `drift`, how far the page went since the finger last moved, is added to
// where the finger was then.
@Observable
final class EdgeScroll {
    private static let edge: CGFloat = 70
    // Each step, about a frame.
    private static let fastest: CGFloat = 14

    private(set) var isHolding = false
    // How far the page scrolled since the finger last moved.
    private(set) var drift: CGFloat = 0
    // The finger on the screen, as it last moved.
    @ObservationIgnored private var finger: CGFloat = 0
    // Where the page was scrolled then.
    @ObservationIgnored private var heldOffset: CGFloat = 0
    // On the screen: the top of the stack of what is dragged, and the frame of the scroll view.
    @ObservationIgnored private var spaceTop: CGFloat = 0
    @ObservationIgnored private var viewTop: CGFloat = 0
    @ObservationIgnored private var geometry: ScrollGeometry?

    // The finger moved, at `y` in the stack of what is dragged.
    func hold(at y: CGFloat) {
        finger = spaceTop + y
        heldOffset = geometry?.contentOffset.y ?? 0
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

    // Where to scroll the page while held near its top or bottom; nil if not, or at its end.
    func step() -> CGFloat? {
        guard isHolding, let geometry else { return nil }
        let top = viewTop + geometry.contentInsets.top + Self.edge
        let bottom = viewTop + geometry.containerSize.height - geometry.contentInsets.bottom - Self.edge
        let past = finger < top ? finger - top : finger > bottom ? finger - bottom : 0
        guard past != 0 else { return nil }
        let step = min(max(past / Self.edge, -1), 1) * Self.fastest
        let lowest = -geometry.contentInsets.top
        let highest = max(lowest, geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom)
        let offset = min(max(geometry.contentOffset.y + step, lowest), highest)
        return offset == geometry.contentOffset.y ? nil : offset
    }

    fileprivate func scrolled(_ geometry: ScrollGeometry) {
        self.geometry = geometry
        if isHolding {
            drift = geometry.contentOffset.y - heldOffset
        }
    }

    fileprivate func measure(viewTop: CGFloat) {
        self.viewTop = viewTop
    }

    fileprivate func measure(spaceTop: CGFloat) {
        self.spaceTop = spaceTop
    }
}

extension View {
    // Put on the scroll view of the page.
    func edgeScroll(_ scroll: EdgeScroll) -> some View {
        modifier(EdgeScrollView(scroll: scroll))
    }

    // Put on the stack of what is dragged, where the finger is measured.
    func edgeScrollSpace(_ scroll: EdgeScroll) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
            scroll.measure(spaceTop: top)
        }
    }
}

private struct EdgeScrollView: ViewModifier {
    let scroll: EdgeScroll
    @State private var position = ScrollPosition(idType: String.self)

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in
                scroll.scrolled(geometry)
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                scroll.measure(viewTop: top)
            }
            // Each frame while something is held.
            .task(id: scroll.isHolding) {
                guard scroll.isHolding else { return }
                while !Task.isCancelled {
                    if let offset = scroll.step() {
                        position.scrollTo(y: offset)
                    }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
    }
}
