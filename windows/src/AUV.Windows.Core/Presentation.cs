using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Encodings.Web;
using System.Text.Json;

namespace AUV.Windows.Core;

public abstract class Observable : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void Changed([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new(name));
    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    { if (EqualityComparer<T>.Default.Equals(field, value)) return false; field = value; Changed(name); return true; }
}

public sealed class ModelCatalog
{
    public string Revision { get; }
    public IReadOnlyDictionary<string, string[]> Models { get; }
    public static readonly string[] DisplayOrder = ["gpt-6.1-sol", "gpt-6-sol", "gpt-6-luna", "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra"];
    public ModelCatalog()
    {
        using var stream = typeof(ModelCatalog).Assembly.GetManifestResourceStream("AUV.Windows.Core.Resources.models.v4.json")
            ?? throw new InvalidDataException("Missing versioned model catalog.");
        using var json = JsonDocument.Parse(stream);
        Revision = json.RootElement.GetProperty("revision").GetString()!;
        if (Revision != "sol-luna-ultra-20261010.1") throw new InvalidDataException("Unexpected model catalog revision.");
        Models = json.RootElement.GetProperty("models").EnumerateObject().ToDictionary(m => m.Name,
            m => m.Value.GetProperty("reasoning_efforts").EnumerateArray().Select(e => e.GetString()!).ToArray());
    }
    public bool Allows(string? model, string? effort) => model != null && effort != null && Models.TryGetValue(model, out var list) && list.Contains(effort);
}

public sealed record RoleSelection(string Model, string Effort);

public sealed class RoleDraft : Observable
{
    private readonly ModelCatalog catalog;
    private string model;
    private string effort;
    public string Key { get; }
    public string Label { get; }
    public string Purpose { get; }
    public string[] Models => ModelCatalog.DisplayOrder;
    public string[] Efforts => catalog.Models[model];
    public string Model
    {
        get => model;
        set
        {
            if (!catalog.Models.ContainsKey(value) || !Set(ref model, value)) return;
            // Normalize before notifying Efforts: WPF may temporarily clear a ComboBox selection.
            if (!catalog.Allows(model, effort)) { effort = "medium"; Changed(nameof(Effort)); }
            Changed(nameof(Efforts));
        }
    }
    public string Effort { get => effort; set { if (catalog.Allows(model, value)) Set(ref effort, value); } }
    public RoleDraft(ModelCatalog catalog, string key, string label, string purpose, string model, string effort)
    { this.catalog = catalog; Key = key; Label = label; Purpose = purpose; this.model = model; this.effort = effort; }
    public RoleSelection Selection => new(Model, Effort);
}

/// <summary>Exact compact JSON contract from v0.15.1 ThreadOSLeaderPrompt.make. No execution or dispatch.</summary>
public static class LeaderInstruction
{
    public static readonly string[] Roles = ["leader", "coderCluster", "reviewerCluster", "qa"];
    public static string Generate(ModelCatalog catalog, IReadOnlyDictionary<string, RoleSelection> selections)
    {
        if (selections.Count != 4 || Roles.Any(r => !selections.TryGetValue(r, out var s) || !catalog.Allows(s.Model, s.Effort)))
            throw new ArgumentException("Unsupported role/model/effort selection.");
        var roles = new SortedDictionary<string, object>(StringComparer.Ordinal);
        foreach (var role in Roles)
            roles[role] = new SortedDictionary<string, object>(StringComparer.Ordinal)
            { ["model"] = selections[role].Model, ["thinking"] = selections[role].Effort };
        var execution = new SortedDictionary<string, object>(StringComparer.Ordinal)
        {
            ["leader_control"] = "native_control_or_manual", ["minimal_recording"] = true,
            ["no_interrupt"] = true, ["no_routine_confirmation"] = true, ["no_self_dispatch"] = true,
            ["only_bound_roles"] = true, ["parallel_native_dispatch"] = true,
            ["report_values"] = new[] { "requested", "submitted", "effective" },
            ["respect_host_restrictions"] = true, ["update_foremen_and_child_defaults"] = true
        };
        return JsonSerializer.Serialize(new SortedDictionary<string, object>(StringComparer.Ordinal)
        { ["execution"] = execution, ["op"] = "set_team_models", ["roles"] = roles, ["scope"] = "receiving_leader_bound_root" },
            new JsonSerializerOptions { Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping });
    }
}

public sealed record DayUsage(string Label, double Tokens);
public sealed record UsageSnapshot(double? WeeklyRemaining, double? ShortRemaining, long? AccountWeek,
    long? AccountLifetime, decimal? LocalEstimate, IReadOnlyList<DayUsage> Days)
{
    public static UsageSnapshot Unknown { get; } = new(null, null, null, null, null, []);
    public static double? ValidRemaining(double? value) => value is >= 0 and <= 100 && double.IsFinite(value.Value) ? value : null;
    public static string RemainingText(double? value) => ValidRemaining(value) is double number
        ? UiText.T($"{number.ToString("0.#", System.Globalization.CultureInfo.InvariantCulture)}% remaining", $"剩余 {number.ToString("0.#", System.Globalization.CultureInfo.InvariantCulture)}%") : UiText.T("Unknown", "未知");
    public static string TokensText(long? value) => value is >= 0 ? value.Value.ToString("N0") : "—";
}

public sealed class AgentPresentation
{
    public string Id { get; }
    public string Name { get; }
    public string Monogram { get; }
    public UsageSnapshot Usage { get; }
    public bool IsDemo { get; }
    public AllowanceCard Card { get; }
    public string SecondaryLabel { get; }
    public string SecondaryValue { get; }
    public string? TokenSource { get; }
    /// <summary>All admitted quota windows and the selection made for this read (in memory only).</summary>
    public QuotaSelection? Selection { get; init; }
    public IReadOnlyList<QuotaWindow> Windows { get; init; } = [];
    public bool HasSecondaryWindow => Windows.Count > 1 && Card.HasDisplayableQuota;
    public string Status => IsDemo ? "Development fixture" : Card.Connection.ToString();
    public string Remaining => UsageSnapshot.RemainingText(Usage.WeeklyRemaining);
    public bool HasUsage => UsageSnapshot.ValidRemaining(Usage.WeeklyRemaining) != null;
    public double RemainingValue => UsageSnapshot.ValidRemaining(Usage.WeeklyRemaining) ?? 0;
    public AgentPresentation(string id, string name, string monogram, UsageSnapshot usage, bool demo, AllowanceCard? card = null,
        string? secondaryLabel = null, string? secondaryValue = null, string? tokenSource = null)
    {
        Id = id; Name = name; Monogram = monogram; Usage = usage; IsDemo = demo;
        SecondaryLabel = secondaryLabel ?? UiText.T("Other · 5-hour window", "另一窗口 · 5 小时窗口"); SecondaryValue = secondaryValue ?? UsageSnapshot.RemainingText(usage.ShortRemaining); TokenSource = tokenSource;
        Card = card ?? new AllowanceCard(id, name, monogram, demo ? "Pro" : null,
            UsageSnapshot.ValidRemaining(usage.WeeklyRemaining) != null ? AllowanceKind.Percentage : AllowanceKind.Unavailable,
            usage.WeeklyRemaining, null, demo ? UiText.T("7-day window", "7 天窗口") : UiText.T("Quota unavailable", "额度不可用"),
            demo ? UiText.T("Development fixture · no account connected", "开发用样例数据 · 未连接账户") : UiText.T("No Windows provider connection configured", "尚未配置 Windows 连接"),
            demo ? UiText.T("Fixture snapshot · Oct 10, 2026", "样例快照 · 2026-10-10") : UiText.T("Never · no verified data", "从未 · 没有已验证数据"), demo ? ConnectionState.Connected : ConnectionState.Disconnected)
            { WindowMinutes = demo ? 10080 : null };
        if (demo && UsageSnapshot.ValidRemaining(usage.WeeklyRemaining) is double weekly)
            Windows = new[] { new QuotaWindow(id + ".secondary", 10080, weekly, null) }
                .Concat(UsageSnapshot.ValidRemaining(usage.ShortRemaining) is double shortWindow ? [new QuotaWindow(id + ".primary", 300, shortWindow, null)] : Array.Empty<QuotaWindow>()).ToArray();
    }
    public static AgentPresentation[] Create(bool demo) =>
    [
        new("codex", "Codex", "C", demo ? new(68, 82, 1246800, 18420000, 18.64m,
            new[] { 132000d, 218000, 167000, 246000, 184000, 205000, 94800 }.Select((v, i) => new DayUsage($"Oct {i + 4:00}", v)).ToArray()) : UsageSnapshot.Unknown, demo),
        new("claude", "Claude", "✳", demo ? new(43, 91, 864200, 9800000, 12.30m,
            new[] { 82000d, 146000, 119000, 170000, 102000, 138000, 107200 }.Select((v, i) => new DayUsage($"Oct {i + 4:00}", v)).ToArray()) : UsageSnapshot.Unknown, demo),
        new("workbuddy", "WorkBuddy", "W", UsageSnapshot.Unknown, false),
        new("antigravity", "Antigravity", "A", UsageSnapshot.Unknown, false)
    ];
}

public sealed class ShellState : Observable
{
    private string section = "AUV";
    private AgentPresentation selectedAgent;
    public AgentPresentation[] Agents { get; private set; }
    public void ReplaceAdmittedPresentation(AgentPresentation[] admitted)
    {
        var previous = selectedAgent.Id; Agents = admitted; Changed(nameof(Agents));
        if (admitted.Length > 0) { selectedAgent = admitted.FirstOrDefault(a => a.Id == previous) ?? admitted[0]; Changed(nameof(SelectedAgent)); }
    }
    /// <summary>Applies the user's agent order; an empty order restores the default Codex-first order.</summary>
    public void Reorder(IReadOnlyList<string> order) =>
        ReplaceAdmittedPresentation(AgentOrdering.Apply(Agents, a => a.Id, order.Count > 0 ? order : AgentCatalog.DefaultOrder).ToArray());
    public string Section { get => section; set { if (value is "AUV" or "ThreadOS" or "Sectorium") Set(ref section, value); } }
    public AgentPresentation SelectedAgent { get => selectedAgent; set { if (value != null && Agents.Contains(value)) Set(ref selectedAgent, value); } }
    public ShellState(bool demo, string agentId = "codex", string section = "AUV")
    { Agents = AgentPresentation.Create(demo); selectedAgent = Agents.FirstOrDefault(a => a.Id == agentId) ?? Agents[0]; Section = section; }
}

/// <summary>Presentation-only storage policy. This milestone has no storage executor, enumeration, or mutation API.</summary>
public static class SectoriumPreview
{
    public static bool CanMutate => false;
    public static string Status => "Windows storage backend is not implemented in this preview.";
    public static string[] UnavailableActions => ["Install / configure", "Mount", "Start", "Stop", "Safe eject"];
}
