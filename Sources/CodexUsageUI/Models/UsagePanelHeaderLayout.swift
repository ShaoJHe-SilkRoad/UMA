import Foundation

/// Compact-panel header rules kept outside the private SwiftUI view so their
/// readability contract is directly testable.
public enum UsagePanelHeaderLayout {
    /// Keeps the complete localized product title visible beside the plan and
    /// toolbar controls at the fixed 370-point panel width.
    public static let titleMinimumScaleFactor: CGFloat = 0.72
    public static let titleLayoutPriority: Double = 1
}
