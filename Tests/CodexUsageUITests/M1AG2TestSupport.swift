import Foundation
@testable import CodexUsageUI

@MainActor
extension UsageStore {
    convenience init(
        autoRefresh: Bool = true,
        previewOnly: Bool = false,
        language: AppLanguage? = nil,
        client: any CodexUsageClient,
        localActivityReader: any CodexLocalActivityReading,
        consentDefaults: UserDefaults? = nil,
        periodicRefreshInterval: Duration = .seconds(240)
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
            periodicRefreshInterval: periodicRefreshInterval
        )
    }
}
