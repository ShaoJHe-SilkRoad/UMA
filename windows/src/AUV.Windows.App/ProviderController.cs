using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;
using AUV.Windows.Core;
using Microsoft.Win32;

namespace AUV.Windows.App;

/// <summary>One provider admission point, shared by main, tray and Wizard. Owns the single refresh schedule.</summary>
public sealed partial class ProviderController : Observable, IDisposable
{
    private readonly App app;
    private readonly MainWindow main;
    private readonly CodexAppServer codex = new();
    private readonly CodexLocalCostEstimator costEstimator = new();
    private readonly IReadOnlyDictionary<string, IReadOnlyUsageConnector> prepared = PreparedConnections.Plans
        .ToDictionary(p => p.ProviderId, p => (IReadOnlyUsageConnector)new PreparedUsageConnector(p));
    private readonly DispatcherTimer refreshTimer = new();
    private readonly DispatcherTimer freshnessTimer = new() { Interval = TimeSpan.FromSeconds(30) };
    private readonly Dictionary<string, Func<AgentPresentation>> rebuild = [];
    private CancellationTokenSource lifetime = new();
    private Task? inFlight, allInFlight, costInFlight;
    private WorkBuddyConnectionWindow? workBuddy;
    private QuotaSelection? codexSelection;
    private bool disposed, busy, started;
    private int generation;
    public int AutomaticRefreshCount { get; private set; }
    public DateTimeOffset? LastAutomaticRefresh { get; private set; }
    public bool Busy { get => busy; private set { if (Set(ref busy, value)) Changed(nameof(RefreshLabel)); } }
    public string RefreshLabel => Busy ? Loc.T("Refreshing…", "正在刷新…") : Loc.T("Refresh All", "全部刷新");
    public bool CodexEnabled
    {
        get => app.Settings.Providers.CodexEnabled;
        set
        {
            if (value == CodexEnabled) return;
            app.Settings.Providers.CodexEnabled = value; Changed(); main.Persist();
            generation++; lifetime.Cancel(); lifetime.Dispose(); lifetime = new(); codex.Dispose(); inFlight = null; codexSelection = null;
            if (value) _ = RefreshCodexAsync();
            else Admit("codex", () => ProviderData.Unavailable("codex", Loc.T("Codex monitoring is turned off in AUV.", "已在 AUV 中关闭 Codex 监控。"), ConnectionState.Disconnected));
        }
    }
    public string CodexExecutable { get => app.Settings.Providers.CodexExecutable ?? ""; set { app.Settings.Providers.CodexExecutable = string.IsNullOrWhiteSpace(value) ? null : value.Trim(); Changed(); Changed(nameof(ResolvedCodex)); main.Persist(); } }
    public string ResolvedCodex => CodexAppServer.ResolveExecutable(app.Settings.Providers.CodexExecutable) ?? Loc.T("Not found", "未找到");
    // Refresh pane
    public bool AutomaticRefresh { get => app.Settings.Refresh.Automatic; set { if (value == AutomaticRefresh) return; app.Settings.Refresh.Automatic = value; Changed(); main.Persist(); Reschedule(); } }
    public int[] Intervals => RefreshPreferences.Intervals;
    public int RefreshInterval
    {
        get => app.Settings.Refresh.IntervalMinutes;
        set { if (!RefreshPreferences.Intervals.Contains(value) || value == RefreshInterval) return; app.Settings.Refresh.IntervalMinutes = value; Changed(); main.Persist(); Reschedule(); }
    }
    public bool RefreshOnWake { get => app.Settings.Refresh.OnWake; set { app.Settings.Refresh.OnWake = value; Changed(); main.Persist(); } }
    public TimeSpan ScheduledInterval => refreshTimer.Interval;
    public bool ScheduleActive => refreshTimer.IsEnabled;
    // Local Cost Estimate (off by default; hidden while off)
    public bool ShowCostEstimate
    {
        get => app.Settings.ShowCostEstimate;
        set
        {
            if (value == ShowCostEstimate) return;
            app.Settings.ShowCostEstimate = value; main.Model.ShowCostEstimate = value; Changed(); main.Persist();
            if (value) _ = RefreshCostAsync(); else main.Model.CodexCost = null;
        }
    }
    internal object Diagnostics => new { codex.OwnedProcessId, Methods = codex.Methods.Order().ToArray(), RefreshInFlight = inFlight is { IsCompleted: false },
        ScheduleMinutes = ScheduleActive ? refreshTimer.Interval.TotalMinutes : (double?)null, AutomaticRefreshCount };
    public ProviderController(App app, MainWindow main)
    {
        this.app = app; this.main = main;
        main.Model.ShowCostEstimate = app.Settings.ShowCostEstimate;
        refreshTimer.Tick += async (_, _) => { AutomaticRefreshCount++; LastAutomaticRefresh = DateTimeOffset.Now; await RefreshAllAsync(automatic: true); };
        freshnessTimer.Tick += (_, _) => EnforceFreshness(DateTimeOffset.UtcNow);
        UiText.Changed += Relocalize;
        SystemEvents.PowerModeChanged += PowerModeChanged;
    }
    public void Start()
    {
        if (app.Demo || started) return;
        started = true;
        foreach (var plan in PreparedConnections.Plans) { var id = plan.ProviderId; Admit(id, () => ProviderData.Unavailable(id, plan.UserStatus)); }
        StartClaude();
        freshnessTimer.Start(); Reschedule();
        _ = RefreshAllAsync(automatic: false);
    }
    private void Reschedule()
    {
        refreshTimer.Stop();
        if (disposed || app.Demo || !started || !app.Settings.Refresh.Automatic) { Changed(nameof(ScheduleActive)); return; }
        refreshTimer.Interval = TimeSpan.FromMinutes(app.Settings.Refresh.IntervalMinutes); refreshTimer.Start();
        Changed(nameof(ScheduleActive)); Changed(nameof(ScheduledInterval));
    }
    /// <summary>For verification: run the schedule at a test interval without changing the saved preference.</summary>
    internal void OverrideSchedule(TimeSpan interval) { refreshTimer.Stop(); refreshTimer.Interval = interval; refreshTimer.Start(); }
    internal void RestoreSchedule() => Reschedule();
    private void PowerModeChanged(object sender, PowerModeChangedEventArgs e)
    {
        if (e.Mode != PowerModes.Resume) return;
        main.Dispatcher.BeginInvoke(async () => { if (!disposed && app.Settings.Refresh.OnWake) await RefreshAllAsync(automatic: true); });
    }
    /// <summary>Refresh All: every agent that can be read without opening a window. WorkBuddy syncs only while its connection window is open.</summary>
    public Task RefreshAllAsync(bool automatic = false)
    {
        if (disposed) return Task.CompletedTask;
        if (app.Demo) { main.Model.Status = Loc.T("Live connections are disabled in demo mode.", "演示模式下不连接真实账户。"); return Task.CompletedTask; }
        if (allInFlight is { IsCompleted: false }) return allInFlight;
        return allInFlight = RunAll(automatic);
    }
    private async Task RunAll(bool automatic)
    {
        Busy = true;
        try
        {
            var work = new List<Task>();
            if (CodexEnabled) work.Add(RefreshCodexAsync());
            if (ClaudeBrowserEnabled) work.Add(RefreshClaudeAsync(userInitiated: !automatic));
            if (workBuddy is { IsVisible: true } open) work.Add(open.SyncAsync());
            if (ShowCostEstimate) work.Add(RefreshCostAsync());
            await Task.WhenAll(work);
            if (!disposed && !automatic) main.Model.Status = Loc.T("Refreshed every agent that AUV can read.", "已刷新 AUV 能读取的所有智能体。");
        }
        finally { if (!disposed) Busy = false; }
    }
    public Task RefreshCodexAsync()
    {
        if (disposed || app.Demo || !CodexEnabled) return Task.CompletedTask;
        if (inFlight is { IsCompleted: false }) return inFlight;
        return inFlight = ReadCodex();
    }
    private async Task ReadCodex()
    {
        var current = generation;
        try
        {
            AgentPresentation result;
            try { result = await codex.ReadAsync(app.Settings.Providers.CodexExecutable, codexSelection, lifetime.Token); }
            catch (IOException) when (!lifetime.IsCancellationRequested && generation == current)
            {
                // 0.17.5 parity: the app-server exiting or being replaced is an ordinary end of stream. Reconnect once.
                result = await codex.ReadAsync(app.Settings.Providers.CodexExecutable, codexSelection, lifetime.Token);
            }
            if (disposed || generation != current) return;
            if (result.Card.Connection == ConnectionState.Connected) codexSelection = result.Selection;
            var snapshot = result; Admit("codex", () => snapshot);
            main.Model.Status = result.Card.Connection == ConnectionState.Connected ? Loc.T("Codex usage refreshed from the local client.", "已从本地客户端刷新 Codex 用量。") : result.Card.Source;
        }
        catch (Exception e) when (e is OperationCanceledException or IOException or InvalidDataException or UnauthorizedAccessException or JsonException or CodexRpcException or System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            if (disposed || generation != current) return;
            var timedOut = e is OperationCanceledException;
            Admit("codex", () => ProviderData.Unavailable("codex", timedOut ? Loc.T("Codex usage read timed out. Refresh to retry.", "读取 Codex 用量超时，请刷新重试。")
                : Loc.T("Codex usage could not be verified. Check the installed client and sign-in, then refresh.", "无法验证 Codex 用量。请检查已安装的客户端和登录状态，然后刷新。"), ConnectionState.Failed));
            main.Model.Status = main.Model.Shell.Agents.First(a => a.Id == "codex").Card.Source;
        }
    }
    public Task RefreshCostAsync()
    {
        if (disposed || app.Demo || !ShowCostEstimate) return Task.CompletedTask;
        if (costInFlight is { IsCompleted: false }) return costInFlight;
        return costInFlight = ComputeCost();
    }
    private async Task ComputeCost()
    {
        var token = lifetime.Token;
        try
        {
            var estimate = await Task.Run(() => costEstimator.Estimate(CodexLocalCostEstimator.DefaultRoots(), DateTimeOffset.Now, TimeZoneInfo.Local, token), token);
            if (!disposed && ShowCostEstimate) main.Model.CodexCost = estimate;
        }
        catch (OperationCanceledException) { }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { if (!disposed) main.Model.CodexCost = null; }
    }
    private void EnforceFreshness(DateTimeOffset now)
    {
        if (disposed) return;
        foreach (var agent in main.Model.Shell.Agents.ToArray())
        {
            var card = agent.Card;
            if (card.Kind == AllowanceKind.Unavailable || card.IsStale || card.Connection != ConnectionState.Connected || card.ObservedAt == null) continue;
            var current = agent.Id == "workbuddy" ? now - card.ObservedAt <= TimeSpan.FromMinutes(10) : ReadingFreshness.IsCurrent(card.ObservedAt, now, app.Settings.Refresh);
            if (current) continue;
            // Stale readings are withdrawn from every surface (Windows fresh-only rule) until the next successful read.
            var stale = new AgentPresentation(agent.Id, agent.Name, agent.Monogram, agent.Usage, false, card with { IsStale = true, Connection = ConnectionState.Stale },
                agent.SecondaryLabel, agent.SecondaryValue, agent.TokenSource) { Selection = agent.Selection, Windows = agent.Windows };
            Admit(agent.Id, () => stale);
        }
    }
    internal void Admit(AgentPresentation presentation) => Admit(presentation.Id, () => presentation);
    private void Admit(string id, Func<AgentPresentation> build)
    {
        if (disposed) return;
        rebuild[id] = build; var presentation = build();
        main.Model.Shell.ReplaceAdmittedPresentation(main.Model.Shell.Agents.Select(a => a.Id == presentation.Id ? presentation : a).ToArray());
    }
    private void Relocalize()
    {
        if (disposed) return;
        main.Dispatcher.BeginInvoke(() =>
        {
            if (disposed) return;
            Changed(nameof(RefreshLabel)); Changed(nameof(ResolvedCodex));
            if (app.Demo) { main.Model.Shell.ReplaceAdmittedPresentation(AgentOrdering.Apply(AgentPresentation.Create(true), a => a.Id, app.Settings.AgentOrder.Count > 0 ? app.Settings.AgentOrder : AgentCatalog.DefaultOrder).ToArray()); return; }
            foreach (var pair in rebuild.ToArray()) if (pair.Key != "codex" || !CodexEnabled) Admit(pair.Key, pair.Value);
            Changed(nameof(RefreshLabel)); Changed(nameof(ResolvedCodex));
            // Codex text is produced at decode time; read again so labels follow the new language.
            if (CodexEnabled) _ = RefreshCodexAsync();
        });
    }
    public void OpenWorkBuddy()
    {
        if (app.Demo) { main.Model.Status = Loc.T("Live connections are disabled in demo mode.", "演示模式下不连接真实账户。"); return; }
        app.Settings.Providers.WorkBuddyConsent = true; main.Persist();
        if (workBuddy == null) { workBuddy = new(this, app.Store.PathName) { Owner = main }; workBuddy.Closed += (_, _) => workBuddy = null; }
        workBuddy.Show(); workBuddy.Activate();
    }
    internal void WorkBuddyUnavailable(string reason)
    { Admit("workbuddy", () => ProviderData.Unavailable("workbuddy", reason)); }
    internal void AdmitWorkBuddy(Func<AgentPresentation> decode)
    { Admit("workbuddy", decode); main.Model.Status = Loc.T("WorkBuddy Credits synchronized from the official page.", "已从官方页面同步 WorkBuddy Credits。"); }
    public async Task RefreshSelectedAsync()
    {
        var id = main.Model.Shell.SelectedAgent.Id;
        if (id == "codex") { if (!CodexEnabled) CodexEnabled = true; await RefreshCodexAsync(); }
        else if (id == "workbuddy") { OpenWorkBuddy(); }
        else if (id == "claude") { if (ClaudeBrowserEnabled) await RefreshClaudeAsync(userInitiated: true); else main.Model.Status = ClaudeBrowserPresentation.Disabled; }
        else if (prepared.TryGetValue(id, out var connector))
        {
            Admit(await connector.ReadAsync(lifetime.Token));
            main.Model.Status = PreparedConnections.Find(id)!.UserStatus;
        }
    }
    public async Task DisconnectWorkBuddyAsync()
    {
        app.Settings.Providers.WorkBuddyConsent = false; main.Persist();
        WorkBuddyUnavailable(Loc.T("WorkBuddy disconnected from AUV.", "已断开 WorkBuddy 与 AUV 的连接。"));
        if (workBuddy != null) await workBuddy.ClearSessionAsync();
        else
        {
            // Create the same owned profile, clear only that profile, then dispose the hidden controller.
            using var view = new Microsoft.Web.WebView2.Wpf.WebView2();
            await view.EnsureCoreWebView2Async(await WorkBuddyConnectionWindow.EnvironmentFor(app.Store.PathName));
            await view.CoreWebView2.Profile.ClearBrowsingDataAsync();
        }
    }
    public void Dispose()
    {
        if (disposed) return; disposed = true; refreshTimer.Stop(); freshnessTimer.Stop(); generation++; lifetime.Cancel(); codex.Dispose(); workBuddy?.Close(); StopClaudeLink(); lifetime.Dispose();
        UiText.Changed -= Relocalize; SystemEvents.PowerModeChanged -= PowerModeChanged;
    }
}
