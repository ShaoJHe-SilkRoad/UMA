using System.Diagnostics;
using System.IO;
using System.Windows;
using AUV.Windows.Core;
using Microsoft.Win32;

namespace AUV.Windows.App;

/// <summary>
/// Claude through the browser companion (Chrome/Edge). Off until the person turns it on and sets the companion up (D15).
/// Each sync is a request-correlated read run by <see cref="ClaudeCompanionCoordinator"/>; only a current, verified
/// reading is shown (D8), and a failed sync leaves a still-current reading in place until it goes out of date.
/// </summary>
public sealed partial class ProviderController
{
    private ClaudeBrowserPipeServer? claudeLink;
    private ClaudeCompanionCoordinator? claudeCoordinator;
    private QuotaSelection? claudeSelection;
    private Task? claudeInFlight;
    private bool claudeAskedThisStretch;
    private DateTimeOffset claudeLastAttempt = DateTimeOffset.MinValue;
    private string claudeLastResult = "";

    public ClaudeBrowserSetup ClaudeSetup => new(ClaudeBrowserPaths.InstallRoot(app.Store.PathName), ClaudeBrowserPaths.PackageRoot, ClaudeBrowserPaths.PipeName(app.Store.PathName));
    public string[] ClaudeBrowsers => ClaudeBrowserPreferences.Browsers;
    public string[] ClaudePlacements => ClaudeBrowserPreferences.PlacementChoices;
    public bool ClaudeBrowserEnabled
    {
        get => app.Settings.ClaudeBrowser.Enabled;
        set
        {
            if (value == ClaudeBrowserEnabled) return;
            app.Settings.ClaudeBrowser.Enabled = value; Changed(); main.Persist();
            if (value) { StartClaudeLink(); _ = RefreshClaudeAsync(userInitiated: true); }
            else { StopClaudeLink(); claudeSelection = null; Admit("claude", () => ProviderData.Unavailable("claude", ClaudeBrowserPresentation.Disabled, ConnectionState.Disconnected)); }
            ClaudeChanged();
        }
    }
    public string ClaudeBrowser
    {
        get => app.Settings.ClaudeBrowser.Browser;
        set { if (!ClaudeBrowserPreferences.Browsers.Contains(value) || value == ClaudeBrowser) return; app.Settings.ClaudeBrowser.Browser = value; Changed(); main.Persist(); RestartClaudeLink(); }
    }
    public string ClaudePlacement
    {
        get => app.Settings.ClaudeBrowser.Placement;
        set { if (!ClaudeBrowserPreferences.PlacementChoices.Contains(value) || value == ClaudePlacement) return; app.Settings.ClaudeBrowser.Placement = value; Changed(); main.Persist(); }
    }
    public bool ClaudeAskToOpenBrowser
    {
        get => app.Settings.ClaudeBrowser.AskToOpenBrowser;
        set { if (value == ClaudeAskToOpenBrowser) return; app.Settings.ClaudeBrowser.AskToOpenBrowser = value; Changed(); main.Persist(); }
    }
    /// <summary>One line for Claude settings: the browser connection as AUV sees it right now.</summary>
    public string ClaudeLinkText => !ClaudeBrowserEnabled ? Loc.T("Browser sync is off.", "浏览器同步已关闭。")
        : claudeLink == null ? Loc.T("Not set up yet.", "尚未设置。")
        : claudeLink.State switch
        {
            CompanionLinkState.Connected => Loc.T($"Connected · {ClaudeBrowserPresentation.BrowserName(claudeLink.Host?.BrowserProduct)} · companion {claudeLink.Host?.HostVersion} (build {claudeLink.Host?.HostBuild})",
                $"已连接 · {ClaudeBrowserPresentation.BrowserName(claudeLink.Host?.BrowserProduct)} · 伴侣 {claudeLink.Host?.HostVersion}（构建 {claudeLink.Host?.HostBuild}）"),
            CompanionLinkState.Rejected => ClaudeBrowserPresentation.Message(ClaudeSyncOutcome.UpdateRequired, null),
            _ => Loc.T("Waiting for Chrome or Edge with the AUV companion.", "正在等待装有 AUV 伴侣的 Chrome 或 Edge。")
        };
    public string ClaudeLastResult => claudeLastResult;
    private void ClaudeChanged() { Changed(nameof(ClaudeLinkText)); Changed(nameof(ClaudeLastResult)); }

    private void StartClaude()
    {
        if (!ClaudeBrowserEnabled) { Admit("claude", () => ProviderData.Unavailable("claude", ClaudeBrowserPresentation.Disabled, ConnectionState.Disconnected)); return; }
        StartClaudeLink();
    }

    /// <summary>Opens AUV's pipe for the installed companion. Without an installed companion there is nothing to connect to.</summary>
    private void StartClaudeLink()
    {
        if (disposed || app.Demo || claudeLink != null) return;
        var root = ClaudeBrowserPaths.InstallRoot(app.Store.PathName);
        var installed = ClaudeBrowserPaths.LoadManifest(root);
        if (installed == null)
        {
            Admit("claude", () => ProviderData.Unavailable("claude", ClaudeBrowserPresentation.NotSetUp, ConnectionState.Disconnected));
            ClaudeChanged(); return;
        }
        var link = new ClaudeBrowserPipeServer(ClaudeBrowserPaths.PipeName(app.Store.PathName), installed, ClaudeBrowserPipeServer.InstalledHostOnly(root), () => app.Settings.ClaudeBrowser.Browser);
        var coordinator = new ClaudeCompanionCoordinator(link, installed);
        link.StateChanged += () => main.Dispatcher.BeginInvoke(ClaudeLinkChanged);
        coordinator.SyncRequested += request => main.Dispatcher.BeginInvoke(() => { _ = RefreshClaudeAsync(userInitiated: true); });
        claudeLink = link; claudeCoordinator = coordinator;
        link.Start();
        if (!CurrentClaudeReading()) Admit("claude", () => ClaudeBrowserPresentation.Failure(ClaudeSyncOutcome.NotConnected, null));
        ClaudeChanged();
    }
    private void StopClaudeLink()
    {
        claudeCoordinator?.Dispose(); claudeLink?.Dispose();
        claudeCoordinator = null; claudeLink = null;
        ClaudeChanged();
    }
    internal void RestartClaudeLink()
    {
        StopClaudeLink();
        if (ClaudeBrowserEnabled) { StartClaudeLink(); _ = RefreshClaudeAsync(userInitiated: true); }
    }

    private void ClaudeLinkChanged()
    {
        if (disposed || claudeLink == null) return;
        ClaudeChanged();
        if (claudeLink.State != CompanionLinkState.Connected) return;
        claudeAskedThisStretch = false;
        // A browser that just connected (opened after AUV, or after a prompt) is read at once when Claude has no current reading.
        if (!CurrentClaudeReading() && DateTimeOffset.UtcNow - claudeLastAttempt > TimeSpan.FromSeconds(30)) _ = RefreshClaudeAsync(userInitiated: false);
    }

    private bool CurrentClaudeReading() =>
        main.Model.Shell.Agents.FirstOrDefault(a => a.Id == "claude")?.Card is { HasDisplayableQuota: true } card && ReadingFreshness.IsCurrent(card.ObservedAt, DateTimeOffset.UtcNow, app.Settings.Refresh);

    public Task RefreshClaudeAsync(bool userInitiated)
    {
        if (disposed || app.Demo || !ClaudeBrowserEnabled) return Task.CompletedTask;
        if (claudeInFlight is { IsCompleted: false }) return claudeInFlight;
        return claudeInFlight = ReadClaude(userInitiated);
    }

    private async Task ReadClaude(bool userInitiated)
    {
        if (claudeCoordinator == null) StartClaudeLink();
        var coordinator = claudeCoordinator;
        if (coordinator == null) return;
        claudeLastAttempt = DateTimeOffset.UtcNow;
        var hadReading = CurrentClaudeReading();
        if (!hadReading) Admit("claude", () => ProviderData.Unavailable("claude", ClaudeBrowserPresentation.Syncing, ConnectionState.Reconnecting));
        ClaudeSyncResult result;
        try { result = await coordinator.SyncAsync(app.Settings.ClaudeBrowser.CommandPlacement, lifetime.Token); }
        catch (OperationCanceledException) { return; }
        catch (Exception e) when (e is IOException or CompanionProtocolException or ObjectDisposedException or InvalidOperationException) { result = new(ClaudeSyncOutcome.PageUnreadable); }
        if (disposed || coordinator != claudeCoordinator) return;
        ApplyClaude(result);
        if (result.Outcome == ClaudeSyncOutcome.NotConnected) OfferToOpenBrowser(userInitiated);
    }

    private void ApplyClaude(ClaudeSyncResult result)
    {
        var now = DateTimeOffset.UtcNow;
        if (result is { Outcome: ClaudeSyncOutcome.Success, Observation: { } observation })
        {
            var previous = claudeSelection; var product = result.BrowserProduct;
            var presentation = ClaudeBrowserPresentation.Success(observation, product, now, previous);
            claudeSelection = presentation.Selection;
            // Rebuilt on a language change from the admitted observation only.
            Admit("claude", () => ClaudeBrowserPresentation.Success(observation, product, now, previous));
            claudeLastResult = Loc.T("Last sync: exact figures read ", "上次同步：已读取精确读数 ") + observation.ObservedAt.ToLocalTime().ToString("HH:mm:ss") +
                (result.Attempts > 1 ? Loc.T(" (on the retry)", "（重试时）") : "");
            main.Model.Status = Loc.T("Claude usage synchronized from the browser companion.", "已从浏览器伴侣同步 Claude 用量。");
        }
        else
        {
            var message = ClaudeBrowserPresentation.Message(result.Outcome, result.BrowserProduct);
            // A failed sync does not withdraw a reading that is still current; it goes out of date on the usual schedule.
            if (!CurrentClaudeReading()) Admit("claude", () => ClaudeBrowserPresentation.Failure(result.Outcome, result.BrowserProduct));
            claudeLastResult = Loc.T("Last sync: ", "上次同步：") + message;
            main.Model.Status = "Claude: " + message;
        }
        ClaudeChanged();
    }

    // ---- D9: ask before opening the browser ----

    private static readonly (string Product, string Executable)[] BrowserExecutables = [("chrome", "chrome.exe"), ("edge", "msedge.exe")];
    internal static string? BrowserPath(string product)
    {
        var exe = BrowserExecutables.First(b => b.Product == product).Executable;
        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
        {
            using var key = hive.OpenSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\" + exe);
            if (key?.GetValue(null) is string path && File.Exists(path)) return path;
        }
        return null;
    }
    private static bool BrowserRunning(string product) =>
        Process.GetProcessesByName(product == "edge" ? "msedge" : "chrome") is var found && Dispose(found) > 0;
    private static int Dispose(Process[] processes) { foreach (var p in processes) p.Dispose(); return processes.Length; }
    /// <summary>The browser AUV would open: the chosen one, or under Automatic, Chrome when installed, else Edge.</summary>
    public string? ClaudeTargetBrowser => app.Settings.ClaudeBrowser.Browser is "chrome" or "edge" ? app.Settings.ClaudeBrowser.Browser
        : BrowserPath("chrome") != null ? "chrome" : BrowserPath("edge") != null ? "edge" : null;

    private void OfferToOpenBrowser(bool userInitiated)
    {
        var product = ClaudeTargetBrowser;
        if (product == null || BrowserRunning(product) || BrowserPath(product) == null) return;
        if (!userInitiated && (!ClaudeAskToOpenBrowser || claudeAskedThisStretch)) return;
        claudeAskedThisStretch = true;
        var name = ClaudeBrowserPresentation.BrowserName(product);
        // Shown without blocking: a prompt nobody answers must never hold up Refresh All for other agents.
        var prompt = new ClaudeBrowserPrompt(name, showDontAsk: !userInitiated) { Owner = main.IsVisible ? main : null };
        prompt.Closed += (_, _) =>
        {
            if (prompt.DontAskDuringAutomaticRefresh) ClaudeAskToOpenBrowser = false;
            if (prompt.Accepted) _ = OpenBrowserAndSyncAsync(product);
        };
        prompt.Show();
    }

    private async Task OpenBrowserAndSyncAsync(string product)
    {
        if (!LaunchBrowser(product, null)) { main.Model.Status = Loc.T("The browser could not be opened.", "无法打开浏览器。"); return; }
        // Mac 0.18.4: up to three attempts five seconds apart after the browser starts.
        for (var attempt = 0; attempt < 3 && !disposed; attempt++)
        {
            await Task.Delay(TimeSpan.FromSeconds(5));
            if (claudeLink?.State != CompanionLinkState.Connected) continue;
            await RefreshClaudeAsync(userInitiated: false);
            if (CurrentClaudeReading()) break;
        }
    }

    /// <summary>Starts the browser minimized, optionally at one page such as its extensions page.</summary>
    internal static bool LaunchBrowser(string product, string? page)
    {
        var path = BrowserPath(product);
        if (path == null) return false;
        try
        {
            var start = new ProcessStartInfo(path) { UseShellExecute = true, WindowStyle = page == null ? ProcessWindowStyle.Minimized : ProcessWindowStyle.Normal };
            if (page != null) start.ArgumentList.Add(page);
            Process.Start(start)?.Dispose();
            return true;
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) { return false; }
    }
}

/// <summary>"Open Chrome to update Claude's usage?" The accept button waits a second before it can be clicked (Mac 0.18.4).</summary>
internal sealed class ClaudeBrowserPrompt : Window
{
    public bool Accepted { get; private set; }
    public bool DontAskDuringAutomaticRefresh => dontAsk.IsChecked == true;
    private readonly System.Windows.Controls.CheckBox dontAsk = new() { Content = Loc.T("Don't ask during automatic refresh", "自动刷新时不再询问"), Margin = new Thickness(0, 12, 0, 0) };
    public ClaudeBrowserPrompt(string browser, bool showDontAsk)
    {
        var app = (App)Application.Current;
        Title = "AUV"; Width = 440; SizeToContent = SizeToContent.Height; ResizeMode = ResizeMode.NoResize; ShowInTaskbar = true;
        WindowStartupLocation = WindowStartupLocation.CenterScreen; Topmost = true;
        var accept = new System.Windows.Controls.Button { Content = Loc.T($"Open {browser}", $"打开 {browser}"), IsEnabled = false, IsDefault = true, MinWidth = 110 };
        var later = new System.Windows.Controls.Button { Content = Loc.T("Not Now", "暂不"), IsCancel = true, MinWidth = 90, Margin = new Thickness(8, 0, 0, 0) };
        accept.Click += (_, _) => { Accepted = true; Close(); };
        later.Click += (_, _) => Close();
        var buttons = new System.Windows.Controls.StackPanel { Orientation = System.Windows.Controls.Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        buttons.Children.Add(accept); buttons.Children.Add(later);
        var body = new System.Windows.Controls.StackPanel { Margin = new Thickness(20) };
        body.Children.Add(new System.Windows.Controls.TextBlock { Text = Loc.T($"Open {browser} to update Claude's usage?", $"打开 {browser} 以更新 Claude 用量？"), FontSize = 16, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        body.Children.Add(new System.Windows.Controls.TextBlock { Text = Loc.T($"AUV reads Claude's figures through its companion in {browser}, which is not running. {browser} opens minimized; AUV then reads claude.ai's Usage page in a background tab and closes it.",
            $"AUV 通过 {browser} 中的伴侣读取 Claude 读数，但 {browser} 当前没有运行。{browser} 会以最小化方式打开，随后 AUV 在后台标签页中读取 claude.ai 用量页并关闭该标签页。"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 8, 0, 0) });
        if (showDontAsk) body.Children.Add(dontAsk);
        body.Children.Add(buttons);
        Content = body;
        Background = (System.Windows.Media.Brush)app.Resources["CanvasBrush"]; Foreground = (System.Windows.Media.Brush)app.Resources["TextBrush"];
        SourceInitialized += (_, _) => { NativeAppearance.Apply(this, app.IsDark); AppBrandIcon.Apply(this, app.IsDark); };
        Loaded += async (_, _) => { await Task.Delay(1000); accept.IsEnabled = true; };
    }
}
