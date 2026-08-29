import AppKit
import Foundation

@main
@MainActor
struct TestChannelRelaunch {
    private enum RelaunchError: Error {
        case invalidArguments
        case invalidBundle
        case terminationRejected
        case forceTerminationRejected
        case terminationTimedOut
        case liveIdentityMismatch
    }

    static func main() async throws {
        guard CommandLine.arguments.count == 5 || CommandLine.arguments.count == 6 else {
            throw RelaunchError.invalidArguments
        }
        let canonicalURL = URL(fileURLWithPath: CommandLine.arguments[1])
            .standardizedFileURL
        let expectedIdentifier = CommandLine.arguments[2]
        let expectedBuild = CommandLine.arguments[3]
        let generationInfoKey: String
        let expectedGeneration: String
        if CommandLine.arguments.count == 6 {
            generationInfoKey = CommandLine.arguments[4]
            expectedGeneration = CommandLine.arguments[5].lowercased()
        } else {
            generationInfoKey = "UMASafariHostRuntimeGenerationID"
            expectedGeneration = CommandLine.arguments[4].lowercased()
        }
        guard generationInfoKey == "UMASafariHostRuntimeGenerationID"
                || generationInfoKey == "UMARuntimeGenerationID"
        else {
            throw RelaunchError.invalidArguments
        }
        guard let bundle = Bundle(url: canonicalURL),
              bundle.bundleIdentifier == expectedIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                == expectedBuild,
              (bundle.object(forInfoDictionaryKey: generationInfoKey)
                as? String)?.lowercased() == expectedGeneration
        else {
            throw RelaunchError.invalidBundle
        }

        func runningApplications() -> [NSRunningApplication] {
            NSRunningApplication.runningApplications(
                withBundleIdentifier: expectedIdentifier
            ).filter { !$0.isTerminated }
        }
        let prior = runningApplications()
        for application in prior where !application.isTerminated {
            guard application.terminate() else {
                throw RelaunchError.terminationRejected
            }
        }
        let gracefulDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !runningApplications().isEmpty {
            guard ContinuousClock.now < gracefulDeadline else { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        for application in runningApplications() {
            guard application.forceTerminate() else {
                throw RelaunchError.forceTerminationRejected
            }
        }
        let forcedDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !runningApplications().isEmpty {
            guard ContinuousClock.now < forcedDeadline else {
                throw RelaunchError.terminationTimedOut
            }
            try await Task.sleep(for: .milliseconds(100))
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        let launched = try await NSWorkspace.shared.openApplication(
            at: canonicalURL,
            configuration: configuration
        )
        guard launched.bundleIdentifier == expectedIdentifier,
              launched.bundleURL?.standardizedFileURL == canonicalURL,
              !launched.isTerminated,
              let liveBundle = launched.bundleURL.flatMap(Bundle.init(url:)),
              liveBundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                == expectedBuild,
              (liveBundle.object(forInfoDictionaryKey: generationInfoKey)
                    as? String)?.lowercased()
                == expectedGeneration
        else {
            throw RelaunchError.liveIdentityMismatch
        }
        print(
            "MUTABLE_TEST_APP_RELAUNCHED "
                + "bundle=\(expectedIdentifier) build=\(expectedBuild) "
                + "generation=\(expectedGeneration) pid=\(launched.processIdentifier)"
        )
    }
}
