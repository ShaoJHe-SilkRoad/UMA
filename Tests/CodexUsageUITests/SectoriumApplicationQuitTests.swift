import Foundation
import HESectoriumRuntime
import Testing
@testable import CodexUsageUI

@Suite("Sectorium normal app quit", .serialized)
@MainActor struct SectoriumApplicationQuitTests {
    let app = SectoriumQuitApplication(processID: 41001, bundleIdentifier: "test.fixture.editor", name: "Fixture Editor")

    @Test("Normal quit completion waits for observed process exit")
    func finishesAfterObservedExit() async {
        let fake = QuitFixture()
        fake.running = [app.id]
        var pauses = 0
        let result = await SectoriumApplicationQuitSequence.run(applications: [app], quitter: fake, attempts: 3) {
            pauses += 1
            fake.running.remove(app.id)
        }
        #expect(result == .finished && pauses == 1)
        #expect(fake.requests == [app])
    }

    @Test("A refused normal quit stops without retrying or forcing termination")
    func refusedQuitStops() async {
        let fake = QuitFixture()
        fake.accept = false
        fake.running = [app.id]
        let result = await SectoriumApplicationQuitSequence.run(applications: [app], quitter: fake, attempts: 3) {
            Issue.record("A refused quit must return immediately")
        }
        #expect(result == .refused([app.name]))
        #expect(fake.requests == [app] && fake.running == [app.id])
    }

    @Test("Save dialogs have a bounded wait and leave the running app alone")
    func uncompletedSavePromptTimesOut() async {
        let fake = QuitFixture()
        fake.running = [app.id]
        var pauses = 0
        let result = await SectoriumApplicationQuitSequence.run(applications: [app], quitter: fake, attempts: 3) {
            pauses += 1
        }
        #expect(result == .stillRunning([app.name]) && pauses == 3)
        #expect(fake.requests == [app] && fake.running == [app.id])
    }

    @Test("Cancelled consent does not issue quit requests")
    func cancellationDoesNotQuit() async {
        let fake = QuitFixture()
        let task = Task { @MainActor in
            await Task.yield()
            return await SectoriumApplicationQuitSequence.run(applications: [app], quitter: fake) {}
        }
        task.cancel()
        #expect(await task.value == .cancelled)
        #expect(fake.requests.isEmpty)
    }

    @Test("Quit preserves the exact displayed process and bundle identities")
    func exactTargetsOnly() async {
        let fake = QuitFixture()
        let second = SectoriumQuitApplication(processID: 41002, bundleIdentifier: "test.fixture.shell", name: "Fixture Shell")
        fake.running = [second.id]
        let result = await SectoriumApplicationQuitSequence.run(applications: [app, second], quitter: fake, attempts: 1) {
            fake.running.remove(second.id)
        }
        #expect(result == .finished)
        #expect(fake.requests == [app, second])
    }
}

@MainActor private final class QuitFixture: SectoriumApplicationQuitting {
    var requests: [SectoriumQuitApplication] = []
    var running: Set<Int32> = []
    var accept = true
    func applications(using processes: [SectoriumActivityProcess]) -> [SectoriumQuitApplication] { [] }
    func requestQuit(_ application: SectoriumQuitApplication) -> Bool { requests.append(application); return accept }
    func isRunning(_ application: SectoriumQuitApplication) -> Bool { running.contains(application.id) }
}
