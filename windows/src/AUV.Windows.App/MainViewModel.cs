using System.Globalization;
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
/// <summary>One quota row on the agent page's Usage card.</summary>
public sealed record UsageRow(string Label, string Value, AllowanceCard Card, string? Reset, bool Shown, bool HasBar);
public sealed record DetailRow(string Label, string Value);
public sealed class MainViewModel : Observable
{
    public ModelCatalog Catalog { get; } = new();
    public ShellState Shell { get; }
    public RoleDraft[] Roles { get; }
    public SectoriumState Storage { get; }
    public AllowanceCard SelectedCard => Shell.SelectedAgent.Card;
    public string PrimaryValue => SelectedCard.Value;
    public bool Demo { get; }
    public string Mode => Demo ? Loc.T("DEMO · Sample data", "演示 · 样例数据") : "";
    public string WindowTitle => $"AUV {ProductInfo.Version}" + (Demo ? " [DEMO — sample data]" : "");
    public AgentPresentation[] QuotaAgents => Shell.Agents.Where(a => a.Card.HasDisplayableQuota).ToArray();
    public bool HasQuotaAgents => QuotaAgents.Length > 0;
    public string DataState => Shell.SelectedAgent.IsDemo ? Loc.T("Sample data · isolated fixture", "样例数据 · 独立夹具") : SelectedCard.Kind == AllowanceKind.Unavailable ? Loc.T("Usage unavailable", "用量不可用") : Loc.T("Verified provider data", "已验证的提供方数据");
    public string WeeklyRemaining => UsageSnapshot.RemainingText(Shell.SelectedAgent.Usage.WeeklyRemaining);
    public string ShortRemaining => Shell.SelectedAgent.SecondaryValue;
    public string SecondaryLabel => Shell.SelectedAgent.SecondaryLabel;
    public double WeeklyValue => UsageSnapshot.ValidRemaining(Shell.SelectedAgent.Usage.WeeklyRemaining) ?? 0;
    public double ShortValue => UsageSnapshot.ValidRemaining(Shell.SelectedAgent.Usage.ShortRemaining) ?? 0;
    public bool HasUsage => SelectedCard.HasDisplayableQuota;
    public bool HasPlan => HasUsage && !string.IsNullOrWhiteSpace(SelectedCard.Plan);
    public bool HasPercentBar => HasUsage && SelectedCard.FillFraction != null;
    public bool HasSecondary => Shell.SelectedAgent.HasSecondaryWindow;
    public bool HasWeekTokens => Shell.SelectedAgent.Usage.AccountWeek is >= 0;
    public bool HasLifetimeTokens => Shell.SelectedAgent.Usage.AccountLifetime is >= 0;
    public bool HasTokenMetrics => HasWeekTokens || HasLifetimeTokens;
    // Local Cost Estimate card: Codex only on Windows, behind the switch (off by default).
    private bool showCostEstimate;
    public bool ShowCostEstimate { get => showCostEstimate; set { if (Set(ref showCostEstimate, value)) CostChanged(); } }
    private LocalCostEstimate? codexCost;
    public LocalCostEstimate? CodexCost { get => codexCost; set { if (Set(ref codexCost, value)) CostChanged(); } }
    private LocalCostEstimate? SelectedCost => ShowCostEstimate && Shell.SelectedAgent.Id == "codex" && !Shell.SelectedAgent.IsDemo ? CodexCost : null;
    public bool HasLocalCost => SelectedCost != null || ShowCostEstimate && Shell.SelectedAgent.Usage.LocalEstimate is >= 0;
    public bool HasData => HasUsage || HasWeekTokens || HasLifetimeTokens || HasChart || HasLocalCost;
    public string RemainingLabel => SelectedCard.Kind == AllowanceKind.Credits ? Loc.T("Balance", "余额") : Loc.T("Remaining", "剩余");
    public string WeekTokens => UsageSnapshot.TokensText(Shell.SelectedAgent.Usage.AccountWeek);
    public string LifetimeTokens => UsageSnapshot.TokensText(Shell.SelectedAgent.Usage.AccountLifetime);
    public string LocalCost => SelectedCost is { } cost ? Money(cost.HasPricedUsage ? cost.SevenDayUsd : null) : Shell.SelectedAgent.Usage.LocalEstimate is decimal demo && ShowCostEstimate ? $"US${demo:0.00}" : "—";
    public string LifetimeCost => SelectedCost is { } cost ? Money(cost.HasPricedUsage ? cost.LifetimeUsd : null) : "—";
    public string CostCoverage => SelectedCost is { } cost ? (cost.PricedCoverage * 100).ToString("0", CultureInfo.InvariantCulture) + "%" : "—";
    public bool CostHasNoPricedModels => SelectedCost is { HasPricedUsage: false };
    private static string Money(decimal? value) => value is decimal v ? "US$" + v.ToString("0.00", CultureInfo.InvariantCulture) : "—";
    public string Source => SelectedCard.Source;
    public string Updated => SelectedCard.Freshness;
    public string ConnectionText => Loc.Connection(SelectedCard.Connection);
    public string FreshnessText => SelectedCard.Kind == AllowanceKind.Unavailable ? Loc.T("Unavailable", "不可用") : SelectedCard.IsStale ? Loc.T("Out of date · hidden", "已过期 · 不显示") : Loc.T("Current", "当前");
    public string UpdatedText => SelectedCard.ObservedAt is { } at ? Relative(DateTimeOffset.UtcNow - at) : Loc.T("Never", "从未");
    private static string Relative(TimeSpan age) => age.TotalSeconds < 60 ? Loc.T("just now", "刚刚") : age.TotalMinutes < 60 ? Loc.T($"{(int)age.TotalMinutes} min ago", $"{(int)age.TotalMinutes} 分钟前") : Loc.T($"{(int)age.TotalHours} hr ago", $"{(int)age.TotalHours} 小时前");
    public DetailRow[] ConnectionRows
    {
        get
        {
            var rows = new List<DetailRow> { new(Loc.T("Status", "状态"), ConnectionText), new(Loc.T("Source", "来源"), Source), new(Loc.T("Freshness", "新鲜度"), FreshnessText) };
            if (HasPlan) rows.Add(new(Loc.T("Plan", "方案"), SelectedCard.Plan!));
            rows.Add(new(Loc.T("Updated", "更新于"), UpdatedText));
            return rows.ToArray();
        }
    }
    public string SettingsButton => Loc.T($"{Shell.SelectedAgent.Name} Settings…", $"{Shell.SelectedAgent.Name} 设置…");
    /// <summary>Usage card rows: every current window, the displayed one marked; Credits as one native row.</summary>
    public UsageRow[] UsageRows
    {
        get
        {
            var agent = Shell.SelectedAgent; var card = agent.Card;
            if (!card.HasDisplayableQuota) return [];
            if (agent.Windows.Count == 0)
                return [new(card.Kind == AllowanceKind.Credits ? card.Window : card.Window, card.Value, card, ResetText.Format(card.ResetsAt, DateTimeOffset.UtcNow), true, card.FillFraction != null)];
            return agent.Windows.OrderBy(w => w.LengthRank).Select(w =>
            {
                var shown = w.Id == agent.Selection?.SelectedId || agent.Selection == null && w.Minutes == card.WindowMinutes;
                var row = new AllowanceCard(card.Id, card.Name, card.Mark, card.Plan, AllowanceKind.Percentage, w.Remaining, null, w.Label, card.Source, card.Freshness, card.Connection, card.IsStale)
                { WindowMinutes = w.Minutes, ResetsAt = w.ResetsAt, ObservedAt = card.ObservedAt };
                return new UsageRow(w.Label + (shown ? Loc.T(" · shown", " · 当前显示") : ""), row.Value, row, ResetText.Format(w.ResetsAt, DateTimeOffset.UtcNow), shown, true);
            }).ToArray();
        }
    }
    public string NoQuotaText => Shell.SelectedAgent.Id switch
    {
        "claude" => Loc.T("No current Claude reading. AUV shows no estimate in its place.", "没有当前的 Claude 读数。AUV 不会用估算值代替。"),
        "antigravity" => Loc.T("Not available on Windows yet. AUV shows no estimate in its place.", "Windows 上暂不可用，AUV 不会用估算值代替。"),
        "workbuddy" => Loc.T("Connect WorkBuddy in its settings, then Sync Credits on the official page.", "请在 WorkBuddy 设置中连接，然后在官方页面同步 Credits。"),
        _ => Loc.T("No quota reading. Check that Codex is installed and signed in, then Refresh All.", "无额度读数。请确认 Codex 已安装并登录，然后全部刷新。")
    };
    /// <summary>0.18.6: the Claude page carries the Connect card and checklist (not in demo mode).</summary>
    public bool IsClaude => !Demo && Shell.SelectedAgent.Id == "claude";
    public string ChartHeading => Loc.T("Daily tokens", "每日令牌");
    public string ChartSummary => Shell.SelectedAgent.TokenSource ?? (Shell.SelectedAgent.IsDemo ? "Local tokens · independent sample source" : Loc.T("No token data available", "没有令牌数据"));
    public string Activity => Shell.SelectedAgent.IsDemo ? "Development fixture loaded. No local sessions were read." : Loc.T("Only admitted allowance and aggregate account data are displayed. No conversation content is read.", "只显示允许范围内的额度和账户汇总数据，不读取任何对话内容。");
    public static string CompactTokens(double tokens) => tokens >= 1_000_000_000 ? $"{tokens / 1_000_000_000:0.##}B" : tokens >= 1_000_000 ? $"{tokens / 1_000_000:0.#}M" : tokens >= 1000 ? $"{tokens / 1000:0.#}k" : $"{tokens:0}";
    public ChartBar[] Bars => Shell.SelectedAgent.Usage.Days.Select(d => new ChartBar(d.Label, CompactTokens(d.Tokens), d.Tokens / Math.Max(1, Shell.SelectedAgent.Usage.Days.Max(x => x.Tokens)) * 100, $"{d.Tokens:N0} tokens · {d.Label}")).ToArray();
    public bool HasChart => Bars.Length > 0;
    private string generated = "";
    public string Generated { get => generated; private set { Set(ref generated, value); CopyCommand.Refresh(); } }
    private string instructionStatus = Loc.T("Choose settings, generate, then copy and paste to your receiving Leader.", "选择设置并生成，然后复制粘贴给接收端的 Leader。");
    public string InstructionStatus { get => instructionStatus; set => Set(ref instructionStatus, value); }
    private string status = Loc.T("Ready", "就绪");
    public string Status { get => status; set => Set(ref status, value); }
    public RelayCommand GenerateCommand { get; }
    public RelayCommand CopyCommand { get; }
    public Action<string>? CopyText { get; set; }
    private static readonly string[] SelectionBound = [nameof(SelectedCard), nameof(PrimaryValue), nameof(DataState), nameof(WeeklyRemaining), nameof(ShortRemaining), nameof(SecondaryLabel), nameof(WeeklyValue), nameof(ShortValue), nameof(HasUsage), nameof(HasPlan), nameof(HasPercentBar), nameof(HasSecondary), nameof(HasWeekTokens), nameof(HasLifetimeTokens), nameof(HasTokenMetrics), nameof(HasLocalCost), nameof(HasData), nameof(RemainingLabel), nameof(WeekTokens), nameof(LifetimeTokens), nameof(LocalCost), nameof(LifetimeCost), nameof(CostCoverage), nameof(CostHasNoPricedModels), nameof(Source), nameof(Updated), nameof(ConnectionText), nameof(FreshnessText), nameof(UpdatedText), nameof(ConnectionRows), nameof(UsageRows), nameof(NoQuotaText), nameof(IsClaude), nameof(SettingsButton), nameof(ChartSummary), nameof(ChartHeading), nameof(Activity), nameof(Bars), nameof(HasChart)];
    private void CostChanged() { foreach (var name in new[] { nameof(HasLocalCost), nameof(HasData), nameof(LocalCost), nameof(LifetimeCost), nameof(CostCoverage), nameof(CostHasNoPricedModels) }) Changed(name); }
    /// <summary>Re-evaluates every computed binding, e.g. after the display language changes.</summary>
    public void RefreshText() { Changed(string.Empty); }
    public MainViewModel(bool demo, PreviewSettings settings)
    {
        Demo = demo; Shell = new(demo, settings.SelectedAgent, settings.ActiveSection); Storage = new(demo);
        if (settings.AgentOrder is { Count: > 0 } order) Shell.Reorder(order);
        Roles = [new(Catalog, "leader", "Leader", "Plan & coordinate", "gpt-6.1-sol", "high"), new(Catalog, "coderCluster", "Coder Cluster", "Build & integrate", "gpt-6-luna", "medium"), new(Catalog, "reviewerCluster", "Reviewer Cluster", "Independent review", "gpt-6-luna", "medium"), new(Catalog, "qa", "QA", "Verify & accept", "gpt-6.1-sol", "high")];
        GenerateCommand = new(() => { Generated = LeaderInstruction.Generate(Catalog, Roles.ToDictionary(r => r.Key, r => r.Selection)); InstructionStatus = Loc.T("Instruction generated locally. Copy and paste to your receiving Leader.", "已在本地生成指令。复制后粘贴给接收端的 Leader。"); });
        CopyCommand = new(() => CopyText?.Invoke(Generated), () => Generated.Length > 0);
        foreach (var role in Roles)
        {
            if (settings.Roles.TryGetValue(role.Key, out var saved)) { role.Model = saved.Model; role.Effort = saved.Effort; }
            role.PropertyChanged += (_, _) => { Generated = ""; InstructionStatus = Loc.T("Draft changed. Generate again before copying.", "草稿已更改，复制前请重新生成。"); };
        }
        Shell.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(ShellState.Agents)) { Changed(nameof(QuotaAgents)); Changed(nameof(HasQuotaAgents)); }
            if (e.PropertyName != nameof(ShellState.SelectedAgent)) return;
            foreach (var name in SelectionBound) Changed(name);
        };
    }
}
