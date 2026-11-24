import ClaudeBrowserBridgeProtocol
import Foundation
import Testing
@testable import CodexUsageUI

@Suite("Claude and Gemini reads take turns on the Safari Bridge")
struct SafariBridgeReadQueueTests {
    @Test("An idle Bridge starts a read; the same provider in flight refuses; the other waits")
    func admission() {
        #expect(SafariBridgeReadQueue.admission(for: .gemini, activeProviders: []) == .start)
        #expect(SafariBridgeReadQueue.admission(for: .claude, activeProviders: [.claude]) == .refuse)
        #expect(SafariBridgeReadQueue.admission(for: .gemini, activeProviders: [.claude]) == .wait)
        #expect(SafariBridgeReadQueue.admission(for: .claude, activeProviders: [.gemini]) == .wait)
    }

    @Test("Claude goes first once the Bridge is idle, then the others in order")
    func claudeFirst() {
        var queue = SafariBridgeReadQueue()
        let gemini = SafariBridgeReadQueue.Ticket(id: UUID(), provider: .gemini)
        let claude = SafariBridgeReadQueue.Ticket(id: UUID(), provider: .claude)
        let geminiQueued = queue.enqueue(gemini)
        let claudeQueued = queue.enqueue(claude)
        #expect(geminiQueued && claudeQueued)
        let first = queue.next()
        let second = queue.next()
        let third = queue.next()
        #expect(first == claude)
        #expect(second == gemini)
        #expect(third == nil)
    }

    @Test("Only one read per provider waits, and a given-up wait leaves the queue")
    func oneWaiterPerProvider() {
        var queue = SafariBridgeReadQueue()
        let first = SafariBridgeReadQueue.Ticket(id: UUID(), provider: .gemini)
        let firstQueued = queue.enqueue(first)
        let secondQueued = queue.enqueue(.init(id: UUID(), provider: .gemini))
        let removed = queue.remove(first.id)
        let removedAgain = queue.remove(first.id)
        #expect(firstQueued)
        #expect(!secondQueued)
        #expect(removed)
        #expect(!removedAgain)
        #expect(queue.waiting.isEmpty)
    }
}
