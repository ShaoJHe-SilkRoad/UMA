import Foundation

/// Keeps recovery controls reachable when verified values remain visible after
/// a later connection or refresh problem. The model contains only existing
/// sanitized presentation copy and typed actions.
struct RetainedSnapshotRecoveryPresentation: Equatable {
    let statusText: String
    let primaryAction: CodexPresentedAction?
    let secondaryAction: CodexPresentedAction?

    init?(
        presentation: CodexConnectionPresentation,
        language: AppLanguage
    ) {
        guard presentation.showsRealData && (
              presentation.showsProgress
                || presentation.freshnessText != nil
                || presentation.technicalDetail != nil
                || presentation.primaryAction != nil
                || presentation.secondaryAction != nil
                || presentation.tertiaryAction != nil
              )
        else { return nil }

        var parts = [presentation.freshnessText ?? presentation.title, presentation.body]
        if let technicalDetail = presentation.technicalDetail {
            parts.append("\(language.connectionTechnicalDetail): \(technicalDetail)")
        }
        statusText = parts.joined(separator: " · ")
        primaryAction = presentation.primaryAction
        secondaryAction = presentation.secondaryAction ?? presentation.tertiaryAction
    }
}
