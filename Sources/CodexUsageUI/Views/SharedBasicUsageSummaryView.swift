import SwiftUI

/// Reusable read-only account/provider usage content. Callers supply the
/// frozen `BasicSharedUsagePresentation` from `UsageStore.snapshot`; this view
/// owns no store, collector, refresh task, or ThreadOS attribution input.
struct SharedBasicUsageSummaryView: View {
    let presentation: BasicSharedUsagePresentation
    let language: AppLanguage
    var showsQuotaWindows = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(localized("Snapshot updated", "快照更新时间")): \(presentation.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            if showsQuotaWindows, !presentation.windows.isEmpty {
                ForEach(presentation.windows) { window in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(window.title).font(.callout.weight(.medium))
                        }
                        Spacer(minLength: 12)
                        Text("\(localized("Remaining", "剩余")): \(window.isEstimated ? "≈\(window.remainingText)" : window.remainingText)")
                            .font(.headline.monospacedDigit())
                    }
                }
            }

            if !presentation.metrics.isEmpty {
                Text(localized("Locally observed tokens", "本地观察令牌"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 20) {
                    ForEach(presentation.metrics) { metric in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metric.value).font(.headline).monospacedDigit()
                            Text(metric.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if presentation.recentActivity.isEmpty {
                Text(localized("No recent allowlisted local activity metadata.", "暂无允许范围内的本地活动元数据。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(presentation.recentActivity) { activity in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(activity.title).lineLimit(1)
                            Text(activity.timestamp).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Text(activity.tokenText).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }

            if let estimate = presentation.apiEquivalentEstimate {
                VStack(alignment: .leading, spacing: 3) {
                    localSourceContext
                    fact(localized("API-equivalent local estimate (7 days)", "API 等效本地估算（7 天）"), currency(estimate.sevenDayUSD))
                    fact(localized("API-equivalent local estimate (lifetime)", "API 等效本地估算（生命周期）"), currency(estimate.lifetimeUSD))
                    Text(coverageText(for: estimate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                localSourceContext
                Text(localized("API-equivalent local estimate unavailable.", "API 等效本地估算不可用。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let source = presentation.providerSource {
                Text("\(localized("Account source", "账户来源")): \(source.label) · \(freshness(source.freshness)) · \(source.isAvailable ? localized("available", "可用") : localized("unavailable", "不可用"))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(localized("Account source unavailable.", "账户来源不可用。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private func coverageText(for estimate: BasicSharedUsagePresentation.APIEquivalentEstimate) -> String {
        if estimate.isPartialCoverage {
            return localized(
                "Priced coverage \(estimate.coveragePercent)% — partial local estimate, not an account total.",
                "已定价覆盖率 \(estimate.coveragePercent)%——仅为部分本地估算，并非账户总额。"
            )
        }
        return localized(
            "Priced coverage \(estimate.coveragePercent)% for admitted local activity.",
            "已定价覆盖率 \(estimate.coveragePercent)%（已准入本地活动）。"
        )
    }

    private func localized(_ english: String, _ chinese: String) -> String {
        language == .simplifiedChinese ? chinese : english
    }

    private func freshness(_ value: UsageSourceStatus.Freshness) -> String {
        switch value {
        case .fresh: localized("current", "当前")
        case .stale: localized("stale", "已过期")
        case .unavailable: localized("unavailable", "不可用")
        }
    }

    @ViewBuilder private var localSourceContext: some View {
        if let source = presentation.localSource {
            Text("\(localized("Local activity source", "本地活动来源")): \(source.label) · \(freshness(source.freshness)) · \(source.isAvailable ? localized("available", "可用") : localized("unavailable", "不可用"))")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text(localized("Local activity source unavailable.", "本地活动来源不可用。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
