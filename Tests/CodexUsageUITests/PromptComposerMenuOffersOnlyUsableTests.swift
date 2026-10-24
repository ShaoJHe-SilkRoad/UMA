import Foundation
import Testing
@testable import CodexUsageUI

/// A menu that offers a choice the generator then refuses is a trap: the user
/// picks it, nothing says no until Copy fails. This pins the two halves
/// together — what the composer presents as selectable, and what
/// `ThreadOSLeaderPrompt.make` accepts — so they cannot drift apart silently.
@Suite("Prompt composer offers only usable selections", .timeLimit(.minutes(1)))
struct PromptComposerMenuOffersOnlyUsableTests {
    /// The other three roles held at a combination the catalog allows, so a
    /// refusal can only come from the role under test.
    private func baseline(excluding role: ThreadOSPromptRole)
        -> [ThreadOSPromptRole: ThreadOSPromptSelection] {
        var values: [ThreadOSPromptRole: ThreadOSPromptSelection] = [:]
        for other in ThreadOSPromptRole.allCases where other != role {
            values[other] = .init(model: "gpt-6.1-sol", effort: "high")
        }
        return values
    }

    private func makeAccepts(model: String, effort: String, for role: ThreadOSPromptRole) -> Bool {
        var values = baseline(excluding: role)
        values[role] = .init(model: model, effort: effort)
        return (try? ThreadOSLeaderPrompt.make(selections: values, language: .english)) != nil
    }

    /// `canSelect` is what the effort menu sets each item's `enabled` from, so
    /// it has to agree with the generator for every pair, in both directions.
    @Test("What the menu enables is exactly what the generator accepts")
    func menuEnablementMatchesTheGenerator() {
        let capabilities = ThreadOSCapabilities.unverified
        var checked = 0
        for role in ThreadOSPromptRole.allCases {
            for model in ThreadOSLeaderPrompt.supportedModels {
                for effort in ThreadOSLeaderPrompt.supportedEfforts {
                    let enabled = ThreadOSCapabilities.catalogAllows(model: model, effort: effort)
                        && capabilities.availability(model: model, effort: effort) != .unsupported
                    #expect(
                        enabled == makeAccepts(model: model, effort: effort, for: role),
                        "\(role) \(model)/\(effort): menu says \(enabled)"
                    )
                    checked += 1
                }
            }
        }
        #expect(checked == ThreadOSPromptRole.allCases.count
            * ThreadOSLeaderPrompt.supportedModels.count
            * ThreadOSLeaderPrompt.supportedEfforts.count)
    }

    /// Both halves must actually have something to disagree about: a run where
    /// every pair is allowed would pass the test above while proving nothing.
    @Test("Some pairs are refused, so the agreement above is not vacuous")
    func someSelectionsAreRefused() {
        let refused = ThreadOSLeaderPrompt.supportedModels.flatMap { model in
            ThreadOSLeaderPrompt.supportedEfforts.filter {
                !ThreadOSCapabilities.catalogAllows(model: model, effort: $0)
            }
        }
        #expect(!refused.isEmpty)
    }

    /// Every effort the menu can show has a label in both languages. `ultra`
    /// went untranslated in Chinese while the other four were translated.
    @Test("Every effort is labelled in both languages")
    @MainActor
    func everyEffortIsLabelled() {
        for language in AppLanguage.allCases {
            for effort in ThreadOSLeaderPrompt.supportedEfforts {
                let label = ThreadOSPromptComposerSummary.effortLabel(effort, language: language)
                #expect(!label.isEmpty)
                #expect(label != effort)
            }
            // Case-insensitively equal to the raw key is still untranslated —
            // `ultra` rendered as "Ultra" in Chinese and slipped a weaker
            // check that only compared against the key verbatim.
            for effort in ThreadOSLeaderPrompt.supportedEfforts where language == .simplifiedChinese {
                let chinese = ThreadOSPromptComposerSummary.effortLabel(effort, language: language)
                #expect(chinese.lowercased() != effort.lowercased())
                #expect(chinese != ThreadOSPromptComposerSummary.effortLabel(effort, language: .english))
            }
        }
    }
}
