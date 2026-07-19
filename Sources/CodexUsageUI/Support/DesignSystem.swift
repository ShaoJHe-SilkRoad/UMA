import SwiftUI

public enum UsagePanelMetrics {
    public static let width: CGFloat = 370
    public static let height: CGFloat = 776
    public static let collapsedHeight: CGFloat = 402
    public static let settingsMinimumHeight: CGFloat = 430

    public static func targetHeight(
        showsRealData: Bool,
        moreInfoExpanded: Bool,
        settingsPresented: Bool
    ) -> CGFloat {
        let contentHeight: CGFloat
        if !showsRealData {
            contentHeight = 330
        } else {
            contentHeight = moreInfoExpanded ? height : collapsedHeight
        }
        return settingsPresented ? max(contentHeight, settingsMinimumHeight) : contentHeight
    }

    public static func preferredHeight(
        showUsageSummary: Bool,
        showRecentTasks: Bool,
        showAPICost: Bool
    ) -> CGFloat {
        guard showRecentTasks || showAPICost else { return collapsedHeight }
        return height
    }
}

enum UsageDesign {
    static let blue = Color(red: 0.0, green: 0.43, blue: 0.94)
    static let green = Color(red: 0.05, green: 0.72, blue: 0.34)

    static func font(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        language: AppLanguage = .simplifiedChinese
    ) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

struct GlassCardBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    let tuning: GlassTuning

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(.ultraThinMaterial)
            .opacity(0.72)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        Color.white.opacity(
                            colorScheme == .dark ? 0.035 : 0.085
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(
                                    colorScheme == .dark ? 0.12 : 0.20
                                ),
                                Color.white.opacity(0.03),
                                Color.black.opacity(
                                    colorScheme == .dark ? 0.10 : 0.045
                                )
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(color: Color.black.opacity(0.045), radius: 4, y: 1)
    }
}
