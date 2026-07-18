import Foundation
@testable import CodexUsageUI

@MainActor
extension UsageStore {
    convenience init(
        autoRefresh: Bool = true,
        previewOnly: Bool = false,
        language: AppLanguage? = nil,
        client: any CodexUsageClient,
        localActivityReader: any CodexLocalActivityReading = CodexLocalActivityReader(),
        consentDefaults: UserDefaults? = nil,
        periodicRefreshInterval: Duration = .seconds(240),
        localSessionReconciliationInterval: Duration = .seconds(5),
        localSessionReconciliationTimeout: Duration = .seconds(300)
    ) {
        self.init(
            autoRefresh: autoRefresh,
            previewOnly: previewOnly,
            language: language,
            registry: AgentUsageRuntime.makeCodexRegistry(
                snapshotStore: nil,
                client: client,
                localActivityReader: localActivityReader
            ),
            primaryConnectorID: CodexUsageConnector.connectorID,
            consentDefaults: consentDefaults,
            visibleRefreshInterval: periodicRefreshInterval,
            // Preserve the pre-Task-B focused tests' visible-only cadence.
            // New Task-B coverage supplies an explicit short background
            // interval when it needs to prove the adaptive fallback.
            backgroundRefreshInterval: .seconds(900)
        )
        _ = localSessionReconciliationInterval
        _ = localSessionReconciliationTimeout
    }
}
