import Foundation

extension AppLanguage {
    var claudeCodeName: String { "Claude Code" }

    var claudeBrowserSourceLabel: String {
        switch self {
        case .simplifiedChinese: "Claude 本地智能模式 · 按需精确同步"
        case .english: "Claude Local Smart Mode · on-demand Accuracy Sync"
        }
    }

    var claudeEnableIntegration: String {
        switch self {
        case .simplifiedChinese: "连接 Claude"
        case .english: "Connect Claude"
        }
    }

    var claudeNotConfigured: String {
        switch self {
        case .simplifiedChinese: "未连接"
        case .english: "Disconnected"
        }
    }

    var claudeConnected: String {
        switch self {
        case .simplifiedChinese: "本地智能模式已连接"
        case .english: "Local Smart Mode connected"
        }
    }

    var claudeCached: String {
        switch self {
        case .simplifiedChinese: "已缓存"
        case .english: "Cached"
        }
    }

    var claudeStale: String {
        switch self {
        case .simplifiedChinese: "较早数据"
        case .english: "Stale"
        }
    }

    var claudeFresh: String {
        switch self {
        case .simplifiedChinese: "新鲜"
        case .english: "Fresh"
        }
    }

    var claudeUpdatesPageDriven: String {
        switch self {
        case .simplifiedChinese: "本地活动或桌面端计划缓存的估算值以 ≈ 标记；不会显示推测的重置时间。"
        case .english: "Local-activity or Desktop plan-cache estimates are labeled ≈; no reset time is inferred."
        }
    }

    var claudeDisableIntegration: String {
        switch self {
        case .simplifiedChinese: "断开 Claude"
        case .english: "Disconnect Claude"
        }
    }

    var claudeSourceTransparency: String {
        switch self {
        case .simplifiedChinese: "来源透明度"
        case .english: "Source Transparency"
        }
    }

    var claudeConsentDisclosure: String {
        switch self {
        case .simplifiedChinese:
            "在受支持的 Claude Code 终端或 IDE 环境中，UMA 可以安装一个可恢复的状态栏中继，仅保留官方 5 小时/7 天用量与重置字段。经您同意，UMA 还可在内存中一次处理一条有界的本地 Claude Code JSONL 记录，立即丢弃提示、回复和会话内容，仅保留允许的用量计数、模型系列分类与活动时间戳，用于生成与官方精确配额不同、以 ≈ 标记的本地活动估算。Claude Desktop 未提供稳定的逐回复本地活动信号；它只能从版本锁定的本地计划缓存提供以 ≈ 标记的估算剩余量；组织信息与历史会被丢弃，也不会推测重置时间。路径、身份与凭据不会持久化。按需“精确同步”才会临时打开 Safari，创建并关闭一个任务自有标签页；不会启用浏览器定时器或永久标签页。"
        case .english:
            "On supported Claude Code terminal or IDE surfaces, UMA can install a reversible status-line relay that retains only official five-hour/seven-day usage and reset fields. With your consent, UMA may also process one bounded local Claude Code JSONL record at a time in memory, immediately discard prompts, responses, and session content, and retain only allowlisted usage counts, model-family classification, and an activity timestamp to produce an ≈ local-activity estimate distinct from official exact quota. Claude Desktop does not expose a stable local activity signal, including a per-response signal; it may provide only ≈-labeled remaining estimates from a version-pinned local plan cache; organization and history are discarded, and no reset time is inferred. Paths, identity, and credentials are not persisted. Safari opens only for an explicit Accuracy Sync, which creates and closes one task-owned temporary tab; no browser timer or permanent tab is enabled."
        }
    }

    func claudeBrowserActionStatus(_ action: ClaudeSettingsAction) -> String {
        switch (self, action) {
        case (.english, .checking): "Checking Local Smart Mode…"
        case (.english, .connecting): "Installing Local Smart Mode…"
        case (.english, .refreshing): "Refreshing…"
        case (.english, .checkingCompanion): "Checking Browser Companion…"
        case (.english, .repairing): "Repairing status-line integration…"
        case (.english, .requestingSiteAccess): "Requesting Safari Site Access…"
        case (.english, .retryingSiteAccess): "Retrying Safari Site Access…"
        case (.english, .disconnecting): "Disconnecting…"
        case (.simplifiedChinese, .checking): "正在检查本地智能模式…"
        case (.simplifiedChinese, .connecting): "正在安装本地智能模式…"
        case (.simplifiedChinese, .refreshing): "正在刷新…"
        case (.simplifiedChinese, .checkingCompanion): "正在检查浏览器伴侣…"
        case (.simplifiedChinese, .repairing): "正在修复状态栏集成…"
        case (.simplifiedChinese, .requestingSiteAccess): "正在请求 Safari 网站访问权限…"
        case (.simplifiedChinese, .retryingSiteAccess): "正在重试 Safari 网站访问权限…"
        case (.simplifiedChinese, .disconnecting): "正在断开…"
        }
    }

    func claudeBrowserError(_ error: ClaudeSettingsSafeError) -> String {
        switch (self, error) {
        case (.english, .routeChanged):
            "Claude's Usage page changed. Accuracy Sync stopped safely."
        case (.english, .timedOut):
            "Claude Accuracy Sync timed out."
        case (.english, .ambiguousUsagePage):
            "Claude Accuracy Sync rejected an ambiguous Usage page."
        case (.simplifiedChinese, .routeChanged):
            "Claude 使用量页面已更改；精确同步已安全停止。"
        case (.simplifiedChinese, .timedOut):
            "Claude 精确同步已超时。"
        case (.simplifiedChinese, .ambiguousUsagePage):
            "Claude 精确同步已拒绝含糊的使用量页面。"
        }
    }

    func claudeLiveLinkStatus(_ stage: ClaudeLiveLinkStageReason?) -> String {
        switch (self, stage) {
        case (.english, .localStatusLinePending):
            "Waiting for an official Claude Code status-line update."
        case (.simplifiedChinese, .localStatusLinePending):
            "正在等待 Claude Code 官方状态栏更新。"
        case (.english, .localStatusLineRejected):
            "The latest official status-line update was rejected safely."
        case (.simplifiedChinese, .localStatusLineRejected):
            "最近的官方状态栏更新已安全拒绝。"
        case (.english, .localActivityDetectedAwaitingExactAnchor):
            "Activity detected — awaiting exact usage anchor."
        case (.simplifiedChinese, .localActivityDetectedAwaitingExactAnchor):
            "已检测到活动 — 正在等待精确用量锚点。"
        case (.english, .localCodeActivityDetectedDesktopUnavailable):
            "Claude Code activity detected — awaiting an exact usage anchor. Claude Desktop activity detection is unavailable."
        case (.simplifiedChinese, .localCodeActivityDetectedDesktopUnavailable):
            "已检测到 Claude Code 活动 — 正在等待精确用量锚点。Claude Desktop 活动检测不可用。"
        case (.english, .localCallbackWithoutQuotaWindows):
            "Local activity received. Automatic exact quota is not available yet."
        case (.simplifiedChinese, .localCallbackWithoutQuotaWindows):
            "已收到本地活动；自动精确配额尚不可用。"
        case (.english, .desktopActivitySignalUnavailable):
            "Claude Desktop does not expose a stable local activity signal. UMA can show only an available ≈ plan-cache estimate; use Accuracy Sync for current exact usage."
        case (.simplifiedChinese, .desktopActivitySignalUnavailable):
            "Claude Desktop 未提供稳定的本地活动信号。UMA 只能显示可用的 ≈ 计划缓存估算；请使用精确同步获取当前精确用量。"
        case (.english, .accuracyInventoryRestartRequired):
            "The Test App update is ready. Restart Safari once to finish loading it."
        case (.simplifiedChinese, .accuracyInventoryRestartRequired):
            "测试版应用更新已就绪。请重启 Safari 一次以完成加载。"
        case (.english, .accuracyInventoryLoading):
            "Safari is still loading the Browser Companion."
        case (.simplifiedChinese, .accuracyInventoryLoading):
            "Safari 仍在加载浏览器伴侣。"
        case (.english, .accuracyCompanionStarting):
            "The Browser Companion is starting."
        case (.simplifiedChinese, .accuracyCompanionStarting):
            "浏览器伴侣正在启动。"
        case (.english, .accuracyProtocolMismatch):
            "The Browser Companion version does not match the Test App."
        case (.simplifiedChinese, .accuracyProtocolMismatch):
            "浏览器伴侣版本与测试版应用不匹配。"
        case (.english, .accuracyCompanionUnavailable):
            "The Browser Companion is unavailable."
        case (.simplifiedChinese, .accuracyCompanionUnavailable):
            "浏览器伴侣不可用。"
        case (.english, .accuracyBrowserUnavailable):
            "Safari is unavailable. Accuracy Sync will not start until Safari is ready."
        case (.simplifiedChinese, .accuracyBrowserUnavailable):
            "Safari 不可用。Safari 就绪前精确同步不会启动。"
        case (.english, .accuracyHandshakeUnavailable):
            "Accuracy Sync could not verify the Browser Companion."
        case (.simplifiedChinese, .accuracyHandshakeUnavailable):
            "精确同步无法验证浏览器伴侣。请检查已启用的伴侣后重试。"
        case (.english, .accuracyWorkDispatchFailed):
            "Accuracy Sync could not start the usage check. No page content was read."
        case (.simplifiedChinese, .accuracyWorkDispatchFailed):
            "精确同步无法开始使用量检查，未读取页面内容。"
        case (.english, .accuracyRequestMismatch):
            "Accuracy Sync ignored an unrelated response and stopped safely."
        case (.simplifiedChinese, .accuracyRequestMismatch):
            "精确同步已忽略不属于本次操作的响应并安全停止。"
        case (.english, .accuracyPermissionRequired):
            "Accuracy Sync needs access to claude.ai. Allow access in Safari Extensions, then try again."
        case (.simplifiedChinese, .accuracyPermissionRequired):
            "精确同步需要访问 claude.ai。请在 Safari 扩展中允许访问后重试。"
        case (.english, .accuracySignInRequired):
            "Sign in to Claude in Safari, then try Accuracy Sync again."
        case (.simplifiedChinese, .accuracySignInRequired):
            "请先在 Safari 中登录 Claude，再次尝试精确同步。"
        case (.english, .accuracyRouteRejected):
            "Claude's Usage page could not be verified. Accuracy Sync stopped safely."
        case (.simplifiedChinese, .accuracyRouteRejected):
            "无法验证 Claude 使用量页面；精确同步已安全停止。"
        case (.english, .accuracyUsageUnavailable):
            "Claude's current usage was not available on the verified Usage page."
        case (.simplifiedChinese, .accuracyUsageUnavailable):
            "已验证的 Claude 使用量页面暂未提供当前使用量。"
        case (.english, .accuracyTabUnavailable):
            "Accuracy Sync could not open its temporary Usage tab."
        case (.simplifiedChinese, .accuracyTabUnavailable):
            "精确同步无法打开临时使用量标签页。"
        case (.english, .accuracyOwnedTabLost):
            "Accuracy Sync lost its temporary Usage tab and stopped without touching other tabs."
        case (.simplifiedChinese, .accuracyOwnedTabLost):
            "精确同步丢失了临时使用量标签页，并在不影响其他标签页的情况下停止。"
        default:
            switch self {
            case .english: "Waiting for the first valid Claude Code status-line update"
            case .simplifiedChinese: "等待 Claude Code 第一次有效状态栏更新"
            }
        }
    }

    var claudeRetainedAccuracyAwaitingLocalReceipt: String {
        switch self {
        case .english:
            "Current exact Accuracy Sync value is retained while the official local status-line anchor is unavailable."
        case .simplifiedChinese:
            "当前精确同步值仍有效；官方本地状态栏锚点暂不可用。"
        }
    }

    func claudeEstimateConfidence(_ value: String?) -> String {
        let label: String = switch (self, value) {
        case (.english, "high"): "High"
        case (.english, "medium"): "Medium"
        case (.english, "low"): "Low"
        case (.english, "exact"): "Exact value — estimate not active"
        case (.english, _): "Not yet available"
        case (.simplifiedChinese, "high"): "高"
        case (.simplifiedChinese, "medium"): "中"
        case (.simplifiedChinese, "low"): "低"
        case (.simplifiedChinese, "exact"): "精确值 — 未使用估算"
        case (.simplifiedChinese, _): "尚不可用"
        }
        return switch self {
        case .english: "Estimate confidence: \(label)"
        case .simplifiedChinese: "估算置信度：\(label)"
        }
    }

    func claudeLastExact(_ date: Date?) -> String {
        guard let date else {
            return switch self {
            case .english: "Last exact observation: Not yet received"
            case .simplifiedChinese: "最近精确观测：尚未收到"
            }
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        let value = formatter.localizedString(for: date, relativeTo: Date())
        return switch self {
        case .english: "Last exact observation: \(value)"
        case .simplifiedChinese: "最近精确观测：\(value)"
        }
    }

    func claudeLocalSmartStatus(
        _ state: ClaudeLocalSmartState,
        stage: ClaudeLiveLinkStageReason?
    ) -> String {
        switch (self, state) {
        case let (.english, .exactLocal(date)):
            "Exact local usage available. \(claudeUpdated(date))"
        case let (.simplifiedChinese, .exactLocal(date)):
            "本地精确用量可用。\(claudeUpdated(date))"
        case let (.english, .estimated(date)):
            "≈ Local estimate available. \(claudeUpdated(date))"
        case let (.simplifiedChinese, .estimated(date)):
            "≈ 本地估算可用。\(claudeUpdated(date))"
        case let (.english, .staleUnsupported(date)):
            date.map { "Local estimate is stale or unsupported. \(claudeUpdated($0))" }
                ?? "Local estimate is stale or unsupported."
        case let (.simplifiedChinese, .staleUnsupported(date)):
            date.map { "本地估算已过期或不受支持。\(claudeUpdated($0))" }
                ?? "本地估算已过期或不受支持。"
        case (.english, .unavailable):
            stage.map { claudeLiveLinkStatus($0) }
                ?? "Local Smart usage is not available yet."
        case (.simplifiedChinese, .unavailable):
            stage.map { claudeLiveLinkStatus($0) } ?? "本地智能用量尚不可用。"
        case (.english, .error):
            "Local Smart input was rejected safely."
        case (.simplifiedChinese, .error):
            "本地智能输入已安全拒绝。"
        }
    }

    func claudeBrowserAccuracyStatus(
        _ state: ClaudeBrowserAccuracyState,
        stage: ClaudeLiveLinkStageReason?
    ) -> String {
        switch (self, state) {
        case (.english, .notConfigured):
            "Accuracy Sync is not configured."
        case (.simplifiedChinese, .notConfigured):
            "精确同步尚未配置。"
        case (.english, .consentRequired):
            "Consent is required before Accuracy Sync can access Claude."
        case (.simplifiedChinese, .consentRequired):
            "精确同步访问 Claude 前需要同意。"
        case (.english, .ready):
            "Accuracy Sync is ready."
        case (.simplifiedChinese, .ready):
            "精确同步已就绪。"
        case (.english, .companionUnavailable):
            stage.map { claudeLiveLinkStatus($0) } ?? "Accuracy Sync is unavailable."
        case (.simplifiedChinese, .companionUnavailable):
            stage.map { claudeLiveLinkStatus($0) } ?? "精确同步不可用。"
        case (.english, .updatePendingRestart):
            "Browser Companion update ready — restart Safari once."
        case (.simplifiedChinese, .updatePendingRestart):
            "浏览器伴侣更新已就绪 — 请重启 Safari 一次。"
        case (.english, .syncing):
            "Accuracy Sync is running."
        case (.simplifiedChinese, .syncing):
            "正在进行精确同步。"
        case let (.english, .exactAnchorAvailable(date)):
            "Exact Accuracy Sync anchor available. \(claudeUpdated(date))"
        case let (.simplifiedChinese, .exactAnchorAvailable(date)):
            "精确同步锚点可用。\(claudeUpdated(date))"
        case (.english, .error):
            stage.map { claudeLiveLinkStatus($0) } ?? "Accuracy Sync stopped safely."
        case (.simplifiedChinese, .error):
            stage.map { claudeLiveLinkStatus($0) } ?? "精确同步已安全停止。"
        }
    }

    func claudeCompanionRuntimeStatus(
        runtime: ClaudeCompanionRuntimeState,
        accuracyState: ClaudeBrowserAccuracyState
    ) -> String {
        switch (self, runtime) {
        case (.english, .notConfigured):
            "Companion not configured."
        case (.simplifiedChinese, .notConfigured):
            "浏览器伴侣尚未配置。"
        case (.english, .starting):
            "Companion starting."
        case (.simplifiedChinese, .starting):
            "浏览器伴侣正在启动。"
        case (.english, .updatePendingSafariRestart):
            "Companion update pending Safari restart."
        case (.simplifiedChinese, .updatePendingSafariRestart):
            "浏览器伴侣更新正在等待 Safari 重启。"
        case (.english, .unavailable):
            "Native bridge unavailable."
        case (.simplifiedChinese, .unavailable):
            "原生桥接不可用。"
        case (.english, .protocolMismatch):
            "Companion protocol mismatch."
        case (.simplifiedChinese, .protocolMismatch):
            "浏览器伴侣协议不匹配。"
        case (.english, .ready):
            accuracyState == .consentRequired
                ? "Companion ready · Claude consent required."
                : "Companion ready."
        case (.simplifiedChinese, .ready):
            accuracyState == .consentRequired
                ? "浏览器伴侣已就绪 · 需要 Claude 同意。"
                : "浏览器伴侣已就绪。"
        }
    }

    func claudeUpdated(_ date: Date?) -> String {
        guard let date else {
            return switch self {
            case .simplifiedChinese: "尚未收到当前用量"
            case .english: "No current usage received"
            }
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        let value = formatter.localizedString(
            for: date,
            relativeTo: Date()
        )
        return switch self {
        case .simplifiedChinese: "更新于\(value)"
        case .english: "Updated \(value)"
        }
    }
}
