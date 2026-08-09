import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M6-G2 bounded Antigravity CLI client")
struct M6G2AntigravityCLIClientTests {
    private let executable = URL(
        fileURLWithPath: AntigravityReadOnlyCLIClient.executablePath
    )

    @Test
    func exactExecutableArgumentsNeutralDirectoryAndEnvironment() async throws {
        let capture = InvocationCapture()
        let workingDirectory = URL(
            fileURLWithPath: "/private/tmp/uma-m6-g2-fixture-cwd"
        )
        let client = makeClient(
            workingDirectory: workingDirectory,
            run: { invocation in
                await capture.record(invocation)
                return .init(
                    stdout: validFixture(),
                    stderr: Data(),
                    terminationStatus: 0
                )
            }
        )
        let snapshot = try await client.readCurrentQuota()
        let invocation = try #require(await capture.invocation)

        #expect(invocation.executableURL.path == AntigravityReadOnlyCLIClient.executablePath)
        #expect(invocation.arguments == ["--output-format", "json", "-p", "/usage"])
        #expect(invocation.workingDirectoryURL == workingDirectory)
        #expect(invocation.timeout == 15)
        #expect(invocation.hardTimeout == 20)
        #expect(invocation.stdoutLimit == 64 * 1_024)
        #expect(invocation.stderrLimit == 16 * 1_024)
        #expect(Set(invocation.environment.keys) == ["HOME", "TMPDIR", "LANG", "LC_ALL"])
        #expect(!invocation.environment.keys.contains("PATH"))
        #expect(!invocation.environment.keys.contains("ANTHROPIC_API_KEY"))
        #expect(snapshot.buckets.first?.remainingPercent == 50)
    }

    @Test
    func executableAbsentAndUntrustedCandidatesFailBeforeLaunch() async {
        let launch = Counter()
        for expected in [
            AntigravityCLIClientError.notInstalled,
            AntigravityCLIClientError.untrustedExecutable,
        ] {
            let client = AntigravityReadOnlyCLIClient(
                dependencies: .init(
                    inspectExecutable: { _ in throw expected },
                    makeWorkingDirectory: { URL(fileURLWithPath: "/private/tmp/unused") },
                    removeWorkingDirectory: { _ in },
                    run: { _ in
                        await launch.increment()
                        throw AntigravityCLIClientError.providerUnavailable
                    },
                    now: Date.init
                )
            )
            await #expect(throws: expected) {
                try await client.readCurrentQuota()
            }
        }
        #expect(await launch.value == 0)
    }

    @Test
    func trustGateRejectsWrongHashArchitectureOrPath() {
        let identities: [AntigravityExecutableIdentity] = [
            admittedIdentity(sha256: String(repeating: "0", count: 64)),
            admittedIdentity(architecture: "x86_64"),
            admittedIdentity(
                canonicalURL: URL(fileURLWithPath: "/private/tmp/agy")
            ),
            admittedIdentity(ownerUID: getuid() &+ 1),
            admittedIdentity(mode: 0o644),
        ]
        for identity in identities {
            let client = makeClient(identity: identity, run: { _ in
                Issue.record("Untrusted executable launched")
                throw AntigravityCLIClientError.providerUnavailable
            })
            #expect(throws: AntigravityCLIClientError.untrustedExecutable) {
                try client.verifyCapability()
            }
        }
    }

    @Test
    func nonzeroExitIsBoundedAndRawStderrNeverEscapes() async {
        let client = makeClient(run: { _ in
            .init(
                stdout: Data(),
                stderr: Data("synthetic private diagnostic".utf8),
                terminationStatus: 7
            )
        })
        await #expect(throws: AntigravityCLIClientError.processExited) {
            try await client.readCurrentQuota()
        }
    }

    @Test
    func authenticationClassificationIsBounded() async {
        let client = makeClient(run: { _ in
            .init(
                stdout: Data(),
                stderr: Data("Sign in required".utf8),
                terminationStatus: 1
            )
        })
        await #expect(throws: AntigravityCLIClientError.loginRequired) {
            try await client.readCurrentQuota()
        }
    }

    @Test
    func malformedAndUnsupportedSchemaAreFailClosed() async {
        let malformed = makeClient(run: { _ in
            .init(stdout: Data("{".utf8), stderr: Data(), terminationStatus: 0)
        })
        await #expect(throws: AntigravityCLIClientError.malformedOutput) {
            try await malformed.readCurrentQuota()
        }

        let unsupported = makeClient(run: { _ in
            .init(
                stdout: Data(#"{"command":{"name":"credits"}}"#.utf8),
                stderr: Data(),
                terminationStatus: 0
            )
        })
        await #expect(throws: AntigravityCLIClientError.unsupportedSchema) {
            try await unsupported.readCurrentQuota()
        }

        let invalidBucket = makeClient(run: { _ in
            var object = try #require(
                JSONSerialization.jsonObject(with: validFixture())
                    as? [String: Any]
            )
            var command = try #require(object["command"] as? [String: Any])
            var data = try #require(command["data"] as? [String: Any])
            var groups = try #require(data["groups"] as? [[String: Any]])
            var buckets = try #require(groups[0]["buckets"] as? [[String: Any]])
            buckets[0]["id"] = "unsafe identity"
            groups[0]["buckets"] = buckets
            data["groups"] = groups
            command["data"] = data
            object["command"] = command
            return .init(
                stdout: try JSONSerialization.data(withJSONObject: object),
                stderr: Data(),
                terminationStatus: 0
            )
        })
        await #expect(throws: AntigravityCLIClientError.invalidBucket) {
            try await invalidBucket.readCurrentQuota()
        }
    }

    @Test
    func productionRunnerCoversSuccessExitTimeoutOversizeAndTeardown() async throws {
        let runner = FoundationAntigravityProcessRunner()
        let cwd = FileManager.default.temporaryDirectory
        let success = try await runner.run(
            invocation(
                executable: "/usr/bin/printf",
                arguments: ["fixture"],
                cwd: cwd
            )
        )
        #expect(success.stdout == Data("fixture".utf8))
        #expect(success.terminationStatus == 0)

        let failure = try await runner.run(
            invocation(executable: "/usr/bin/false", cwd: cwd)
        )
        #expect(failure.terminationStatus != 0)

        await #expect(throws: AntigravityCLIClientError.outputTooLarge) {
            try await runner.run(
                invocation(
                    executable: "/usr/bin/yes",
                    cwd: cwd,
                    stdoutLimit: 128
                )
            )
        }
        await #expect(throws: AntigravityCLIClientError.timedOut) {
            try await runner.run(
                invocation(
                    executable: "/bin/sleep",
                    arguments: ["5"],
                    cwd: cwd,
                    timeout: 0.05
                )
            )
        }
    }

    @Test
    func productionRunnerCancellationTerminatesOwnedChild() async {
        let runner = FoundationAntigravityProcessRunner()
        let clock = ContinuousClock()
        let startedAt = clock.now
        let task = Task {
            try await runner.run(
                invocation(
                    executable: "/bin/sleep",
                    arguments: ["5"],
                    cwd: FileManager.default.temporaryDirectory,
                    timeout: 10
                )
            )
        }
        await Task.yield()
        task.cancel()
        await #expect(throws: AntigravityCLIClientError.cancelled) {
            try await task.value
        }
        #expect(startedAt.duration(to: clock.now) < .seconds(2))
    }

    private func makeClient(
        identity: AntigravityExecutableIdentity? = nil,
        workingDirectory: URL = URL(fileURLWithPath: "/private/tmp/uma-m6-g2-fixture-cwd"),
        run: @escaping @Sendable (AntigravityCLIInvocation) async throws
            -> AntigravityCLIProcessResult
    ) -> AntigravityReadOnlyCLIClient {
        AntigravityReadOnlyCLIClient(
            executableURL: executable,
            dependencies: .init(
                inspectExecutable: { _ in identity ?? admittedIdentity() },
                makeWorkingDirectory: { workingDirectory },
                removeWorkingDirectory: { _ in },
                run: run,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }
            )
        )
    }

    private func admittedIdentity(
        canonicalURL: URL? = nil,
        sha256: String = AntigravityReadOnlyCLIClient.admittedSHA256,
        architecture: String = "arm64",
        ownerUID: uid_t = getuid(),
        mode: mode_t = 0o755
    ) -> AntigravityExecutableIdentity {
        AntigravityExecutableIdentity(
            canonicalURL: canonicalURL ?? executable,
            sha256: sha256,
            architecture: architecture,
            ownerUID: ownerUID,
            mode: mode
        )
    }

    private func invocation(
        executable: String,
        arguments: [String] = [],
        cwd: URL,
        timeout: TimeInterval = 2,
        hardTimeout: TimeInterval = 3,
        stdoutLimit: Int = 1_024
    ) -> AntigravityCLIInvocation {
        .init(
            executableURL: URL(fileURLWithPath: executable),
            arguments: arguments,
            workingDirectoryURL: cwd,
            environment: [:],
            timeout: timeout,
            hardTimeout: hardTimeout,
            stdoutLimit: stdoutLimit,
            stderrLimit: 1_024
        )
    }

    private func validFixture() -> Data {
        let object: [String: Any] = [
            "num_turns": 0,
            "conversation_id": "",
            "duration_seconds": 0,
            "response": "Synthetic ignored response",
            "status": "success",
            "usage": ["input_tokens": 0],
            "command": [
                "name": "usage",
                "data": [
                    "description": "Synthetic quota fixture",
                    "groups": [[
                        "name": "group-a",
                        "description": "Synthetic group",
                        "buckets": [[
                            "id": "pool-a",
                            "name": "Synthetic label",
                            "window": "window-a",
                            "remaining_fraction": 0.5,
                        ]],
                    ]],
                ],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: object)
    }
}

private actor InvocationCapture {
    private(set) var invocation: AntigravityCLIInvocation?
    func record(_ invocation: AntigravityCLIInvocation) {
        self.invocation = invocation
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
