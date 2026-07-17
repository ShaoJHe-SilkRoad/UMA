import AppKit
import SwiftUI

struct CodexConnectionBridgeView: View {
    let presentation: CodexConnectionPresentation
    let language: AppLanguage
    let perform: @MainActor (CodexConnectionAction) async -> Void

    @State private var showsTechnicalDetail = false
    @FocusState private var focusedAction: CodexConnectionAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(UsageDesign.blue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title)
                        .font(UsageDesign.font(20, weight: .bold, language: language))
                    if presentation.showsProgress {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(presentation.accessibilityAnnouncement)
                    }
                }
            }

            Text(presentation.body)
                .font(UsageDesign.font(13, language: language))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = presentation.technicalDetail {
                DisclosureGroup(language.connectionTechnicalDetail, isExpanded: $showsTechnicalDetail) {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.disabled)
                }
                .accessibilityLabel(language.connectionTechnicalDetail)
            }

            HStack(spacing: 10) {
                if let tertiary = visibleAction(presentation.tertiaryAction) {
                    actionButton(tertiary, primary: false)
                }
                if let secondary = visibleAction(presentation.secondaryAction) {
                    actionButton(secondary, primary: false)
                }
                Spacer(minLength: 0)
                if let primary = visibleAction(presentation.primaryAction) {
                    actionButton(primary, primary: true)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GlassCardBackground(tuning: .final))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityAnnouncement)
        .onAppear {
            focusedAction = visibleAction(presentation.primaryAction)?.action
            postCodexAccessibilityAnnouncement(presentation.accessibilityAnnouncement)
        }
        .onChange(of: presentation.title) { _, _ in
            showsTechnicalDetail = false
            focusedAction = visibleAction(presentation.primaryAction)?.action
            postCodexAccessibilityAnnouncement(presentation.accessibilityAnnouncement)
        }
    }

    @ViewBuilder
    private func actionButton(_ item: CodexPresentedAction, primary: Bool) -> some View {
        Button(item.title) {
            Task { @MainActor in await perform(item.action) }
        }
        .buttonStyle(.bordered)
        .tint(primary ? UsageDesign.blue : .gray)
        .fontWeight(primary ? .semibold : .regular)
        .focused($focusedAction, equals: item.action)
        .accessibilityLabel(item.title)
    }

    private func visibleAction(_ action: CodexPresentedAction?) -> CodexPresentedAction? {
        guard let action else { return nil }
        switch action.action {
        case .openCodex, .updateCodex:
            return nil
        default:
            return action
        }
    }

    private var symbolName: String {
        if presentation.showsProgress { return "arrow.triangle.2.circlepath" }
        if presentation.technicalDetail != nil { return "exclamationmark.triangle" }
        return "link.circle"
    }
}

@MainActor
private func postCodexAccessibilityAnnouncement(_ message: String) {
    NSAccessibility.post(
        element: NSApplication.shared,
        notification: .announcementRequested,
        userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ]
    )
}
