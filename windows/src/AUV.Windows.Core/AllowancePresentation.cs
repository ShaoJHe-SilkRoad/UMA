using System.Globalization;
using System.Text.RegularExpressions;

namespace AUV.Windows.Core;

public enum AllowanceKind { Percentage, Estimated, Unlimited, Credits, Unavailable }
public enum QuotaSeverity { Neutral, Normal, Low }
public enum ConnectionState { Connected, Reconnecting, Stale, Disconnected, Unavailable, Failed }
public enum WizardDensity { Automatic, Regular, Minimalist }

/// <summary>Admitted immutable presentation. No transport, cache, chooser, or refresh action.</summary>
public sealed record AllowanceCard
{
    public string Id { get; init; }
    public string Name { get; init; }
    public string Mark { get; init; }
    public string? Plan { get; init; }
    public string Window { get; init; }
    public string Source { get; init; }
    public string Freshness { get; init; }
    public ConnectionState Connection { get; init; }
    public bool IsStale { get; init; }
    /// <summary>Structured window length, so compact labels do not depend on display language.</summary>
    public long? WindowMinutes { get; init; }
    public DateTimeOffset? ResetsAt { get; init; }
    /// <summary>When the provider reading was verified. Used for the fresh-only display rule.</summary>
    public DateTimeOffset? ObservedAt { get; init; }
    public AllowanceKind Kind { get; }
    public double? Percent { get; }
    public decimal? Credits { get; }
    public bool HasDisplayableQuota => Kind != AllowanceKind.Unavailable && Connection == ConnectionState.Connected && !IsStale;
    public double? FillFraction => Kind is AllowanceKind.Percentage or AllowanceKind.Estimated ? Percent / 100 : null;
    public string Value => Kind switch
    {
        AllowanceKind.Percentage => FormatPercent(Percent!.Value),
        AllowanceKind.Estimated => "≈" + FormatPercent(Percent!.Value),
        AllowanceKind.Unlimited => "∞",
        AllowanceKind.Credits => Credits!.Value.ToString(Credits.Value == decimal.Truncate(Credits.Value) ? "N0" : "N2", CultureInfo.InvariantCulture) + " Credits",
        _ => "—"
    };
    public string Detail => Plan is { Length: > 0 } ? $"{Plan} · {Window}" : Window;
    /// <summary>Tray panel line: plan, window and the reset time when it is known and still ahead.</summary>
    public string DetailWithReset => ResetText.Format(ResetsAt, DateTimeOffset.UtcNow) is { } reset ? $"{Detail} · {reset}" : Detail;
    public string WizardWindow
    {
        get
        {
            if (WindowMinutes is long minutes && minutes > 0) return new QuotaWindow("", minutes, 0, null).Compact;
            var window = Regex.Replace(Window, @"\s*·\s*resets\b.*$", "", RegexOptions.IgnoreCase).Trim();
            window = Regex.Replace(window, @"\b(\d+)\s*[- ]?\s*(?:days?|d)\b(?:\s+(?:window|limit))?", "$1d", RegexOptions.IgnoreCase);
            window = Regex.Replace(window, @"\b(\d+)\s*[- ]?\s*(?:hours?|hrs?|h)\b(?:\s+(?:window|limit))?", "$1h", RegexOptions.IgnoreCase);
            return window;
        }
    }
    public string MinimalistValue => Id == "workbuddy" && Kind == AllowanceKind.Credits ? CompactCredits.Format(Credits!.Value) : Value;
    public QuotaSeverity Severity => LowRemainingPolicy.Resolve(Id, Plan, Percent, Credits, Kind);
    public string Description => UiText.T(
        $"{Name}; {Plan ?? "plan unknown"}; {Value} remaining; {Window}; {Source}; {Freshness}; {Connection}; {Severity}{(IsStale ? "; retained stale snapshot" : "")}",
        $"{Name}；{Plan ?? "方案未知"}；剩余 {Value}；{Window}；{Source}；{Freshness}；{Connection}；{Severity}{(IsStale ? "；已过期的保留读数" : "")}");
    public static string FormatPercent(double value) => value.ToString("0.#", CultureInfo.InvariantCulture) + "%";
    public AllowanceCard(string id, string name, string mark, string? plan, AllowanceKind kind,
        double? percent, decimal? credits, string window, string source, string freshness,
        ConnectionState connection, bool stale = false)
    {
        Id = id; Name = name; Mark = mark; Plan = plan; Window = window; Source = source;
        Freshness = freshness; Connection = connection; IsStale = stale;
        Kind = kind switch
        {
            AllowanceKind.Percentage or AllowanceKind.Estimated when UsageSnapshot.ValidRemaining(percent) == null => AllowanceKind.Unavailable,
            AllowanceKind.Credits when credits is null or < 0 => AllowanceKind.Unavailable,
            _ => kind
        };
        Percent = Kind is AllowanceKind.Percentage or AllowanceKind.Estimated ? percent : null;
        Credits = Kind == AllowanceKind.Credits ? credits : null;
    }
}

/// <summary>Compact, downward-rounded balance. Exact Credits remain in the card description.</summary>
public static class CompactCredits
{
    private static readonly string[] Units = ["", "k", "M", "B", "T", "P", "E", "Z", "Y"];
    public static string Format(decimal amount)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(amount);
        if (amount is > 0 and < .1m) return "<0.1";
        if (amount >= 1_000_000_000_000_000_000_000_000_000m)
        {
            var leading = amount / 1_000_000_000_000_000_000_000_000_000m; var exponent = 27;
            while (leading >= 10) { leading /= 10; exponent++; }
            return decimal.Truncate(leading).ToString("0", CultureInfo.InvariantCulture) + "e" + exponent;
        }
        var value = amount; var unit = 0;
        while (value >= 1000 && unit < Units.Length - 1) { value /= 1000; unit++; }
        var factor = value < 10 ? 10m : 1m;
        return (decimal.Truncate(value * factor) / factor).ToString("0.#", CultureInfo.InvariantCulture) + Units[unit];
    }
}

public static class LowRemainingPolicy
{
    public static QuotaSeverity Resolve(string id, string? plan, double? percent, decimal? credits, AllowanceKind kind)
    {
        var provider = id.Split('.')[0].Trim().ToLowerInvariant();
        if (provider == "workbuddy" && kind == AllowanceKind.Credits && credits is >= 0)
            return credits < 500 ? QuotaSeverity.Low : QuotaSeverity.Normal;
        if (kind is not (AllowanceKind.Percentage or AllowanceKind.Estimated) || UsageSnapshot.ValidRemaining(percent) == null) return QuotaSeverity.Neutral;
        double? threshold = (provider, plan?.Trim().ToLowerInvariant()) switch
        { ("codex", "pro") or ("claude", "max") => 10, ("codex", "plus") or ("claude", "pro") => 20, _ => null };
        return threshold == null ? QuotaSeverity.Neutral : percent < threshold ? QuotaSeverity.Low : QuotaSeverity.Normal;
    }
}

public static class WizardPolicy
{
    public const double WidthRatio = .6;
    public const double HeightRatio = .8;
    public const double RegularWidth = 138.6;
    public const double RegularWidthAdjustment = 1.1;
    public const double MinimalistWidthAdjustment = 1.2;
    public const double RegularRowHeight = 48;
    public const double RowGap = 3.2;
    public static WizardDensity Resolve(WizardDensity preference, int visibleCount) =>
        visibleCount >= 5 || preference == WizardDensity.Minimalist ? WizardDensity.Minimalist : WizardDensity.Regular;
    public static double StackHeight(int count, double rowHeight) => count <= 0 ? 0 : count * rowHeight + (count - 1) * RowGap;
    public static bool IsDrag(double x, double y, double horizontalThreshold, double verticalThreshold) =>
        Math.Abs(x) >= horizontalThreshold || Math.Abs(y) >= verticalThreshold;
}

/// <summary>Single non-mutating storage presentation store; fixtures are explicitly opt-in.</summary>
public sealed class SectoriumState : Observable
{
    public IWindowsStorageBackend Backend { get; } = new PreparedWindowsStorageBackend();
    public bool Demo { get; }
    private bool volumeSelected;
    public bool VolumeSelected { get => volumeSelected; set { if (Set(ref volumeSelected, value)) { Changed(nameof(DetailHeading)); Changed(nameof(SelectedIdentity)); } } }
    public string DetailHeading => VolumeSelected ? UiText.T("Selected development volume", "所选开发卷") : UiText.T("Selected physical drive", "所选物理磁盘");
    public string SelectedIdentity => VolumeSelected ? Volume : Identity;
    private bool error;
    public bool FixtureError { get => error; set { if (Demo && Set(ref error, value)) { Changed(nameof(Feedback)); Changed(nameof(Installation)); } } }
    public string PhysicalDrive => Demo ? "DEMO · External SSD" : UiText.T("Drive discovery unavailable", "无法发现磁盘");
    public string Identity => Demo ? "Fixture SSD · 1 TB · synthetic identity" : UiText.T("Unknown · no inventory read", "未知 · 未读取磁盘清单");
    public string Volume => Demo ? "↳ DEMO · Development.vhdx (illustration)" : UiText.T("None associated", "无关联卷");
    public string Installation => Demo ? FixtureError ? "Fixture error · configuration unavailable" : "Fixture only · unmounted" : UiText.T("Backend unavailable", "后端不可用");
    public string Feedback => Demo ? FixtureError ? "DEMO error: synthetic volume configuration could not be read. No operation was attempted." : "DEMO populated layout. No real drive or image is represented." : UiText.T("Windows storage backend is not implemented. No operation was attempted.", "Windows 存储后端尚未实现，未执行任何操作。");
    public SectoriumState(bool demo) { Demo = demo; }
}
