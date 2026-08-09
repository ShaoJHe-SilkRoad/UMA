import Foundation
import Testing
@testable import CodexUsageUI

@Suite("M6-G2 Antigravity strict quota decoder")
struct M6G2AntigravityQuotaDecoderTests {
    private let observedAt = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func admittedSchemaPreservesIndependentBucketsAndNormalizesOnce() throws {
        let decoded = try decode(groups: [
            group("group-a", buckets: [
                bucket("pool-a", window: "five-hour", remaining: 0.25,
                       reset: "2027-01-15T10:30:00Z", name: "Five hour"),
                bucket("pool-b", window: "seven-day", remaining: 1),
            ]),
        ], extras: [
            "response": ["text": "must-not-survive"],
        ])

        #expect(decoded.sourceVersion == "agy-1.1.11")
        #expect(decoded.observedAt == observedAt)
        #expect(decoded.buckets.map(\.id) == ["pool-a", "pool-b"])
        #expect(decoded.buckets.map(\.remainingPercent) == [25, 100])
        #expect(decoded.buckets[0].displayLabel == "Five hour")
        #expect(decoded.buckets[1].displayLabel == "Synthetic label")
        #expect(decoded.buckets[0].resetsAt != nil)
        let reflection = String(reflecting: decoded)
        #expect(!reflection.contains("must-not-survive"))
    }

    @Test
    func reorderedBucketsRetainProviderIdentity() throws {
        let first = try decode(groups: [group("group-a", buckets: [
            bucket("pool-a", window: "a", remaining: 0.4),
            bucket("pool-b", window: "b", remaining: 0.8),
        ])])
        let second = try decode(groups: [group("group-a", buckets: [
            bucket("pool-b", window: "b", remaining: 0.7),
            bucket("pool-a", window: "a", remaining: 0.3),
        ])])
        #expect(Set(first.buckets.map(\.id)) == Set(second.buckets.map(\.id)))
        #expect(first.buckets.map(\.remainingPercent) != second.buckets.map(\.remainingPercent))
    }

    @Test(arguments: [0.0, 0.1, 0.5, 1.0])
    func acceptsFiniteRemainingBoundary(_ fraction: Double) throws {
        let decoded = try decode(groups: [
            group("group-a", buckets: [
                bucket("pool-a", window: "window-a", remaining: fraction),
            ]),
        ])
        #expect(decoded.buckets[0].remainingPercent == fraction * 100)
    }

    @Test(arguments: [-0.01, 1.01])
    func rejectsOutOfRangeRemaining(_ fraction: Double) {
        #expect(throws: AntigravityQuotaDecodingError.invalidBucket) {
            try decode(groups: [group("g", buckets: [
                bucket("p", window: "w", remaining: fraction),
            ])])
        }
    }

    @Test
    func rejectsNaNAndMissingOrWrongTypedRemaining() throws {
        for nonJSONNumber in ["NaN", "Infinity", "-Infinity"] {
            let payload = #"{"num_turns":0,"conversation_id":"","usage":{"input":0},"command":{"name":"usage","data":{"groups":[{"name":"g","buckets":[{"id":"p","window":"w","remaining_fraction":__VALUE__}]}]}}}"#
                .replacingOccurrences(of: "__VALUE__", with: nonJSONNumber)
            #expect(throws: AntigravityQuotaDecodingError.malformedJSON) {
                try AntigravityQuotaDecoder.decode(
                    Data(payload.utf8),
                    cliVersion: "1.1.11",
                    observedAt: observedAt
                )
            }
        }
        var missing = bucket("p", window: "w", remaining: 0.5)
        missing.removeValue(forKey: "remaining_fraction")
        #expect(throws: AntigravityQuotaDecodingError.invalidBucket) {
            try decode(groups: [group("g", buckets: [missing])])
        }
        missing["remaining_fraction"] = "0.5"
        #expect(throws: AntigravityQuotaDecodingError.invalidBucket) {
            try decode(groups: [group("g", buckets: [missing])])
        }
    }

    @Test
    func rejectsWrongCommandMissingContainersAndEmptyQuota() {
        #expect(throws: AntigravityQuotaDecodingError.unsupportedSchema) {
            try decode(groups: [], commandName: "credits")
        }
        #expect(throws: AntigravityQuotaDecodingError.unsupportedSchema) {
            try AntigravityQuotaDecoder.decode(
                Data(#"{"num_turns":0,"conversation_id":"","usage":{"input":0},"command":{"name":"usage","data":{}}}"#.utf8),
                cliVersion: "1.1.11",
                observedAt: observedAt
            )
        }
        #expect(throws: AntigravityQuotaDecodingError.noValidQuota) {
            try decode(groups: [])
        }
    }

    @Test
    func rejectsDuplicateAmbiguousOrOversizedIdentities() {
        #expect(throws: AntigravityQuotaDecodingError.duplicateBucketIdentity) {
            try decode(groups: [group("g", buckets: [
                bucket("same", window: "a", remaining: 0.1),
                bucket("same", window: "b", remaining: 0.2),
            ])])
        }
        #expect(throws: AntigravityQuotaDecodingError.invalidBucket) {
            try decode(groups: [group("g", buckets: [
                bucket("unsafe identity", window: "a", remaining: 0.1),
            ])])
        }
        #expect(throws: AntigravityQuotaDecodingError.invalidBucket) {
            try decode(groups: [group("g", buckets: [
                bucket(String(repeating: "x", count: 65), window: "a", remaining: 0.1),
            ])])
        }
    }

    @Test
    func resetIsOptionalBucketScopedAndStrictISO8601() throws {
        let withoutReset = try decode(groups: [group("g", buckets: [
            bucket("p", window: "w", remaining: 0.5),
        ])])
        #expect(withoutReset.buckets[0].resetsAt == nil)
        #expect(throws: AntigravityQuotaDecodingError.invalidBucket) {
            try decode(groups: [group("g", buckets: [
                bucket("p", window: "w", remaining: 0.5, reset: "tomorrow"),
            ])])
        }
    }

    @Test
    func rejectsProviderWorkAndUnsupportedVersion() {
        #expect(throws: AntigravityQuotaDecodingError.invalidOperationalEnvelope) {
            try decode(groups: [group("g", buckets: [
                bucket("p", window: "w", remaining: 0.5),
            ])], extras: ["num_turns": 1])
        }
        #expect(throws: AntigravityQuotaDecodingError.invalidOperationalEnvelope) {
            try decode(groups: [group("g", buckets: [
                bucket("p", window: "w", remaining: 0.5),
            ])], extras: ["task_id": "synthetic-task"])
        }
        #expect(throws: AntigravityQuotaDecodingError.unsupportedVersion) {
            try AntigravityQuotaDecoder.decode(
                fixture(groups: [group("g", buckets: [
                    bucket("p", window: "w", remaining: 0.5),
                ])]),
                cliVersion: "1.1.12",
                observedAt: observedAt
            )
        }
    }

    @Test
    func rejectsFutureOrPrivateSchemaWithoutTraversingResponseContent() {
        let validGroups = [group("g", buckets: [
            bucket("p", window: "w", remaining: 0.5),
        ])]
        #expect(throws: AntigravityQuotaDecodingError.unsupportedSchema) {
            try decode(groups: validGroups, extras: [
                "future_private": ["response": "must-not-be-inspected"],
            ])
        }

        var futureGroup = group("g", buckets: [
            bucket("p", window: "w", remaining: 0.5),
        ])
        futureGroup["future_field"] = "ignored-content"
        #expect(throws: AntigravityQuotaDecodingError.invalidBucket) {
            try decode(groups: [futureGroup])
        }

        var futureBucket = bucket("p", window: "w", remaining: 0.5)
        futureBucket["future_field"] = "ignored-content"
        #expect(throws: AntigravityQuotaDecodingError.invalidBucket) {
            try decode(groups: [group("g", buckets: [futureBucket])])
        }

        var missingName = bucket("p", window: "w", remaining: 0.5)
        missingName.removeValue(forKey: "name")
        #expect(throws: AntigravityQuotaDecodingError.invalidBucket) {
            try decode(groups: [group("g", buckets: [missingName])])
        }
    }

    private func decode(
        groups: [[String: Any]],
        commandName: String = "usage",
        extras: [String: Any] = [:]
    ) throws -> AntigravityQuotaSnapshot {
        try AntigravityQuotaDecoder.decode(
            fixture(groups: groups, commandName: commandName, extras: extras),
            cliVersion: "1.1.11",
            observedAt: observedAt
        )
    }

    private func fixture(
        groups: [[String: Any]],
        commandName: String = "usage",
        extras: [String: Any] = [:]
    ) -> Data {
        var root: [String: Any] = [
            "num_turns": 0,
            "conversation_id": "",
            "duration_seconds": 0,
            "usage": ["input_tokens": 0, "output_tokens": 0],
            "response": "Synthetic ignored response",
            "status": "success",
            "command": [
                "name": commandName,
                "data": [
                    "description": "Synthetic quota fixture",
                    "groups": groups,
                ],
            ],
        ]
        for (key, value) in extras { root[key] = value }
        return try! JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    private func group(
        _ name: String,
        buckets: [[String: Any]]
    ) -> [String: Any] {
        [
            "name": name,
            "description": "Synthetic group",
            "buckets": buckets,
        ]
    }

    private func bucket(
        _ id: String,
        window: String,
        remaining: Double,
        reset: String? = nil,
        name: String = "Synthetic label"
    ) -> [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "name": name,
            "window": window,
            "remaining_fraction": remaining,
        ]
        if let reset { value["reset_time"] = reset }
        return value
    }
}
