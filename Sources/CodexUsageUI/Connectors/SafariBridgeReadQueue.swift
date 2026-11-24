import ClaudeBrowserBridgeProtocol
import Foundation

/// What a Gemini read through the Safari Bridge reports back, in order: the
/// observation before the terminal event, as for Claude.
enum GeminiBrowserInboundEvent: Sendable {
    case observation(GeminiBrowserObservationEnvelope)
    case automation(ClaudeBrowserAutomationEvent)
    case dispatchFailure(ClaudeBrowserAutomaticDispatchResult)
}

/// The Safari Bridge Host and the companion each run one read at a time, and
/// the companion keeps a single owned-tab receipt. Claude and Gemini reads
/// therefore take turns here, in AUV, instead of a second read being refused
/// by the Host as `requestInFlight` and reported as a failure.
///
/// A read of the provider already reading is still refused at once, exactly
/// as before Gemini: two reads of one page in a row would only race.
struct SafariBridgeReadQueue: Sendable {
    enum Admission: Equatable, Sendable {
        case start
        case wait
        case refuse
    }

    struct Ticket: Equatable, Sendable {
        let id: UUID
        let provider: BrowserUsageProvider
    }

    private(set) var waiting: [Ticket] = []

    static func admission(
        for provider: BrowserUsageProvider,
        activeProviders: [BrowserUsageProvider]
    ) -> Admission {
        if activeProviders.isEmpty { return .start }
        return activeProviders.contains(provider) ? .refuse : .wait
    }

    /// One waiting read per provider; a second one of the same provider is
    /// refused, since the first already covers it.
    mutating func enqueue(_ ticket: Ticket) -> Bool {
        guard !waiting.contains(where: { $0.provider == ticket.provider }) else { return false }
        waiting.append(ticket)
        return true
    }

    @discardableResult
    mutating func remove(_ id: UUID) -> Bool {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return false }
        waiting.remove(at: index)
        return true
    }

    /// The next read to start once the Bridge is idle. Claude goes first: its
    /// exact reading anchors the Smart estimate, and its sync was there first.
    mutating func next() -> Ticket? {
        let index = waiting.firstIndex(where: { $0.provider == .claude }) ?? waiting.indices.first
        guard let index else { return nil }
        return waiting.remove(at: index)
    }
}

/// Delivers one provider's inbound events strictly in the order they arrived.
final class SafariBridgeOrderedConsumer<Event: Sendable>: @unchecked Sendable {
    typealias Processor = @Sendable (Event) async -> Void

    private let lock = NSLock()
    private let processor: Processor
    private var pending: [Event] = []
    private var isDraining = false

    init(processor: @escaping Processor) { self.processor = processor }

    func submit(_ event: Event) {
        let shouldStart = lock.withLock {
            pending.append(event)
            guard !isDraining else { return false }
            isDraining = true
            return true
        }
        guard shouldStart else { return }
        Task { await drain() }
    }

    private func drain() async {
        while let event = next() { await processor(event) }
    }

    private func next() -> Event? {
        lock.withLock {
            guard !pending.isEmpty else {
                isDraining = false
                return nil
            }
            return pending.removeFirst()
        }
    }
}
