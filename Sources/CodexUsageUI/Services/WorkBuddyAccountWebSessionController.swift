import AppKit
import Combine
import Foundation
import WebKit

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
                    guard !(await Self.clearPersistentWebsiteData()) else {
                        return
                    }
                    self?.flowState = .failed(.websiteDataClearFailed)
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
    private var webView: WKWebView?
    private var window: NSWindow?
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var navigationTimeoutTask: Task<Void, Never>?

    var canReadOnApplicationLaunch: Bool {
        consentGranted
            && sessionMode == .persistent
            && defaults.bool(forKey: Self.sessionEstablishedKey)
    }

    public override convenience init() {
        self.init(defaults: .standard)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
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
        let browser = ensureBrowser()
        flowState = .synchronizing
        do {
            try await loadAndAwait(
                URLRequest(url: WorkBuddyAccountWebPolicy.usageURL),
                in: browser
            )
        } catch let failure as WorkBuddyAccountWebFailure {
            flowState = .failed(failure)
            return .failure(failure)
        } catch {
            flowState = .failed(.webContentUnavailable)
            return .failure(.webContentUnavailable)
        }

        guard WorkBuddyAccountWebPolicy.isExactUsagePage(browser.url) else {
            flowState = .signInRequired
            return .authenticationRequired
        }
        do {
            let value = try await browser.evaluateJavaScript(
                WorkBuddyAccountWebExtractorScript.source
            )
            guard let dictionary = value as? [String: Any] else {
                flowState = .failed(.malformedCredits)
                return .failure(.malformedCredits)
            }
            if let failure = dictionary["failure"] as? String {
                let mapped = WorkBuddyAccountWebFailure(rawValue: failure)
                    ?? .malformedCredits
                flowState = .failed(mapped)
                return .failure(mapped)
            }
            let data = try JSONSerialization.data(
                withJSONObject: dictionary,
                options: [.sortedKeys]
            )
            let payload = try JSONDecoder().decode(
                WorkBuddyAccountWebExtractionPayload.self,
                from: data
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
        } catch {
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
        flowState = await Self.clearPersistentWebsiteData()
            ? .idle
            : .failed(.websiteDataClearFailed)
    }

    private static func clearPersistentWebsiteData() async -> Bool {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.remove(
                forIdentifier: Self.persistentDataStoreIdentifier
            ) { error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    public func cancel() {
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
