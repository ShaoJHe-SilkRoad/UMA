extension AppLanguage {
    var globalSettingsSection: String {
        self == .simplifiedChinese ? "全局" : "Global"
    }

    var agentsSettingsSection: String {
        self == .simplifiedChinese ? "智能体" : "Agents"
    }

    var autoSearchForAgents: String {
        self == .simplifiedChinese ? "自动搜索智能体" : "Auto Search for Agents"
    }

    var autoSearchOnboardingHint: String {
        self == .simplifiedChinese
            ? "首次搜索必须手动启动。完成后，此设置才会在后续启动时生效。"
            : "The first search is manual. This setting applies on later launches after that search completes."
    }

    var scanForAgents: String {
        self == .simplifiedChinese ? "搜索智能体" : "Scan for Agents"
    }

    var agentSettings: String {
        self == .simplifiedChinese ? "智能体设置" : "Agent Settings"
    }

    var backToSettings: String {
        self == .simplifiedChinese ? "返回设置" : "Back to Settings"
    }

    var notCurrentlyRunning: String {
        self == .simplifiedChinese ? "当前未运行" : "Not currently running"
    }

    var agentSetupRequired: String {
        self == .simplifiedChinese ? "需要完成设置" : "Setup required"
    }

    var agentSetupRequiredGuidance: String {
        self == .simplifiedChinese
            ? "请在此智能体的设置中完成安全登录或连接。"
            : "Complete the safe sign-in or connection in this Agent's settings."
    }

    var savedSettingsApplyWhenDetected: String {
        self == .simplifiedChinese
            ? "检测到后将应用已保存的设置。"
            : "Saved settings will apply when detected."
    }

    var monitoringEnabled: String {
        self == .simplifiedChinese ? "启用监控" : "Monitoring Enabled"
    }
}
