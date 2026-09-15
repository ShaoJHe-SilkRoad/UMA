import SwiftUI

@MainActor public final class ThreadOSSchemeBLayoutProbe: ObservableObject {
    @Published public private(set) var frames: [String: CGRect] = [:]

    public init() {}

    func record(_ frame: CGRect, for identifier: String) {
        guard frame.width > 0, frame.height > 0 else { return }
        frames[identifier] = frame
    }
}

struct ThreadOSSchemeBGeometryReporter: View {
    let identifier: String
    let probe: ThreadOSSchemeBLayoutProbe?

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { record(geometry.frame(in: .named("uma.threados.scheme-b"))) }
                .onChange(of: geometry.frame(in: .named("uma.threados.scheme-b"))) { _, frame in record(frame) }
        }
        .allowsHitTesting(false)
    }

    private func record(_ frame: CGRect) {
        guard let probe else { return }
        probe.record(frame, for: identifier)
    }
}

/// Shared Scheme B containers keep the card hierarchy visually consistent while
/// leaving settings bindings in the settings surface that owns their semantics.
struct ThreadOSSchemeBCard<Content: View>: View {
    let identifier: String?
    let layoutProbe: ThreadOSSchemeBLayoutProbe?
    @ViewBuilder let content: Content

    init(identifier: String? = nil, layoutProbe: ThreadOSSchemeBLayoutProbe? = nil, @ViewBuilder content: () -> Content) {
        self.identifier = identifier
        self.layoutProbe = layoutProbe
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.quaternary, lineWidth: 1))
            .overlay {
                if let identifier { ThreadOSSchemeBGeometryReporter(identifier: identifier, probe: layoutProbe) }
            }
    }
}

struct ThreadOSSchemeBChildPanel<Content: View>: View {
    let identifier: String?
    let layoutProbe: ThreadOSSchemeBLayoutProbe?
    @ViewBuilder let content: Content

    init(identifier: String? = nil, layoutProbe: ThreadOSSchemeBLayoutProbe? = nil, @ViewBuilder content: () -> Content) {
        self.identifier = identifier
        self.layoutProbe = layoutProbe
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.purple.opacity(0.075), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if let identifier { ThreadOSSchemeBGeometryReporter(identifier: identifier, probe: layoutProbe) }
            }
    }
}

struct WorkerGroupsLayout: Layout {
    private static let breakpoint: CGFloat = 960
    private static let spacing: CGFloat = 12
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        guard width >= Self.breakpoint, subviews.count == 2 else {
            let sizes = subviews.map { $0.sizeThatFits(.init(width: width, height: nil)) }
            return .init(width: width, height: sizes.map(\.height).reduce(0, +) + (sizes.count > 1 ? Self.spacing : 0))
        }
        let panelWidth = (width - Self.spacing) / 2
        return .init(width: width, height: subviews.map { $0.sizeThatFits(.init(width: panelWidth, height: nil)).height }.max() ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard bounds.width >= Self.breakpoint, subviews.count == 2 else {
            var y = bounds.minY
            for subview in subviews { let size = subview.sizeThatFits(.init(width: bounds.width, height: nil)); subview.place(at: .init(x: bounds.minX, y: y), anchor: .topLeading, proposal: .init(width: bounds.width, height: size.height)); y += size.height + Self.spacing }
            return
        }
        let width = (bounds.width - Self.spacing) / 2
        for (index, subview) in subviews.enumerated() { subview.place(at: .init(x: bounds.minX + CGFloat(index) * (width + Self.spacing), y: bounds.minY), anchor: .topLeading, proposal: .init(width: width, height: bounds.height)) }
    }
}

/// Role-card columns are selected from the actual proposed content width.
/// This prevents intrinsic picker widths from turning a narrow layout into 4+1.
struct RoleGridLayout: Layout {
    private let spacing: CGFloat = 8
    private func columns(_ width: CGFloat) -> Int { width >= 932 ? 5 : width >= 556 ? 3 : 2 }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0; let count = columns(width)
        let cell = max(0, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
        var heights = Array(repeating: CGFloat.zero, count: Int(ceil(Double(subviews.count) / Double(count))))
        for (index, view) in subviews.enumerated() { heights[index / count] = max(heights[index / count], view.sizeThatFits(.init(width: cell, height: nil)).height) }
        return .init(width: width, height: heights.reduce(0, +) + CGFloat(max(0, heights.count - 1)) * spacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let count = columns(bounds.width); let cell = (bounds.width - CGFloat(count - 1) * spacing) / CGFloat(count)
        var rowY = bounds.minY; var rowHeight: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            if index > 0 && index % count == 0 { rowY += rowHeight + spacing; rowHeight = 0 }
            let size = view.sizeThatFits(.init(width: cell, height: nil)); rowHeight = max(rowHeight, size.height)
            view.place(at: .init(x: bounds.minX + CGFloat(index % count) * (cell + spacing), y: rowY), anchor: .topLeading, proposal: .init(width: cell, height: size.height))
        }
    }
}
