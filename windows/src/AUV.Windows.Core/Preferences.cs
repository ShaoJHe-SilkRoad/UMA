using System.Globalization;

namespace AUV.Windows.Core;

/// <summary>One schedule for every agent. Missing in pre-0.18.4 settings, so the defaults below apply on upgrade.</summary>
public sealed class RefreshPreferences
{
    public static readonly int[] Intervals = [5, 10, 15, 30, 60];
    public const int DefaultInterval = 5;
    public bool Automatic { get; set; } = true;
    public int IntervalMinutes { get; set; } = DefaultInterval;
    public bool OnWake { get; set; }
    public void Normalize() { if (!Intervals.Contains(IntervalMinutes)) IntervalMinutes = DefaultInterval; }
}

public static class AgentCatalog
{
    /// <summary>Default order, matching the Mac provider priority (Codex, Claude, WorkBuddy, Antigravity).</summary>
    public static readonly string[] DefaultOrder = ["codex", "claude", "workbuddy", "antigravity"];
    public static bool IsKnown(string? id) => id != null && DefaultOrder.Contains(id);
    public static string Name(string id) => id switch { "codex" => "Codex", "claude" => "Claude", "workbuddy" => "WorkBuddy", "antigravity" => "Antigravity", _ => id };
}

public static class AgentOrdering
{
    /// <summary>Listed ids first in saved order; unlisted ids keep their original relative order at the end.</summary>
    public static IReadOnlyList<T> Apply<T>(IEnumerable<T> items, Func<T, string> id, IReadOnlyList<string>? order)
    {
        var list = items.ToList();
        if (order is not { Count: > 0 }) return list;
        var rank = new Dictionary<string, int>(StringComparer.Ordinal);
        for (var i = 0; i < order.Count; i++) rank.TryAdd(order[i], i);
        return list.Select((item, index) => (item, index)).OrderBy(x => rank.TryGetValue(id(x.item), out var r) ? r : int.MaxValue).ThenBy(x => x.index).Select(x => x.item).ToList();
    }
    /// <summary>Moves one id to a new visible index and returns the complete visible order to persist.</summary>
    public static List<string> Move(IReadOnlyList<string> visible, string id, int targetIndex)
    {
        var order = visible.ToList(); var from = order.IndexOf(id);
        if (from < 0) return order;
        order.RemoveAt(from); order.Insert(Math.Clamp(targetIndex, 0, order.Count), id);
        return order;
    }
    public static List<string> Normalize(IEnumerable<string>? saved) =>
        (saved ?? []).Where(AgentCatalog.IsKnown).Distinct(StringComparer.Ordinal).ToList();
}

public static class TrayAgentPolicy
{
    /// <summary>
    /// A pinned agent is used even without a reading. Automatic: Codex while the user has not arranged agents
    /// and Codex has a reading; otherwise the first agent in the visible order with a reading.
    /// </summary>
    public static AgentPresentation? Select(IReadOnlyList<AgentPresentation> ordered, string? pinned, bool arranged)
    {
        if (!string.IsNullOrEmpty(pinned) && ordered.FirstOrDefault(a => a.Id == pinned) is { } pin) return pin;
        var readable = ordered.Where(a => a.Card.HasDisplayableQuota).ToArray();
        if (!arranged && readable.FirstOrDefault(a => a.Id == "codex") is { } codex) return codex;
        return readable.FirstOrDefault();
    }
}

public static class ReadingFreshness
{
    /// <summary>Validity when automatic refresh is off: only launch and manual reads keep a reading current.</summary>
    public static readonly TimeSpan ManualValidity = TimeSpan.FromMinutes(15);
    public static readonly TimeSpan Grace = TimeSpan.FromMinutes(2);
    public static TimeSpan Validity(RefreshPreferences refresh) =>
        (refresh.Automatic ? TimeSpan.FromMinutes(refresh.IntervalMinutes) : ManualValidity) + Grace;
    public static bool IsCurrent(DateTimeOffset? observedAt, DateTimeOffset now, RefreshPreferences refresh) =>
        observedAt is { } observed && now - observed <= Validity(refresh) && observed - now <= TimeSpan.FromMinutes(1);
}

public sealed record QuotaWindow(string Id, long Minutes, double Remaining, DateTimeOffset? ResetsAt)
{
    public int LengthRank => Minutes == 300 ? 0 : Minutes == 10080 ? 1 : 2;
    public string Compact => Minutes % 1440 == 0 ? $"{Minutes / 1440}d" : Minutes % 60 == 0 ? $"{Minutes / 60}h" : $"{Minutes}m";
    public string Label => Minutes % 1440 == 0 ? UiText.T($"{Minutes / 1440}-day window", $"{Minutes / 1440} 天窗口")
        : Minutes % 60 == 0 ? UiText.T($"{Minutes / 60}-hour window", $"{Minutes / 60} 小时窗口") : UiText.T($"{Minutes}-minute window", $"{Minutes} 分钟窗口");
}
public sealed record QuotaSelection(string? SelectedId, IReadOnlyList<QuotaWindow> Windows);

/// <summary>Mac 0.18.0 rule: a spent window first, then the window that dropped most since the previous reading.</summary>
public static class QuotaWindowPolicy
{
    private static readonly TimeSpan SameEpoch = TimeSpan.FromMinutes(10);
    private static IOrderedEnumerable<QuotaWindow> ByLength(IEnumerable<QuotaWindow> windows) =>
        windows.OrderBy(w => w.LengthRank).ThenBy(w => w.Id, StringComparer.Ordinal);
    public static string? Select(IReadOnlyList<QuotaWindow> current, QuotaSelection? previous, DateTimeOffset now)
    {
        var eligible = current.Where(w => w.ResetsAt is not { } reset || reset > now).Where(w => double.IsFinite(w.Remaining)).ToArray();
        if (eligible.Length == 0) return null;
        if (ByLength(eligible.Where(w => w.Remaining == 0)).FirstOrDefault() is { } spent) return spent.Id;
        if (previous != null)
        {
            var changed = eligible.Select(w =>
            {
                var old = previous.Windows.FirstOrDefault(p => p.Id == w.Id);
                var decrement = old != null && Epoch(old.ResetsAt, w.ResetsAt) ? Math.Max(0, old.Remaining - w.Remaining) : 0;
                return (Window: w, Decrement: decrement);
            }).Where(x => x.Decrement > 0).OrderByDescending(x => x.Decrement).ThenBy(x => x.Window.LengthRank).ThenBy(x => x.Window.Id, StringComparer.Ordinal).FirstOrDefault();
            if (changed.Window != null) return changed.Window.Id;
            if (previous.SelectedId != null && eligible.Any(w => w.Id == previous.SelectedId)) return previous.SelectedId;
        }
        return eligible.OrderBy(w => w.LengthRank).ThenBy(w => w.Remaining).ThenBy(w => w.Id, StringComparer.Ordinal).First().Id;
    }
    private static bool Epoch(DateTimeOffset? a, DateTimeOffset? b) => a == null && b == null || a is { } x && b is { } y && (x - y).Duration() <= SameEpoch;
}

public static class ResetText
{
    /// <summary>"Resets in 2 hr (Oct 28, 18:40)" / "2 小时后重置（10月28日 18:40）". Unknown or past resets are blank.</summary>
    public static string? Format(DateTimeOffset? resetsAt, DateTimeOffset now)
    {
        if (resetsAt is not { } reset || reset <= now) return null;
        var left = reset - now; var local = reset.ToLocalTime();
        var en = left.TotalMinutes < 60 ? $"{Math.Max(1, (int)Math.Ceiling(left.TotalMinutes))} min" : left.TotalHours < 48 ? $"{(int)Math.Round(left.TotalHours)} hr" : $"{(int)Math.Round(left.TotalDays)} days";
        var zh = left.TotalMinutes < 60 ? $"{Math.Max(1, (int)Math.Ceiling(left.TotalMinutes))} 分钟" : left.TotalHours < 48 ? $"{(int)Math.Round(left.TotalHours)} 小时" : $"{(int)Math.Round(left.TotalDays)} 天";
        return UiText.T($"Resets in {en} ({local.ToString("MMM d, HH:mm", CultureInfo.InvariantCulture)})",
            $"{zh}后重置（{local.Month}月{local.Day}日 {local:HH:mm}）");
    }
}

public static class ThinkingLabels
{
    /// <summary>Composer effort labels as on the Mac: Low/Medium/High/Ex High/Ultra and 低/中/高/极高/超高.</summary>
    public static string Label(string effort) => effort switch
    {
        "low" => UiText.T("Low", "低"), "medium" => UiText.T("Medium", "中"), "high" => UiText.T("High", "高"),
        "xhigh" => UiText.T("Ex High", "极高"), "ultra" => UiText.T("Ultra", "超高"), _ => effort
    };
}
