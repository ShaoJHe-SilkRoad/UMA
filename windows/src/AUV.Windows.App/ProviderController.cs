using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;
using AUV.Windows.Core;

namespace AUV.Windows.App;

/// <summary>One provider admission point, shared by main, tray and Wizard.</summary>
public sealed class ProviderController : Observable, IDisposable
{
    private readonly App app;
    private readonly MainWindow main;
    private readonly CodexAppServer codex = new();
    private readonly IReadOnlyDictionary<string, IReadOnlyUsageConnector> prepared = PreparedConnections.Plans
        .ToDictionary(p => p.ProviderId, p => (IReadOnlyUsageConnector)new PreparedUsageConnector(p));
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMinutes(1) };
    private CancellationTokenSource lifetime = new();
    private Task? inFlight;
    private WorkBuddyConnectionWindow? workBuddy;
    private DateTimeOffset? workBuddyReadAt;
    private bool disposed, busy;
    private int generation;
    public bool Busy { get => busy; private set { if (Set(ref busy, value)) Changed(nameof(RefreshLabel)); } }
    public string RefreshLabel => Busy ? "Refreshing…" : "Refresh usage";
    public bool CodexEnabled
    {
        get => app.Settings.Providers.CodexEnabled;
        set
        {
            if (value == CodexEnabled) return;
            app.Settings.Providers.CodexEnabled = value; Changed(); main.Persist();
            generation++; lifetime.Cancel(); lifetime.Dispose(); lifetime = new(); codex.Dispose(); inFlight = null;
            if (value) _ = RefreshCodexAsync();
            else Admit(ProviderData.Unavailable("codex", "Codex reading is disabled in AUV.", ConnectionState.Disconnected));
        }
    }
    public string CodexExecutable { get => app.Settings.Providers.CodexExecutable ?? ""; set { app.Settings.Providers.CodexExecutable = string.IsNullOrWhiteSpace(value) ? null : value.Trim(); Changed(); Changed(nameof(ResolvedCodex)); main.Persist(); } }
    public string ResolvedCodex => CodexAppServer.ResolveExecutable(app.Settings.Providers.CodexExecutable) ?? "Not found";
    internal object Diagnostics => new { codex.OwnedProcessId, Methods = codex.Methods.Order().ToArray(), RefreshInFlight = inFlight is { IsCompleted: false } };
    public ProviderController(App app, MainWindow main)
    {
        this.app = app; this.main = main;
        timer.Tick += (_, _) =>
        {
            if (CodexEnabled) _ = RefreshCodexAsync();
            if (workBuddyReadAt is { } observed && DateTimeOffset.UtcNow - observed > TimeSpan.FromMinutes(10))
            {
                var current = main.Model.Shell.Agents.First(a => a.Id == "workbuddy");
                if (current.Card.Kind != AllowanceKind.Unavailable && !current.Card.IsStale)
                    Admit(new(current.Id, current.Name, current.Monogram, current.Usage, false, current.Card with { IsStale = true, Connection = ConnectionState.Stale }));
            }
        };
    }
    public void Start()
    {
        if (app.Demo) return;
        timer.Start(); if (CodexEnabled) _ = RefreshCodexAsync();
    }
    public Task RefreshCodexAsync()
    {
        if (disposed || app.Demo || !CodexEnabled) return Task.CompletedTask;
        if (inFlight is { IsCompleted: false }) return inFlight;
        return inFlight = ReadCodex();
    }
    private async Task ReadCodex()
    {
        var current = generation; Busy = true;
        try
        {
            var result = await codex.ReadAsync(app.Settings.Providers.CodexExecutable, lifetime.Token);
            if (disposed || generation != current) return;
            Admit(result); main.Model.Status = result.Card.Connection == ConnectionState.Connected ? "Codex usage refreshed from the local client." : result.Card.Source;
        }
        catch (Exception e) when (e is OperationCanceledException or IOException or UnauthorizedAccessException or JsonException or CodexRpcException or System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            if (disposed || generation != current) return;
            var message = e is OperationCanceledException ? "Codex usage read timed out. Refresh to retry." : "Codex usage could not be verified. Check the installed client and sign-in, then refresh.";
            Admit(ProviderData.Unavailable("codex", message, ConnectionState.Failed)); main.Model.Status = message;
        }
        finally { if (!disposed) Busy = false; }
    }
    internal void Admit(AgentPresentation presentation)
    {
        if (disposed) return;
        main.Model.Shell.ReplaceAdmittedPresentation(main.Model.Shell.Agents.Select(a => a.Id == presentation.Id ? presentation : a).ToArray());
    }
    public void OpenWorkBuddy()
    {
        if (app.Demo) { main.Model.Status = "Live connections are disabled in demo mode."; return; }
        app.Settings.Providers.WorkBuddyConsent = true; main.Persist();
        if (workBuddy == null) { workBuddy = new(this, app.Store.PathName) { Owner = main }; workBuddy.Closed += (_, _) => workBuddy = null; }
        workBuddy.Show(); workBuddy.Activate();
    }
    internal void WorkBuddyUnavailable(string reason)
    { workBuddyReadAt = null; Admit(ProviderData.Unavailable("workbuddy", reason)); }
    internal void AdmitWorkBuddy(AgentPresentation result)
    { workBuddyReadAt = DateTimeOffset.UtcNow; Admit(result); main.Model.Status = "WorkBuddy Credits synchronized from the official page."; }
    public async Task RefreshSelectedAsync()
    {
        var id = main.Model.Shell.SelectedAgent.Id;
        if (id == "codex") { if (!CodexEnabled) CodexEnabled = true; await RefreshCodexAsync(); }
        else if (id == "workbuddy") { OpenWorkBuddy(); }
        else if (prepared.TryGetValue(id, out var connector))
        {
            Admit(await connector.ReadAsync(lifetime.Token));
            main.Model.Status = PreparedConnections.Find(id)!.UserStatus;
        }
    }
    public async Task DisconnectWorkBuddyAsync()
    {
        app.Settings.Providers.WorkBuddyConsent = false; main.Persist();
        WorkBuddyUnavailable("WorkBuddy disconnected from AUV.");
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
    { if (disposed) return; disposed = true; timer.Stop(); generation++; lifetime.Cancel(); codex.Dispose(); workBuddy?.Close(); lifetime.Dispose(); }
}
