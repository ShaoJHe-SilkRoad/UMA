using System.Windows.Input;
using AUV.Windows.Core;
namespace AUV.Windows.App;
public sealed class RelayCommand(Action action, Func<bool>? canExecute = null) : ICommand
{
    public bool CanExecute(object? parameter) => canExecute?.Invoke() ?? true;
    public void Execute(object? parameter) => action();
    public event EventHandler? CanExecuteChanged;
    public void Refresh() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}
public sealed record ChartBar(string Label, string Value, double Height, string Description = "");
public sealed class MainViewModel : Observable
{
    public ModelCatalog Catalog { get; } = new();
    public ShellState Shell { get; }
    public RoleDraft[] Roles { get; }
    public SectoriumState Storage { get; }
    public AllowanceCard SelectedCard => Shell.SelectedAgent.Card;
    public string PrimaryValue => SelectedCard.Value;
    public bool Demo { get; }
    public string Mode => Demo ? "DEMO · Sample data" : "";
    public AgentPresentation[] QuotaAgents => Shell.Agents.Where(a => a.Card.HasDisplayableQuota).ToArray();
    public bool HasQuotaAgents => QuotaAgents.Length > 0;
    public string DataState => Shell.SelectedAgent.IsDemo ? "Sample data · isolated fixture" : SelectedCard.Kind == AllowanceKind.Unavailable ? "Usage unavailable" : "Verified provider data";
    public string WeeklyRemaining => UsageSnapshot.RemainingText(Shell.SelectedAgent.Usage.WeeklyRemaining);
    public string ShortRemaining => Shell.SelectedAgent.SecondaryValue;
    public string SecondaryLabel => Shell.SelectedAgent.SecondaryLabel;
    public double WeeklyValue => UsageSnapshot.ValidRemaining(Shell.SelectedAgent.Usage.WeeklyRemaining) ?? 0;
    public double ShortValue => UsageSnapshot.ValidRemaining(Shell.SelectedAgent.Usage.ShortRemaining) ?? 0;
    public bool HasUsage => SelectedCard.HasDisplayableQuota;
    public bool HasPlan => HasUsage && !string.IsNullOrWhiteSpace(SelectedCard.Plan);
    public bool HasPercentBar => HasUsage && SelectedCard.FillFraction != null;
    public bool HasSecondary => HasUsage && !string.IsNullOrWhiteSpace(ShortRemaining) && ShortRemaining is not ("Unknown" or "Unavailable" or "—");
    public bool HasWeekTokens => Shell.SelectedAgent.Usage.AccountWeek is >= 0;
    public bool HasLifetimeTokens => Shell.SelectedAgent.Usage.AccountLifetime is >= 0;
    public bool HasLocalCost => Shell.SelectedAgent.Usage.LocalEstimate is >= 0;
    public bool HasData => HasUsage || HasWeekTokens || HasLifetimeTokens || HasChart || HasLocalCost;
    public string RemainingLabel => SelectedCard.Kind == AllowanceKind.Credits ? "Balance" : "Remaining";
    public string WeekTokens => UsageSnapshot.TokensText(Shell.SelectedAgent.Usage.AccountWeek);
    public string LifetimeTokens => UsageSnapshot.TokensText(Shell.SelectedAgent.Usage.AccountLifetime);
    public string LocalCost => Shell.SelectedAgent.Usage.LocalEstimate is decimal cost ? $"US${cost:0.00}" : "—";
    public string Source => SelectedCard.Source;
    public string Updated => SelectedCard.Freshness;
    public string ChartHeading => "Daily tokens";
    public string ChartSummary => Shell.SelectedAgent.TokenSource ?? (Shell.SelectedAgent.IsDemo ? "Local tokens · independent sample source" : "No token data available");
    public string Activity => Shell.SelectedAgent.IsDemo ? "Development fixture loaded. No local sessions were read." : "Only admitted allowance and aggregate account data are displayed. No conversation content is read.";
    public static string CompactTokens(double tokens) => tokens >= 1_000_000_000 ? $"{tokens / 1_000_000_000:0.##}B" : tokens >= 1_000_000 ? $"{tokens / 1_000_000:0.#}M" : tokens >= 1000 ? $"{tokens / 1000:0.#}k" : $"{tokens:0}";
    public ChartBar[] Bars => Shell.SelectedAgent.Usage.Days.Select(d => new ChartBar(d.Label, CompactTokens(d.Tokens), d.Tokens / Math.Max(1, Shell.SelectedAgent.Usage.Days.Max(x => x.Tokens)) * 100, $"{d.Tokens:N0} tokens · {d.Label}")).ToArray();
    public bool HasChart => Bars.Length > 0;
    private string generated = "";
    public string Generated { get => generated; private set { Set(ref generated, value); CopyCommand.Refresh(); } }
    private string instructionStatus = "Choose settings, generate, then copy and paste to your receiving Leader.";
    public string InstructionStatus { get => instructionStatus; set => Set(ref instructionStatus, value); }
    private string status = "Ready";
    public string Status { get => status; set => Set(ref status, value); }
    public RelayCommand GenerateCommand { get; }
    public RelayCommand CopyCommand { get; }
    public Action<string>? CopyText { get; set; }
    public MainViewModel(bool demo, PreviewSettings settings)
    {
        Demo = demo; Shell = new(demo, settings.SelectedAgent, settings.ActiveSection); Storage = new(demo);
        Roles = [new(Catalog, "leader", "Leader", "Plan & coordinate", "gpt-6.1-sol", "high"), new(Catalog, "coderCluster", "Coder Cluster", "Build & integrate", "gpt-6-luna", "medium"), new(Catalog, "reviewerCluster", "Reviewer Cluster", "Independent review", "gpt-6-luna", "medium"), new(Catalog, "qa", "QA", "Verify & accept", "gpt-6.1-sol", "high")];
        GenerateCommand = new(() => { Generated = LeaderInstruction.Generate(Catalog, Roles.ToDictionary(r => r.Key, r => r.Selection)); InstructionStatus = "Instruction generated locally. Copy and paste to your receiving Leader."; });
        CopyCommand = new(() => CopyText?.Invoke(Generated), () => Generated.Length > 0);
        foreach (var role in Roles)
        {
            if (settings.Roles.TryGetValue(role.Key, out var saved)) { role.Model = saved.Model; role.Effort = saved.Effort; }
            role.PropertyChanged += (_, _) => { Generated = ""; InstructionStatus = "Draft changed. Generate again before copying."; };
        }
        Shell.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(ShellState.Agents)) { Changed(nameof(QuotaAgents)); Changed(nameof(HasQuotaAgents)); }
            if (e.PropertyName != nameof(ShellState.SelectedAgent)) return;
            foreach (var name in new[] { nameof(SelectedCard), nameof(PrimaryValue), nameof(DataState), nameof(WeeklyRemaining), nameof(ShortRemaining), nameof(SecondaryLabel), nameof(WeeklyValue), nameof(ShortValue), nameof(HasUsage), nameof(HasPlan), nameof(HasPercentBar), nameof(HasSecondary), nameof(HasWeekTokens), nameof(HasLifetimeTokens), nameof(HasLocalCost), nameof(HasData), nameof(RemainingLabel), nameof(WeekTokens), nameof(LifetimeTokens), nameof(LocalCost), nameof(Source), nameof(Updated), nameof(ChartSummary), nameof(ChartHeading), nameof(Activity), nameof(Bars), nameof(HasChart) }) Changed(name);
        };
    }
}
