import AppKit
import Combine
import Foundation

public struct WorkBuddyManualPreview: Equatable, Sendable {
    public let observation: WorkBuddyManualObservation

    public var remainingFraction: Double? {
        observation.balance.normalizedRemainingFraction
    }

    public var severity: AgentAvailabilitySeverity {
        guard let fraction = remainingFraction else {
            return observation.balance.isExhausted ? .exhausted : .neutral
        }
        switch fraction {
        case 0: return .exhausted
        case 0...0.10: return .critical
        case 0.10..<0.26: return .warning
        default: return .available
        }
    }
}

@MainActor
public final class WorkBuddySettingsModel: ObservableObject {
    @Published public var draft = WorkBuddyManualDraft()
    @Published public private(set) var lifecycle: WorkBuddyManualSourceLifecycle = .unconfigured
    @Published public private(set) var isEnabled = false
    @Published public private(set) var savedObservation: WorkBuddyManualObservation?
    @Published public private(set) var preview: WorkBuddyManualPreview?
    @Published public private(set) var validationError: WorkBuddyManualValidationError?
    @Published public private(set) var statusMessage: String?

    private let source: ManualWorkBuddyAvailabilitySource
    private let officialPageAction: WorkBuddyOfficialUsagePageAction
    private let now: @Sendable () -> Date
    private var sourceTask: Task<Void, Never>?
    private var didSeedDraft = false

    init(
        source: ManualWorkBuddyAvailabilitySource,
        officialPageAction: WorkBuddyOfficialUsagePageAction = .live,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.source = source
        self.officialPageAction = officialPageAction
        self.now = now
    }

    deinit {
        sourceTask?.cancel()
    }

    public var canSave: Bool {
        isEnabled && (try? draft.validated(at: now())) != nil
    }

    public var canConfirmUnchanged: Bool {
        isEnabled && savedObservation != nil
    }

    public var selectedTierSuggestion: WorkBuddyTierSuggestion? {
        WorkBuddyTierSuggestion.publishedJuly2026.first { $0.tier == draft.tier }
    }

    public func start() {
        guard sourceTask == nil else { return }
        sourceTask = Task { @MainActor [weak self, source] in
            _ = await source.load()
            let stream = await source.states()
            for await state in stream {
                guard !Task.isCancelled else { return }
                self?.receive(state)
            }
        }
    }

    public func updateValidation() {
        preview = nil
        do {
            _ = try draft.validated(at: now())
            validationError = nil
        } catch let error as WorkBuddyManualValidationError {
            validationError = error
        } catch {
            validationError = .invalidManualRecord
        }
    }

    public func makePreview() {
        do {
            let observation = try draft.validated(at: now())
            validationError = nil
            preview = WorkBuddyManualPreview(observation: observation)
            statusMessage = nil
        } catch let error as WorkBuddyManualValidationError {
            validationError = error
            preview = nil
        } catch {
            validationError = .invalidManualRecord
            preview = nil
        }
    }

    public func setEnabled(_ enabled: Bool) {
        Task { @MainActor [weak self, source] in
            do {
                _ = try await source.setEnabled(enabled)
                self?.statusMessage = nil
            } catch {
                self?.statusMessage = WorkBuddyManualValidationError.persistenceUnavailable.rawValue
            }
        }
    }

    public func save(language: AppLanguage = .english) {
        guard let observation = validatedDraft(), isEnabled else { return }
        Task { @MainActor [weak self, source] in
            do {
                let changed = try await source.save(observation)
                self?.preview = nil
                self?.validationError = nil
                self?.statusMessage = changed ? "saved" : "unchanged"
                self?.announce(
                    language.workBuddyStatusMessage(changed ? "saved" : "unchanged")
                )
            } catch let error as WorkBuddyManualValidationError {
                self?.validationError = error
            } catch {
                self?.validationError = .persistenceUnavailable
            }
        }
    }

    public func confirmUnchanged(language: AppLanguage = .english) {
        guard canConfirmUnchanged else { return }
        Task { @MainActor [weak self, source, now] in
            do {
                _ = try await source.confirmUnchanged(at: now())
                self?.statusMessage = "confirmed"
                self?.announce(language.workBuddyStatusMessage("confirmed"))
            } catch let error as WorkBuddyManualValidationError {
                self?.validationError = error
            } catch {
                self?.validationError = .persistenceUnavailable
            }
        }
    }

    public func clear(language: AppLanguage = .english) {
        Task { @MainActor [weak self, source] in
            do {
                _ = try await source.clear()
                self?.draft = WorkBuddyManualDraft()
                self?.preview = nil
                self?.validationError = nil
                self?.statusMessage = "cleared"
                self?.didSeedDraft = true
                self?.announce(language.workBuddyStatusMessage("cleared"))
            } catch {
                self?.validationError = .persistenceUnavailable
            }
        }
    }

    public func applySelectedTierSuggestion() {
        guard let suggestion = selectedTierSuggestion else { return }
        draft.companionField = .total
        draft.companionText = String(suggestion.suggestedTotal)
        preview = nil
        updateValidation()
    }

    @discardableResult
    public func openOfficialUsagePage() -> Bool {
        let opened = officialPageAction.request()
        statusMessage = opened ? "officialPageOpened" : "officialPageFailed"
        return opened
    }

    private func receive(_ state: WorkBuddyManualSourceState) {
        lifecycle = state.lifecycle
        isEnabled = state.enabled
        savedObservation = state.observation
        if !didSeedDraft, let observation = state.observation {
            draft = .from(observation)
            didSeedDraft = true
        }
    }

    private func validatedDraft() -> WorkBuddyManualObservation? {
        do {
            let observation = try draft.validated(at: now())
            validationError = nil
            return observation
        } catch let error as WorkBuddyManualValidationError {
            validationError = error
            return nil
        } catch {
            validationError = .invalidManualRecord
            return nil
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue
            ]
        )
    }
}
