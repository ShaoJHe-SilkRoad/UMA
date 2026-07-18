import Foundation
import Testing
@testable import CodexUsageUI

struct M1AG2RefreshCoordinatorTests {
    @Test
    func burstOfFiftyRequestsUsesOneProviderOperation() async throws {
        let coordinator = CodexRefreshCoordinator<Int>()
        let gate = RefreshOperationGate()

        let first = Task { try await coordinator.refresh(trigger: .timer) { try await gate.perform() } }
        await gate.waitUntilStarted(count: 1)
        let joined = (0..<49).map { _ in
            Task { try await coordinator.refresh(trigger: .providerEvent) { try await gate.perform() } }
        }

        for _ in 0..<20 {
            if (await coordinator.diagnostics()).coalescedRequestCount == 49 { break }
            await Task.yield()
        }
        let duringBurst = await coordinator.diagnostics()
        #expect(await gate.startCount == 1)
        #expect(duringBurst.activeTrigger == .timer)
        #expect(duringBurst.highestCoalescedTrigger == .providerEvent)
        #expect(duringBurst.coalescedRequestCount == 49)

        await gate.finish(value: 42, at: 0)
        let firstValue = try await first.value
        #expect(firstValue == 42)
        for task in joined {
            let joinedValue = try await task.value
            #expect(joinedValue == 42)
        }
        #expect((await coordinator.diagnostics()).activeGeneration == nil)
    }

    @Test
    func higherPriorityTriggersCoalesceWithoutStartingAnExtraRead() async throws {
        let coordinator = CodexRefreshCoordinator<Int>()
        let gate = RefreshOperationGate()

        let timer = Task { try await coordinator.refresh(trigger: .timer) { try await gate.perform() } }
        await gate.waitUntilStarted(count: 1)
        let event = Task { try await coordinator.refresh(trigger: .providerEvent) { try await gate.perform() } }
        let wake = Task { try await coordinator.refresh(trigger: .wake) { try await gate.perform() } }
        let manual = Task { try await coordinator.refresh(trigger: .manual) { try await gate.perform() } }

        for _ in 0..<20 {
            if (await coordinator.diagnostics()).coalescedRequestCount == 3 { break }
            await Task.yield()
        }
        let diagnostics = await coordinator.diagnostics()
        #expect(await gate.startCount == 1)
        #expect(diagnostics.highestCoalescedTrigger == .manual)
        #expect(diagnostics.coalescedRequestCount == 3)

        await gate.finish(value: 7, at: 0)
        let timerValue = try await timer.value
        let eventValue = try await event.value
        let wakeValue = try await wake.value
        let manualValue = try await manual.value
        #expect(timerValue == 7)
        #expect(eventValue == 7)
        #expect(wakeValue == 7)
        #expect(manualValue == 7)
    }

    @Test
    func cancellationInvalidatesLateGenerationWithoutClearingNewRefresh() async throws {
        let coordinator = CodexRefreshCoordinator<Int>()
        let gate = RefreshOperationGate()

        let first = Task { try await coordinator.refresh(trigger: .timer) { try await gate.perform() } }
        await gate.waitUntilStarted(count: 1)
        await coordinator.cancelOutstandingRefresh()

        let second = Task { try await coordinator.refresh(trigger: .manual) { try await gate.perform() } }
        await gate.waitUntilStarted(count: 2)
        await gate.finish(value: 1, at: 0) // Deliberately ignores cancellation.

        let third = Task { try await coordinator.refresh(trigger: .wake) { try await gate.perform() } }
        for _ in 0..<20 {
            if (await coordinator.diagnostics()).coalescedRequestCount == 1 { break }
            await Task.yield()
        }
        let afterLateCompletion = await coordinator.diagnostics()
        #expect(await gate.startCount == 2)
        #expect(afterLateCompletion.activeGeneration == 2)
        #expect(afterLateCompletion.highestCoalescedTrigger == .manual)

        await gate.finish(value: 2, at: 0)
        let firstValue = try await first.value
        let secondValue = try await second.value
        let thirdValue = try await third.value
        #expect(firstValue == 1)
        #expect(secondValue == 2)
        #expect(thirdValue == 2)
        #expect((await coordinator.diagnostics()).completedGeneration == 2)
    }

    @Test
    func overloadBackoffDelaysOnlyTheNextExplicitRequest() async throws {
        let sleeper = RecordedSleeper()
        let coordinator = CodexRefreshCoordinator<Int>(
            initialBackoff: 3,
            maximumBackoff: 12,
            now: { Date(timeIntervalSince1970: 1_784_332_800) },
            sleeper: { seconds in await sleeper.record(seconds) }
        )

        do {
            _ = try await coordinator.refresh(trigger: .timer) {
                throw CodexUsageClientError(.serverOverloaded)
            }
            #expect(Bool(false))
        } catch let error as CodexUsageClientError {
            #expect(error.failure == .serverOverloaded)
        }

        #expect((await coordinator.diagnostics()).consecutiveOverloads == 1)
        let successfulValue = try await coordinator.refresh(trigger: .manual) { 99 }
        #expect(successfulValue == 99)
        #expect(await sleeper.delays == [3])
        let afterSuccess = await coordinator.diagnostics()
        #expect(afterSuccess.consecutiveOverloads == 0)
        #expect(afterSuccess.isBackoffActive == false)
    }
}

private actor RefreshOperationGate {
    private var continuations: [CheckedContinuation<Int, Error>] = []
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var startCount = 0

    func perform() async throws -> Int {
        startCount += 1
        resumeSatisfiedWaiters()
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilStarted(count: Int) async {
        guard startCount < count else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func finish(value: Int, at index: Int) {
        guard continuations.indices.contains(index) else { return }
        let continuation = continuations.remove(at: index)
        continuation.resume(returning: value)
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in startWaiters {
            if startCount >= waiter.count {
                waiter.continuation.resume()
            } else {
                remaining.append(waiter)
            }
        }
        startWaiters = remaining
    }
}

private actor RecordedSleeper {
    private(set) var delays: [TimeInterval] = []
    func record(_ seconds: TimeInterval) { delays.append(seconds) }
}
