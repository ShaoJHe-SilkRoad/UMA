import Foundation
import Testing
@testable import CodexUsageUI

/// The agent list can be dragged into an order, that order is kept until it is
/// changed again, and it decides which agent the menu bar reads.
///
/// The rules live in `AgentDisplayOrder` as pure functions so they can be
/// stated directly. `UsageStore.menuProvider` and the two list views are thin
/// adapters over them; what those adapters feed in — a quota's remaining
/// percentage, the inventory's own filtering — is not covered here.
@Suite("Agent display order", .timeLimit(.minutes(1)))
struct AgentDisplayOrderTests {
    private func apply(_ items: [String], _ order: [String]) -> [String] {
        AgentDisplayOrder.apply(items, order: order, id: { $0 })
    }

    // MARK: - Arranging the list

    // An install that has never touched the list must see what it saw before.
    @Test("An empty arrangement leaves the list alone")
    func emptyOrderIsIdentity() {
        #expect(apply(["codex", "claude", "workBuddy"], []) == ["codex", "claude", "workBuddy"])
        #expect(apply([], []) == [])
    }

    @Test("A full arrangement reorders the list")
    func fullOrderRearranges() {
        #expect(apply(["codex", "claude"], ["claude", "codex"]) == ["claude", "codex"])
        #expect(
            apply(["codex", "claude", "workBuddy"], ["workBuddy", "claude", "codex"])
                == ["workBuddy", "claude", "codex"]
        )
    }

    // A newly discovered agent must appear, not vanish and not jump to the top.
    @Test("An agent the arrangement does not mention goes last, in place")
    func unmentionedAgentsFollowInOriginalOrder() {
        #expect(
            apply(["codex", "claude", "workBuddy", "antigravity"], ["claude"])
                == ["claude", "codex", "workBuddy", "antigravity"]
        )
        #expect(
            apply(["codex", "claude", "workBuddy"], ["workBuddy", "codex"])
                == ["workBuddy", "codex", "claude"]
        )
    }

    // An arrangement outlives the agents in it, so it will name ones that are
    // no longer installed. Those must not resurrect anything.
    @Test("An arrangement naming absent agents still orders the present ones")
    func staleIdentifiersAreIgnored() {
        #expect(
            apply(["codex", "claude"], ["ghost", "claude", "other", "codex"])
                == ["claude", "codex"]
        )
        #expect(apply(["codex"], ["ghost"]) == ["codex"])
    }

    @Test("A repeated identifier takes its first position")
    func duplicateIdentifiersUseTheFirstRank() {
        #expect(apply(["codex", "claude"], ["claude", "codex", "claude"]) == ["claude", "codex"])
    }

    // MARK: - Dragging one row onto another

    @Test("Dragging a row onto another puts it in that position")
    func movingProducesTheArrangement() {
        let displayed = ["codex", "claude", "workBuddy"]
        #expect(
            AgentDisplayOrder.moving("workBuddy", onto: "codex", in: displayed)
                == ["workBuddy", "codex", "claude"]
        )
        #expect(
            AgentDisplayOrder.moving("codex", onto: "workBuddy", in: displayed)
                == ["claude", "workBuddy", "codex"]
        )
    }

    // A drag that changes nothing must not write anything, or every stray drop
    // would rewrite the stored arrangement.
    @Test("A drag that changes nothing reports no change")
    func noOpDragsReturnNil() {
        let displayed = ["codex", "claude"]
        #expect(AgentDisplayOrder.moving("codex", onto: "codex", in: displayed) == nil)
        #expect(AgentDisplayOrder.moving("ghost", onto: "codex", in: displayed) == nil)
        #expect(AgentDisplayOrder.moving("codex", onto: "ghost", in: displayed) == nil)
    }

    @Test("Rearranging twice keeps only the latest arrangement")
    func successiveMovesCompose() {
        let first = try! #require(
            AgentDisplayOrder.moving("claude", onto: "codex", in: ["codex", "claude", "workBuddy"])
        )
        #expect(first == ["claude", "codex", "workBuddy"])
        let second = try! #require(
            AgentDisplayOrder.moving("workBuddy", onto: "claude", in: first)
        )
        #expect(second == ["workBuddy", "claude", "codex"])
    }

    // MARK: - Which agent the menu bar reads

    // Existing installs have no arrangement, and must be unaffected.
    @Test("Without an arrangement Codex keeps priority, others are the fallback")
    func unarrangedKeepsThePreferredAgent() {
        #expect(
            AgentDisplayOrder.menuReading(
                amongEligible: ["claude", "codex"], isArranged: false, preferred: "codex"
            ) == "codex"
        )
        // Codex has nothing to report, so the next eligible agent is used.
        #expect(
            AgentDisplayOrder.menuReading(
                amongEligible: ["claude"], isArranged: false, preferred: "codex"
            ) == "claude"
        )
        #expect(
            AgentDisplayOrder.menuReading(
                amongEligible: [String](), isArranged: false, preferred: "codex"
            ) == nil
        )
    }

    // The point of the feature: the top of the user's list drives the menu bar.
    @Test("An arrangement decides, and falls down the list rather than blanking")
    func arrangedFollowsTheUsersOrder() {
        // Claude pinned on top and reporting: the menu bar is Claude's, even
        // though Codex also has a reading.
        #expect(
            AgentDisplayOrder.menuReading(
                amongEligible: ["claude", "codex"], isArranged: true, preferred: "codex"
            ) == "claude"
        )
        // Claude pinned on top with nothing to report is absent from the
        // eligible list, so the reading falls to the next agent in that order.
        #expect(
            AgentDisplayOrder.menuReading(
                amongEligible: ["codex"], isArranged: true, preferred: "codex"
            ) == "codex"
        )
        #expect(
            AgentDisplayOrder.menuReading(
                amongEligible: ["workBuddy", "codex"], isArranged: true, preferred: "codex"
            ) == "workBuddy"
        )
        #expect(
            AgentDisplayOrder.menuReading(
                amongEligible: [String](), isArranged: true, preferred: "codex"
            ) == nil
        )
    }

    // MARK: - Keeping it until it changes again

    @Test("The arrangement round-trips through stored preferences")
    @MainActor
    func orderPersists() {
        let defaults = try! #require(UserDefaults(suiteName: "uma.agent-order.\(UUID().uuidString)"))
        defer { defaults.removeSuite(named: defaults.description) }
        let preferences = ApplicationPreferences(userDefaults: defaults)
        let key = UMAApplicationPreferenceKeys.agentOrder

        // Nothing stored yet is an empty arrangement, not a missing one.
        #expect(preferences.value(for: key) == [])

        preferences.set(["claude", "codex"], for: key)
        #expect(preferences.value(for: key) == ["claude", "codex"])

        // A second reader of the same defaults sees it, which is what survives
        // a relaunch.
        #expect(ApplicationPreferences(userDefaults: defaults).value(for: key) == ["claude", "codex"])

        // And it stays until it is changed again.
        preferences.set(["codex", "claude"], for: key)
        #expect(preferences.value(for: key) == ["codex", "claude"])
    }

    @Test("A malformed stored arrangement yields the identifiers it does hold")
    @MainActor
    func malformedStoredOrderIsFiltered() {
        let defaults = try! #require(UserDefaults(suiteName: "uma.agent-order.\(UUID().uuidString)"))
        defer { defaults.removeSuite(named: defaults.description) }
        defaults.set(["claude", 7, "codex"] as [Any], forKey: UMAApplicationPreferenceKeys.agentOrder.name)
        #expect(
            ApplicationPreferences(userDefaults: defaults)
                .value(for: UMAApplicationPreferenceKeys.agentOrder) == ["claude", "codex"]
        )
    }
}
