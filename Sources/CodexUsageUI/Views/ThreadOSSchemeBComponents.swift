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
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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
