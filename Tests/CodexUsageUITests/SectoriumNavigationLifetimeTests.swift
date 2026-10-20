import Testing
@testable import CodexUsageUI
@testable import CodexUsageMonitor

#if DEBUG
@Suite("Sectorium navigation lifetime")
@MainActor
struct SectoriumNavigationLifetimeTests {
    @Test("Tab reentry retains the same registered-volume state without rebuilding its store")
    func retainsStoreAcrossReentry() {
        var creations = 0
        let lifetime = MainSectoriumStoreLifetime {
            creations += 1
            return HESectoriumStore.isolatedPreviewFixture()
        }
        #expect(creations == 0, "The main shell must not construct storage services before Sectorium is opened")

        var firstEntry: HESectoriumStore? = lifetime.resolve(injected: nil)
        weak var retainedEntry = firstEntry
        let registeredIDs = firstEntry!.volumeRows.map(\.id)
        firstEntry = nil

        #expect(retainedEntry != nil, "Removing the Sectorium tab must not release its session state")
        let nextEntry = lifetime.resolve(injected: nil)
        #expect(nextEntry === retainedEntry)
        #expect(nextEntry.volumeRows.map(\.id) == registeredIDs)
        #expect(creations == 1)
    }

    @Test("Explicit fixture injection never initializes the production fallback")
    func injectedStoreRemainsAuthoritative() {
        var fallbackCreations = 0
        let lifetime = MainSectoriumStoreLifetime {
            fallbackCreations += 1
            return HESectoriumStore.isolatedPreviewFixture()
        }
        let first = HESectoriumStore.isolatedPreviewFixture()
        let replacement = HESectoriumStore.isolatedPreviewFixture()

        #expect(lifetime.resolve(injected: first) === first)
        #expect(lifetime.resolve(injected: replacement) === replacement)
        #expect(fallbackCreations == 0)
    }
}
#endif
