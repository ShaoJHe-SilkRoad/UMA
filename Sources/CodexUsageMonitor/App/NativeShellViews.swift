import CodexUsageUI
import SwiftUI

enum MainWindowDestination: String, CaseIterable, Identifiable {
    case overview
    case providers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .providers: "Providers"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .providers: "person.3"
        }
    }
}

struct MainWindowRootView: View {
    @ObservedObject var store: UsageStore
    @State private var destination: MainWindowDestination? = .overview

    var body: some View {
        NavigationSplitView {
            List(MainWindowDestination.allCases, selection: $destination) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .accessibilityLabel("UMA navigation")
        } detail: {
            switch destination ?? .overview {
            case .overview:
                M1OverviewView(store: store)
            case .providers:
                M1ProvidersView(store: store)
            }
        }
        .frame(minWidth: 720, minHeight: 500)
    }
}

private struct M1OverviewView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Overview")
                        .font(.largeTitle.bold())
                    Text("Remaining usage from the existing UMA provider presentation.")
                        .foregroundStyle(.secondary)
                }

                if store.productInventory.overviewProviders.isEmpty {
                    ContentUnavailableView(
                        "No provider usage available",
                        systemImage: "gauge.with.dots.needle.0percent",
                        description: Text("Missing, unsupported, and error states are never shown as 0%.")
                    )
                } else {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 240), spacing: 14)],
                        spacing: 14
                    ) {
                        ForEach(store.productInventory.overviewProviders) { provider in
                            M1ProviderSummary(provider: provider)
                        }
                    }
                }
            }
            .padding(28)
        }
    }
}

private struct M1ProvidersView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Group {
            List(store.productInventory.providers) { provider in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(provider.displayName).font(.headline)
                            if let planLabel = provider.planLabel {
                                Text(planLabel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(provider.primaryDisplayText)
                                .font(.title3.monospacedDigit().bold())
                        }
                        ForEach(provider.quotas) { quota in
                            HStack {
                                Text(quota.compactLabel)
                                Spacer()
                                Text(quota.displayText)
                                    .monospacedDigit()
                            }
                            .font(.callout)
                        }
                        if provider.quotas.isEmpty {
                            Text(providerStatus(provider))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
        }
    }

    private func providerStatus(_ provider: ProviderProductState) -> String {
        switch provider.availability {
        case .available: "Usage unavailable"
        case .setupRequired: "Setup required"
        case .disabled: "Monitoring disabled"
        case .unavailable: "Currently unavailable"
        case .unsupported: "Unsupported"
        }
    }
}

private struct M1ProviderSummary: View {
    let provider: ProviderProductState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(provider.displayName)
                .font(.headline)
                .lineLimit(1)
            Text(provider.primaryDisplayText)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(provider.primaryQuota?.compactLabel ?? "Remaining")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provider.displayName), \(provider.primaryDisplayText) remaining")
    }
}

struct SettingsWindowRootView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        Form {
            Section("General") {
                Picker(
                    "Language",
                    selection: Binding(
                        get: { store.language },
                        set: { store.setLanguage($0) }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Application language")
            }

            Section("M1 scope") {
                Text("Existing advanced and provider settings remain available in the Quick Panel and are deferred for M4 migration.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 480, minHeight: 320)
    }
}
