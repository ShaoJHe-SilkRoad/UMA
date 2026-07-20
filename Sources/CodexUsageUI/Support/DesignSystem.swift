import AppKit
import CoreText
import SwiftUI

public enum UsagePanelMetrics {
    public static let width: CGFloat = 370
    public static let outerInset: CGFloat = 16
    public static let minimumHeight: CGFloat = 330
    public static let height: CGFloat = 740
    public static let collapsedHeight: CGFloat = 360
    public static let settingsMinimumHeight: CGFloat = collapsedHeight

    public static func presentedHeight(
        showsRealData: Bool,
        moreInfoExpanded: Bool,
        recentTaskCount: Int,
        meteredPeriodCount: Int,
        settingsPresented: Bool
    ) -> CGFloat {
        let meteredPeriodAdjustment =
            CGFloat(max(0, meteredPeriodCount - 1)) * 30
        let contentHeight: CGFloat
        if !showsRealData {
            contentHeight = minimumHeight
        } else if moreInfoExpanded {
            // The expanded body adds the two established 10-point gaps, the
            // Recent Tasks header, its existing rows/dividers, and the
            // unchanged cost card. This sizes the exterior to the presented
            // rows instead of leaving a second-looking empty lower bezel.
            contentHeight = min(
                height,
                560
                    + (CGFloat(max(0, recentTaskCount)) * 50)
                    + meteredPeriodAdjustment
            )
        } else {
            contentHeight = collapsedHeight + meteredPeriodAdjustment
        }
        return settingsPresented
            ? max(contentHeight, settingsMinimumHeight)
            : contentHeight
    }

    public static func targetHeight(
        showsRealData: Bool,
        moreInfoExpanded: Bool,
        settingsPresented: Bool
    ) -> CGFloat {
        let contentHeight: CGFloat
        if !showsRealData {
            contentHeight = minimumHeight
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

public enum UsageTypographyRole: String, CaseIterable, Sendable {
    case applicationTitle
    case planLabel
    case primaryQuotaValue
    case quotaLabel
    case resetTime
    case syncStatus
    case sectionTitle
    case body
    case secondaryBody
    case disclosure
    case settingsLabel
    case tokenMetric
    case priceMetric
    case errorStatus

    fileprivate var pointSize: CGFloat {
        switch self {
        case .applicationTitle: 20
        case .planLabel: 11
        case .primaryQuotaValue: 24
        case .quotaLabel: 16
        case .resetTime: 11.5
        case .syncStatus: 13
        case .sectionTitle: 15
        case .body: 13
        case .secondaryBody: 10.5
        case .disclosure: 12.5
        case .settingsLabel: 12.5
        case .tokenMetric: 14.5
        case .priceMetric: 25
        case .errorStatus: 9.5
        }
    }

    fileprivate var robotoPostScriptName: String {
        switch self {
        case .applicationTitle, .planLabel, .primaryQuotaValue, .quotaLabel,
             .sectionTitle, .tokenMetric, .priceMetric:
            "Roboto-Bold"
        case .disclosure, .settingsLabel:
            "Roboto-Medium"
        case .resetTime, .syncStatus, .body, .secondaryBody, .errorStatus:
            "Roboto-Regular"
        }
    }

    fileprivate var cjkPostScriptName: String {
        switch self {
        case .applicationTitle, .planLabel, .primaryQuotaValue, .quotaLabel,
             .sectionTitle, .tokenMetric, .priceMetric:
            "PingFangSC-Semibold"
        case .disclosure, .settingsLabel:
            "PingFangSC-Medium"
        case .resetTime, .syncStatus, .body, .secondaryBody, .errorStatus:
            "PingFangSC-Regular"
        }
    }
}

public enum UsageTypographyError: Error, CustomStringConvertible {
    case missingResource(String)
    case registrationFailed(String, String)
    case unavailablePostScriptName(String)

    public var description: String {
        switch self {
        case .missingResource(let name):
            "Missing bundled font resource: \(name)"
        case .registrationFailed(let name, let reason):
            "Could not register \(name): \(reason)"
        case .unavailablePostScriptName(let name):
            "Registered font is unavailable by PostScript name: \(name)"
        }
    }
}

@MainActor
public enum UsageTypography {
    public static let requiredPostScriptNames = [
        "Roboto-Regular",
        "Roboto-Medium",
        "Roboto-Bold"
    ]
    public static let cjkFallbackFamily = "PingFang SC"

    private static var registrationResult: Result<[String], Error>?

    @discardableResult
    public static func registerBundledFonts() throws -> [String] {
        if let registrationResult {
            return try registrationResult.get()
        }

        do {
            for postScriptName in requiredPostScriptNames {
                let resourceName = postScriptName
                guard let url = resourceURL(named: resourceName) else {
                    throw UsageTypographyError.missingResource("\(resourceName).ttf")
                }

                var unmanagedError: Unmanaged<CFError>?
                let didRegister = CTFontManagerRegisterFontsForURL(
                    url as CFURL,
                    .process,
                    &unmanagedError
                )
                if !didRegister,
                   NSFont(name: postScriptName, size: 12) == nil {
                    let reason = unmanagedError?.takeRetainedValue().localizedDescription
                        ?? "CoreText returned no error detail"
                    throw UsageTypographyError.registrationFailed(resourceName, reason)
                }
                if let unmanagedError {
                    unmanagedError.release()
                }

                guard NSFont(name: postScriptName, size: 12) != nil else {
                    throw UsageTypographyError.unavailablePostScriptName(postScriptName)
                }
            }
            registrationResult = .success(requiredPostScriptNames)
            return requiredPostScriptNames
        } catch {
            registrationResult = .failure(error)
            throw error
        }
    }

    public static func font(
        _ role: UsageTypographyRole,
        language: AppLanguage,
        sizeOverride: CGFloat? = nil
    ) -> Font {
        Font(appKitFont(role, language: language, sizeOverride: sizeOverride))
    }

    public static func appKitFont(
        _ role: UsageTypographyRole,
        language: AppLanguage,
        sizeOverride: CGFloat? = nil
    ) -> NSFont {
        if registrationResult == nil {
            do {
                try registerBundledFonts()
            } catch {
                preconditionFailure("Roboto registration failed: \(error)")
            }
        }
        let size = sizeOverride ?? role.pointSize
        let fallback = NSFontDescriptor(
            name: role.cjkPostScriptName,
            size: size
        )
        let descriptor = NSFontDescriptor(
            fontAttributes: [
                .name: role.robotoPostScriptName,
                .size: size,
                NSFontDescriptor.AttributeName(
                    rawValue: kCTFontCascadeListAttribute as String
                ): [fallback]
            ]
        )
        guard let font = NSFont(descriptor: descriptor, size: size) else {
            preconditionFailure(
                "Roboto must be registered before constructing application UI: "
                    + role.robotoPostScriptName
            )
        }
        return font
    }

    public static func postScriptName(for role: UsageTypographyRole) -> String {
        role.robotoPostScriptName
    }

    public static func cjkPostScriptName(for role: UsageTypographyRole) -> String {
        role.cjkPostScriptName
    }

    private static func resourceURL(named name: String) -> URL? {
        let subdirectory = "Fonts/Roboto"
        if let packaged = Bundle.main.url(
            forResource: name,
            withExtension: "ttf",
            subdirectory: subdirectory
        ) {
            return packaged
        }
        if let structured = Bundle.module.url(
            forResource: name,
            withExtension: "ttf",
            subdirectory: subdirectory
        ) {
            return structured
        }
        // SwiftPM flattens `.process("Resources")` into its generated bundle.
        return Bundle.module.url(forResource: name, withExtension: "ttf")
    }
}

enum UsageDesign {
    static let blue = Color(red: 0.0, green: 0.43, blue: 0.94)
    static let green = Color(red: 0.05, green: 0.72, blue: 0.34)

    @MainActor
    static func font(
        _ role: UsageTypographyRole,
        language: AppLanguage,
        sizeOverride: CGFloat? = nil
    ) -> Font {
        UsageTypography.font(
            role,
            language: language,
            sizeOverride: sizeOverride
        )
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
