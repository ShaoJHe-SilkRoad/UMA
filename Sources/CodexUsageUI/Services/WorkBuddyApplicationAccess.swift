@preconcurrency import AppKit
import CryptoKit
import Foundation
import Security

@MainActor
protocol WorkBuddyApplicationAccessing: AnyObject {
    func discover() -> WorkBuddyInstallationStatus
    func openOrActivate(_ application: WorkBuddyInstalledApplication) async
        -> WorkBuddyApplicationLaunchResult
    func observeLifecycle(_ action: @escaping @MainActor () -> Void) -> NSObjectProtocol
    func removeLifecycleObserver(_ observer: NSObjectProtocol)
}

struct WorkBuddyApplicationCandidate: Equatable, Sendable {
    let url: URL
    let bundleIdentifier: String?
    let displayName: String
    let version: String?
    let build: String?
    let signatureTrust: WorkBuddySignatureTrust
    let installationIdentity: String
}

@MainActor
final class WorkBuddyApplicationAccess: WorkBuddyApplicationAccessing {
    nonisolated static let expectedBundleIdentifier = "com.workbuddy.workbuddy"
    nonisolated static let expectedTeamIdentifier = "FN2V63AD2J"
    nonisolated static let fallbackURL = URL(
        fileURLWithPath: "/Applications/WorkBuddy.app",
        isDirectory: true
    )

    private let workspace: NSWorkspace
    private let fileManager: FileManager

    init(
        workspace: NSWorkspace = .shared,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func discover() -> WorkBuddyInstallationStatus {
        var candidateURLs: [URL] = []
        if let registered = workspace.urlForApplication(
            withBundleIdentifier: Self.expectedBundleIdentifier
        ) {
            candidateURLs.append(registered)
        }
        candidateURLs.append(Self.fallbackURL)

        var seen: Set<String> = []
        var candidates: [WorkBuddyApplicationCandidate] = []
        for url in candidateURLs {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted,
                  fileManager.fileExists(atPath: standardized.path)
            else {
                continue
            }
            guard let bundle = Bundle(url: standardized) else {
                candidates.append(
                    WorkBuddyApplicationCandidate(
                        url: standardized,
                        bundleIdentifier: nil,
                        displayName: standardized.deletingPathExtension()
                            .lastPathComponent,
                        version: nil,
                        build: nil,
                        signatureTrust: .unverifiable,
                        installationIdentity: Self.installationIdentity(
                            at: standardized,
                            bundle: nil
                        )
                    )
                )
                continue
            }
            let name = (bundle.object(
                forInfoDictionaryKey: "CFBundleDisplayName"
            ) as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? "WorkBuddy"
            candidates.append(
                WorkBuddyApplicationCandidate(
                    url: standardized,
                    bundleIdentifier: bundle.bundleIdentifier,
                    displayName: name,
                    version: bundle.object(
                        forInfoDictionaryKey: "CFBundleShortVersionString"
                    ) as? String,
                    build: bundle.object(
                        forInfoDictionaryKey: "CFBundleVersion"
                    ) as? String,
                    signatureTrust: Self.signatureTrust(at: standardized),
                    installationIdentity: Self.installationIdentity(
                        at: standardized,
                        bundle: bundle
                    )
                )
            )
        }
        return Self.resolve(candidates: candidates)
    }

    nonisolated static func resolve(
        candidates: [WorkBuddyApplicationCandidate]
    ) -> WorkBuddyInstallationStatus {
        for candidate in candidates
        where candidate.bundleIdentifier == expectedBundleIdentifier {
            return .available(
                WorkBuddyInstalledApplication(
                    url: candidate.url,
                    bundleIdentifier: expectedBundleIdentifier,
                    displayName: candidate.displayName,
                    version: candidate.version,
                    build: candidate.build,
                    signatureTrust: candidate.signatureTrust,
                    installationIdentity: candidate.installationIdentity
                )
            )
        }
        if let invalid = candidates.first {
            return .invalidBundleIdentity(found: invalid.bundleIdentifier)
        }
        return .notInstalled
    }

    func openOrActivate(
        _ application: WorkBuddyInstalledApplication
    ) async -> WorkBuddyApplicationLaunchResult {
        let expectedURL = application.url
        let runningWithExpectedIdentifier = workspace.runningApplications.filter {
            $0.bundleIdentifier == Self.expectedBundleIdentifier
        }
        if let running = runningWithExpectedIdentifier.first(where: {
            Self.applicationURLsMatch($0.bundleURL, expectedURL)
        }) {
            return running.activate(options: [.activateAllWindows])
                ? .activated
                : .failed
        }
        guard runningWithExpectedIdentifier.isEmpty else {
            return .failed
        }

        return await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            workspace.openApplication(
                at: application.url,
                configuration: configuration
            ) { runningApplication, error in
                if let cocoaError = error as? CocoaError,
                   cocoaError.code == .userCancelled {
                    continuation.resume(returning: .denied)
                } else if error != nil
                    || runningApplication == nil
                    || !Self.applicationURLsMatch(
                        runningApplication?.bundleURL,
                        expectedURL
                    ) {
                    continuation.resume(returning: .failed)
                } else {
                    continuation.resume(returning: .launched)
                }
            }
        }
    }

    func observeLifecycle(
        _ action: @escaping @MainActor () -> Void
    ) -> NSObjectProtocol {
        let center = workspace.notificationCenter
        return center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication,
                  application.bundleIdentifier == Self.expectedBundleIdentifier
            else {
                return
            }
            Task { @MainActor in action() }
        }
    }

    func removeLifecycleObserver(_ observer: NSObjectProtocol) {
        workspace.notificationCenter.removeObserver(observer)
    }

    nonisolated static func applicationURLsMatch(
        _ candidate: URL?,
        _ expected: URL
    ) -> Bool {
        guard let candidate else { return false }
        return candidate.resolvingSymlinksInPath().standardizedFileURL
            == expected.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func installationIdentity(
        at url: URL,
        bundle: Bundle?
    ) -> String {
        var fields = [
            url.resolvingSymlinksInPath().standardizedFileURL.path,
            bundle?.bundleIdentifier ?? "",
            bundle?.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "",
            bundle?.object(forInfoDictionaryKey: "CFBundleVersion")
                as? String ?? ""
        ]
        for resourceURL in [url, bundle?.executableURL].compactMap({ $0 }) {
            if let values = try? resourceURL.resourceValues(
                forKeys: [
                    .fileResourceIdentifierKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ]
            ) {
                fields.append(String(describing: values.fileResourceIdentifier))
                fields.append(String(values.fileSize ?? -1))
                fields.append(
                    values.contentModificationDate.map {
                        String($0.timeIntervalSince1970)
                    } ?? ""
                )
            }
        }
        let digest = SHA256.hash(
            data: Data(fields.joined(separator: "\u{0}").utf8)
        )
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func signatureTrust(at url: URL) -> WorkBuddySignatureTrust {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            url as CFURL,
            SecCSFlags(),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            return .unverifiable
        }
        let flags = SecCSFlags(
            rawValue: kSecCSCheckAllArchitectures
                | kSecCSStrictValidate
                | kSecCSCheckNestedCode
        )
        let status = SecStaticCodeCheckValidity(
            staticCode,
            flags,
            nil
        )
        if status == errSecSuccess {
            var signingInformation: CFDictionary?
            let informationStatus = SecCodeCopySigningInformation(
                staticCode,
                SecCSFlags(rawValue: kSecCSSigningInformation),
                &signingInformation
            )
            guard informationStatus == errSecSuccess,
                  let information = signingInformation as? [CFString: Any],
                  information[kSecCodeInfoTeamIdentifier] as? String
                    == expectedTeamIdentifier
            else {
                return .rejected
            }
            return .trusted
        }
        return status == errSecCSUnsigned || status == errSecCSSignatureFailed
            ? .rejected
            : .unverifiable
    }
}
