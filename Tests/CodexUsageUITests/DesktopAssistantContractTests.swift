import Foundation
import Testing
@testable import CodexUsageMonitor
@testable import CodexUsageUI

@Suite("Desktop Assistant accepted contract")
struct DesktopAssistantContractTests {
    @Test("Regular and Minimalist geometry is exact")
    func geometry() {
        #expect(DesktopAssistantMetrics.regularWidth == 210)
        #expect(DesktopAssistantMetrics.regularHeight == 60)
        #expect(DesktopAssistantMetrics.minimalistWidth == 58.333333)
        #expect(DesktopAssistantMetrics.minimalistHeight == 30)
        #expect(DesktopAssistantMetrics.minimalistCornerRadius == 15)
    }

    @Test("Minimalist reserves no selected-window width")
    func minimalistContent() {
        #expect(
            DesktopAssistantContentContract.visibleFields(for: .minimalist)
                == [.providerConnectionMark, .percentage]
        )
        #expect(DesktopAssistantMetrics.minimalistReservedWindowWidth == 0)
        #expect(
            !DesktopAssistantContentContract.visibleFields(for: .minimalist)
                .contains(.selectedWindow)
        )
    }

    @Test("Regular keeps selected-window information visible")
    func regularContent() {
        #expect(
            DesktopAssistantContentContract.visibleFields(for: .regular)
                .contains(.selectedWindow)
        )
    }

    @Test("Percentage typography and compact gap stay fixed")
    func typography() {
        #expect(DesktopAssistantMetrics.percentageFontSize == 13)
        #expect(DesktopAssistantMetrics.minimalistGap == 3)
        #expect(DesktopAssistantMetrics.minimalistConnectionDiameter > DesktopAssistantMetrics.percentageFontSize)
    }

    @Test("Shared presentation remains the display and severity authority")
    func sharedPresentationAdapter() {
        let window = SharedUsageWindowPresentation(
            id: "codex.seven-day",
            kind: .sevenDay,
            compactLabel: "7D",
            accessibilityLabel: "seven-day window",
            remaining: .finite(44.4),
            resetsAt: nil,
            resetText: "Resets later"
        )
        let shared = SharedUsageCardPresentation(
            id: "codex",
            providerName: "Codex",
            planLabel: "PRO",
            connectionStatus: .connected,
            freshness: .fresh,
            windows: [window],
            selectedWindowID: window.id,
            remaining: .finite(44.4),
            severity: .critical
        )
        let card = DesktopAssistantCard(shared: shared)

        #expect(card.usageValue == .finite(44))
        #expect(card.tintFraction == 0.444)
        #expect(card.severity == .critical)
        #expect(card.connectionState == .connected)
        #expect(card.selectedWindowShortLabel == "7D")
        #expect(card.planLabel == "PRO")
        #expect(card.resetText == "Resets later")
    }

    @Test("Stale presentation never renders a healthy connection ring")
    func staleConnectionPresentation() {
        let shared = SharedUsageCardPresentation(
            id: "codex",
            providerName: "Codex",
            connectionStatus: .stale,
            freshness: .stale,
            windows: [],
            selectedWindowID: nil,
            remaining: .finite(44),
            severity: .normal,
            isRetainingLastValidValue: true
        )
        let card = DesktopAssistantCard(shared: shared)

        #expect(card.connectionState == .reconnecting)
        #expect(card.isStale)
        #expect(card.accessibilityLabel.contains("reconnecting"))
        #expect(card.accessibilityLabel.contains("stale"))
    }

    @Test("Tint midpoint uses the complete capsule width")
    func tintMidpoint() {
        let width = DesktopAssistantMetrics.minimalistWidth
        #expect(abs(DesktopAssistantTintGeometry.midpointX(remainingFraction: 0.75, width: width) - 43.74999975) < 0.000001)
        #expect(abs(DesktopAssistantTintGeometry.midpointX(remainingFraction: 0.50, width: width) - 29.1666665) < 0.000001)
        #expect(abs(DesktopAssistantTintGeometry.midpointX(remainingFraction: 0.10, width: width) - 5.8333333) < 0.000001)
        #expect(DesktopAssistantTintGeometry.midpointX(remainingFraction: 0, width: width) == 0)
        #expect(DesktopAssistantTintGeometry.midpointX(remainingFraction: 1, width: width) == width)
    }

    @Test("Accepted green opacity constants are exact")
    func greenOpacity() {
        #expect(DesktopAssistantTintOpacity.light == 0.3042)
        #expect(DesktopAssistantTintOpacity.dark == 0.24336)
        #expect(DesktopAssistantTintOpacity.reducedTransparencyLight == 0.36504)
        #expect(DesktopAssistantTintOpacity.reducedTransparencyDark == 0.32448)
        #expect(DesktopAssistantTintOpacity.increasedContrastLight == 0.48672)
        #expect(DesktopAssistantTintOpacity.increasedContrastDark == 0.36504)
    }

    @Test("Minimalist accessibility retains selected window")
    func accessibility() {
        let card = DesktopAssistantCard(
            id: "codex.local",
            providerName: "Codex",
            connectionState: .connected,
            selectedWindowShortLabel: "7D",
            selectedWindowAccessibilityLabel: "seven-day window",
            usageValue: .finite(44),
            severity: .normal,
            isStale: false
        )
        #expect(card.accessibilityLabel.contains("seven-day window"))
        #expect(card.accessibilityLabel.contains("44 percent remaining"))
        #expect(card.toolTip == card.accessibilityLabel)
    }

    @Test("Automatic density forces Minimalist only at five providers")
    func densityResolution() {
        #expect(DesktopAssistantDensity.automatic.resolvedDensity(visibleProviderCount: 4) == .regular)
        #expect(DesktopAssistantDensity.automatic.resolvedDensity(visibleProviderCount: 5) == .minimalist)
        #expect(DesktopAssistantDensity.regular.resolvedDensity(visibleProviderCount: 8) == .minimalist)
        #expect(DesktopAssistantDensity.minimalist.resolvedDensity(visibleProviderCount: 1) == .minimalist)
        let storedManualPreference = DesktopAssistantDensity.regular
        _ = storedManualPreference.resolvedDensity(visibleProviderCount: 5)
        #expect(storedManualPreference == .regular)
    }

    @MainActor
    @Test("Preferences persist without changing manual density")
    func preferences() {
        let suite = "DesktopAssistantContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let position = DesktopAssistantPosition(
            displayIdentifier: 42,
            horizontalFraction: 0.25,
            verticalFraction: 0.75
        )
        DesktopAssistantPreferences(
            isEnabled: false,
            isAlwaysOnTop: false,
            density: .minimalist,
            position: position
        ).save(to: defaults)

        let restored = DesktopAssistantPreferences.load(from: defaults)
        #expect(restored.isEnabled == false)
        #expect(restored.isAlwaysOnTop == false)
        #expect(restored.density == .minimalist)
        #expect(restored.position == position)
    }

    @MainActor
    @Test("State-driven hiding does not persist position or recurse through defaults")
    func stateDrivenHideIsReadOnly() {
        let suite = "DesktopAssistantContractTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        DesktopAssistantPreferences(
            isEnabled: true,
            isAlwaysOnTop: false,
            density: .minimalist,
            position: nil
        ).save(to: defaults)

        let controller = DesktopAssistantPanelController(defaults: defaults)
        controller.update(cards: [])

        #expect(DesktopAssistantPreferences.load(from: defaults).position == nil)
        #expect(!controller.isVisible)
        controller.tearDown()
    }
}
