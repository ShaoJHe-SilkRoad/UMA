import AppKit
import Combine
import Foundation
import WebKit

struct WorkBuddyAccountWebExtractionAttempt: Equatable, Sendable {
    let data: Data
    let failure: WorkBuddyAccountWebFailure?
}

@MainActor
enum WorkBuddyAccountWebExtractionReadiness {
    static let maximumAttempts = 20
    static let delay = Duration.milliseconds(250)

    static func evaluate(
        isCurrent: () -> Bool,
        read: () async throws -> WorkBuddyAccountWebExtractionAttempt,
        wait: (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) async throws -> WorkBuddyAccountWebExtractionAttempt? {
        for attempt in 0..<maximumAttempts {
            guard isCurrent() else { return nil }
            let result = try await read()
            guard isCurrent() else { return nil }
            let isStillRendering =
                result.failure == .unexpectedPage
                    || result.failure == .malformedCredits
            guard isStillRendering, attempt + 1 < maximumAttempts else {
                return result
            }
            try await wait(delay)
        }
        return nil
    }
}

@MainActor
enum WorkBuddyOwnedWebsiteDataClearer {
    static func clear<Record>(
        fetch: () async -> [Record],
        remove: ([Record]) async -> Void
    ) async -> Bool {
        let records = await fetch()
        await remove(records)
        return await fetch().isEmpty
    }
}

@MainActor
public final class WorkBuddyAccountWebSessionController: NSObject, ObservableObject {
    public static let disclosureVersion =
        WorkBuddyAccountWebConsentRecord.currentDisclosureVersion

    @Published public private(set) var flowState: WorkBuddyAccountWebFlowState = .idle
    @Published public private(set) var consentGranted = false
    @Published public private(set) var lastSynchronizedAt: Date?
    @Published public var sessionMode: WorkBuddyAccountWebSessionMode {
        didSet {
            guard oldValue != sessionMode else { return }
            defaults.removeObject(forKey: Self.sessionEstablishedKey)
            persistConsentIfGranted()
            releaseBrowser()
            if oldValue == .persistent && sessionMode == .nonpersistent {
                Task { @MainActor [weak self] in
                    guard let self,
                          !(await websiteDataClearer()) else {
                        return
                    }
                    flowState = .failed(.websiteDataClearFailed)
                }
            }
        }
    }

    private static let consentKey = "workbuddy.accountWebSync.consent.v1"
    static let sessionEstablishedKey =
        "workbuddy.accountWebSync.establishedPersistentSession.v1"
    private static let persistentDataStoreIdentifier = UUID(
        uuidString: "99F5E198-BD63-4450-8EE1-2447F27A5F2D"
    )!
    private let defaults: UserDefaults
    private let websiteDataClearer: @MainActor () async -> Bool
    private var webView: WKWebView?
    private var window: NSWindow?
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var navigationTimeoutTask: Task<Void, Never>?
    private var readGeneration: UInt64 = 0

    var canReadOnApplicationLaunch: Bool {
        consentGranted
            && sessionMode == .persistent
            && defaults.bool(forKey: Self.sessionEstablishedKey)
    }

    public override convenience init() {
        self.init(defaults: .standard)
    }

    init(
        defaults: UserDefaults,
        websiteDataClearer: (@MainActor () async -> Bool)? = nil
    ) {
        self.defaults = defaults
        self.websiteDataClearer = websiteDataClearer ?? {
            await WorkBuddyAccountWebSessionController.clearPersistentWebsiteData()
        }
        let record: WorkBuddyAccountWebConsentRecord? = defaults.data(
            forKey: Self.consentKey
        ).flatMap {
            try? JSONDecoder().decode(WorkBuddyAccountWebConsentRecord.self, from: $0)
        }
        if let record,
           record.disclosureVersion == Self.disclosureVersion {
            consentGranted = true
            sessionMode = record.sessionMode
            if record.sessionMode != .persistent {
                defaults.removeObject(forKey: Self.sessionEstablishedKey)
            }
        } else {
            consentGranted = false
            sessionMode = .nonpersistent
            defaults.removeObject(forKey: Self.sessionEstablishedKey)
        }
        super.init()
    }

    public func grantConsent() {
        consentGranted = true
        if sessionMode != .persistent {
            defaults.removeObject(forKey: Self.sessionEstablishedKey)
        }
        persistConsentIfGranted()
        flowState = .idle
    }

    public func connect() {
        guard consentGranted else {
            flowState = .consentRequired
            return
        }
        let browser = ensureBrowser()
        showWindow()
        flowState = .opening
        browser.load(URLRequest(url: WorkBuddyAccountWebPolicy.usageURL))
    }

    public func openAccountUsage() {
        connect()
    }

    func readCurrentCredits() async -> WorkBuddyAccountWebReadResult {
        guard consentGranted else {
            flowState = .consentRequired
            return .failure(.consentRequired)
        }
        readGeneration &+= 1
        let generation = readGeneration
        let browser = ensureBrowser()
        flowState = .synchronizing
        do {
            try await loadAndAwait(
                URLRequest(url: WorkBuddyAccountWebPolicy.usageURL),
                in: browser
            )
        } catch let failure as WorkBuddyAccountWebFailure {
            guard readGeneration == generation else {
                return .failure(.webContentUnavailable)
            }
            flowState = .failed(failure)
            return .failure(failure)
        } catch {
            guard readGeneration == generation else {
                return .failure(.webContentUnavailable)
            }
            flowState = .failed(.webContentUnavailable)
            return .failure(.webContentUnavailable)
        }

        guard readGeneration == generation else {
            return .failure(.webContentUnavailable)
        }
        guard WorkBuddyAccountWebPolicy.isExactUsagePage(browser.url) else {
            flowState = .signInRequired
            return .authenticationRequired
        }
        do {
            let attempt = try await WorkBuddyAccountWebExtractionReadiness.evaluate(
                isCurrent: { [weak self] in
                    self?.readGeneration == generation
                },
                read: {
                    guard WorkBuddyAccountWebPolicy.isExactUsagePage(browser.url)
                    else {
                        throw WorkBuddyAccountWebFailure.authenticationRequired
                    }
                    let value = try await browser.evaluateJavaScript(
                        WorkBuddyAccountWebExtractorScript.source
                    )
                    guard let dictionary = value as? [String: Any] else {
                        throw WorkBuddyAccountWebFailure.malformedCredits
                    }
                    let data = try JSONSerialization.data(
                        withJSONObject: dictionary,
                        options: [.sortedKeys]
                    )
                    return WorkBuddyAccountWebExtractionAttempt(
                        data: data,
                        failure: (dictionary["failure"] as? String).flatMap(
                            WorkBuddyAccountWebFailure.init(rawValue:)
                        )
                    )
                }
            )
            guard let attempt else {
                return .failure(.webContentUnavailable)
            }
            if let failure = attempt.failure {
                flowState = .failed(failure)
                return .failure(failure)
            }
            let payload = try JSONDecoder().decode(
                WorkBuddyAccountWebExtractionPayload.self,
                from: attempt.data
            )
            let result = WorkBuddyAccountWebExtractor.validate(
                payload,
                observedAt: Date()
            )
            switch result {
            case let .success(reading):
                lastSynchronizedAt = reading.observedAt
                if sessionMode == .persistent {
                    defaults.set(true, forKey: Self.sessionEstablishedKey)
                }
                flowState = .connected
            case .authenticationRequired:
                defaults.removeObject(forKey: Self.sessionEstablishedKey)
                flowState = .signInRequired
            case let .failure(failure):
                flowState = .failed(failure)
            }
            return result
        } catch WorkBuddyAccountWebFailure.authenticationRequired {
            guard readGeneration == generation else {
                return .failure(.webContentUnavailable)
            }
            defaults.removeObject(forKey: Self.sessionEstablishedKey)
            flowState = .signInRequired
            return .authenticationRequired
        } catch {
            guard readGeneration == generation else {
                return .failure(.webContentUnavailable)
            }
            flowState = .failed(.malformedCredits)
            return .failure(.malformedCredits)
        }
    }

    func disconnectAndClearOwnedWebsiteData() async {
        releaseBrowser()
        lastSynchronizedAt = nil
        consentGranted = false
        defaults.removeObject(forKey: Self.consentKey)
        defaults.removeObject(forKey: Self.sessionEstablishedKey)
        flowState = await websiteDataClearer()
            ? .idle
            : .failed(.websiteDataClearFailed)
    }

    private static func clearPersistentWebsiteData() async -> Bool {
        let dataStore = WKWebsiteDataStore(
            forIdentifier: Self.persistentDataStoreIdentifier
        )
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        return await WorkBuddyOwnedWebsiteDataClearer.clear(
            fetch: {
                await withCheckedContinuation { continuation in
                    dataStore.fetchDataRecords(ofTypes: dataTypes) { records in
                        continuation.resume(returning: records)
                    }
                }
            },
            remove: { records in
                await withCheckedContinuation { continuation in
                    dataStore.removeData(ofTypes: dataTypes, for: records) {
                        continuation.resume()
                    }
                }
            }
        )
    }

    public func cancel() {
        readGeneration &+= 1
        webView?.stopLoading()
        navigationTimeoutTask?.cancel()
        navigationTimeoutTask = nil
        navigationContinuation?.resume(
            throwing: WorkBuddyAccountWebFailure.webContentUnavailable
        )
        navigationContinuation = nil
        window?.orderOut(nil)
        flowState = .idle
    }

    public func tearDown() {
        cancel()
        releaseBrowser()
    }

    private func persistConsentIfGranted() {
        guard consentGranted else { return }
        let record = WorkBuddyAccountWebConsentRecord(
            disclosureVersion: Self.disclosureVersion,
            acceptedAt: Date(),
            sessionMode: sessionMode
        )
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Self.consentKey)
        }
    }

    private func ensureBrowser() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = sessionMode == .persistent
            ? WKWebsiteDataStore(
                forIdentifier: Self.persistentDataStoreIdentifier
            )
            : .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let browser = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 860, height: 680),
            configuration: configuration
        )
        browser.navigationDelegate = self
        browser.uiDelegate = self
        webView = browser
        return browser
    }

    private func showWindow() {
        let browser = ensureBrowser()
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            created.title = "WorkBuddy Account Web Sync"
            created.contentView = browser
            created.center()
            created.isReleasedWhenClosed = false
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadAndAwait(
        _ request: URLRequest,
        in browser: WKWebView
    ) async throws {
        guard navigationContinuation == nil else {
            throw WorkBuddyAccountWebFailure.webContentUnavailable
        }
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            navigationTimeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.finishNavigation(
                    failure: .timedOut
                )
            }
            browser.load(request)
        }
    }

    private func finishNavigation(
        failure: WorkBuddyAccountWebFailure? = nil
    ) {
        navigationTimeoutTask?.cancel()
        navigationTimeoutTask = nil
        guard let continuation = navigationContinuation else { return }
        navigationContinuation = nil
        if let failure {
            continuation.resume(throwing: failure)
        } else {
            continuation.resume()
        }
    }

    private func releaseBrowser() {
        readGeneration &+= 1
        navigationTimeoutTask?.cancel()
        navigationTimeoutTask = nil
        navigationContinuation?.resume(
            throwing: WorkBuddyAccountWebFailure.webContentUnavailable
        )
        navigationContinuation = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        webView = nil
    }
}

@MainActor
extension WorkBuddyAccountWebSessionController: WKNavigationDelegate {
    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable
            (WKNavigationActionPolicy) -> Void
    ) {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        switch WorkBuddyAccountWebPolicy.navigationDecision(
            for: navigationAction.request.url,
            isMainFrame: isMainFrame
        ) {
        case .allow:
            decisionHandler(.allow)
        case .cancel:
            decisionHandler(.cancel)
            if isMainFrame {
                flowState = .failed(.invalidNavigation)
                finishNavigation(failure: .invalidNavigation)
            }
        case let .confirmExternalHost(host):
            let alert = NSAlert()
            alert.messageText = "Allow external sign-in host?"
            alert.informativeText = host
            alert.addButton(withTitle: "Allow Once")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
                flowState = .failed(.invalidNavigation)
                finishNavigation(failure: .invalidNavigation)
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        flowState = WorkBuddyAccountWebPolicy.isExactUsagePage(webView.url)
            ? .readyToSync
            : .signInRequired
        finishNavigation()
    }

    public func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        flowState = .failed(.webContentUnavailable)
        finishNavigation(failure: .webContentUnavailable)
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        flowState = .failed(.webContentUnavailable)
        finishNavigation(failure: .webContentUnavailable)
    }
}

@MainActor
extension WorkBuddyAccountWebSessionController: WKUIDelegate {
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else { return nil }
        webView.load(URLRequest(url: url))
        return nil
    }
}
