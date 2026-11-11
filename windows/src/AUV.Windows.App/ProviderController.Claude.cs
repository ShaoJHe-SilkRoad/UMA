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
    private Func<string> claudeLastResult = () => "";
    private bool claudeSyncOnConnect;
    // 0.18.6: one spacing for every request that asks an extension from another build to reload itself.
    private readonly CompanionReloadThrottle claudeReloads = new();
    private CompanionStatus? claudeStatus;
    private ClaudeSyncOutcome? claudeLastOutcome;
    private string? claudeLastProduct;
    private string claudeHint = "";
    private string? claudeUpdateFailure;
    /// <summary>Verification only: a staged package and a throwaway HKCU key instead of the shipped package and the browsers' keys.</summary>
    internal string? ClaudePackageRootOverride { get; set; }
    internal string? ClaudeRegistryBaseOverride { get; set; }

    public ClaudeBrowserSetup ClaudeSetup => new(ClaudeBrowserPaths.InstallRoot(app.Store.PathName), ClaudePackageRootOverride ?? ClaudeBrowserPaths.PackageRoot,
        ClaudeBrowserPaths.PipeName(app.Store.PathName), null, ClaudeRegistryBaseOverride ?? "Software");
    public string[] ClaudeBrowsers => ClaudeBrowserPreferences.Browsers;
    public string[] ClaudePlacements => ClaudeBrowserPreferences.PlacementChoices;
    public bool ClaudeBrowserEnabled
    {
        get => app.Settings.ClaudeBrowser.Enabled;
        set
        {
            if (value == ClaudeBrowserEnabled) return;
            app.Settings.ClaudeBrowser.Enabled = value; Changed(); main.Persist();
            if (value) { claudeSyncOnConnect = true; StartClaudeLink(); _ = RefreshClaudeAsync(userInitiated: true); }
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
            CompanionLinkState.Rejected => ClaudeBrowserPresentation.Message(ClaudeSyncOutcome.UpdateRequired, claudeLink.RejectedHost?.BrowserProduct),
            _ => Loc.T("Waiting for Chrome or Edge with the AUV companion.", "正在等待装有 AUV 伴侣的 Chrome 或 Edge。")
        };
    public string ClaudeLastResult => claudeLastResult();

    // ---- 0.18.6: Connect card, three-step checklist, failure actions ----

    internal CompanionStatus? ClaudeInstallStatus => claudeStatus;
    private void RefreshClaudeStatus()
    {
        try { claudeStatus = ClaudeSetup.Status(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException) { claudeStatus = null; }
    }
    private bool ClaudeInstalledAndRegistered => claudeStatus is { Installed: not null, Registered: true };
    public ClaudeChecklist ClaudeChecklist => ClaudeChecklist.Derive(claudeStatus?.Registered == true, app.Settings.ClaudeBrowser.LoadedBrowsers,
        app.Settings.ClaudeBrowser.ExactReadingSeen, claudeLink?.State == CompanionLinkState.Connected ? claudeLink.Host?.BrowserProduct : null,
        main.Model.Shell.Agents.FirstOrDefault(a => a.Id == "claude")?.Card is { HasDisplayableQuota: true } card ? card.ObservedAt : null);
    /// <summary>The Connect card: shown until Claude sync is on and the companion is installed and registered.</summary>
    public bool ClaudeShowConnect => !app.Demo && (!ClaudeBrowserEnabled || !ClaudeInstalledAndRegistered);
    public bool ClaudeConnectAvailable => claudeStatus?.Packaged != null;
    public string ClaudeConnectLabel => ClaudeBrowserEnabled && claudeStatus is { Installed: not null, Registered: false } ? Loc.T("Repair", "修复") : Loc.T("Connect", "连接");
    public string ClaudeConnectText => !ClaudeConnectAvailable ? ClaudeBrowserPresentation.NotPackaged
        : Loc.T("Read Claude's 5-hour and weekly limits through Chrome or Edge.", "通过 Chrome 或 Edge 读取 Claude 的 5 小时与每周额度。");
    public bool ClaudeShowChecklist => !app.Demo && !ClaudeShowConnect && !ClaudeChecklist.Complete;
    public bool ClaudeShowSummary => !app.Demo && !ClaudeShowConnect && ClaudeChecklist.Complete;
    public string ClaudeSummary => ClaudeChecklist.Summary;
    public bool ClaudeStep1Done => ClaudeChecklist.Registered;
    public bool ClaudeStep2Done => ClaudeChecklist.ExtensionLoaded;
    public bool ClaudeStep3Done => ClaudeChecklist.SignedIn;
    public string ClaudeStep2Text => ClaudeChecklist.ExtensionLoaded
        ? Loc.T($"Extension loaded in {string.Join(" and ", ClaudeChecklist.LoadedBrowsers.Select(ClaudeBrowserPresentation.BrowserName))}", $"已在 {string.Join(" 和 ", ClaudeChecklist.LoadedBrowsers.Select(ClaudeBrowserPresentation.BrowserName))} 中加载扩展")
        : Loc.T("Load the extension in Chrome or Edge", "在 Chrome 或 Edge 中加载扩展");
    public string ClaudeStep3Text => ClaudeChecklist.SignedIn ? Loc.T("Signed in to claude.ai", "已登录 claude.ai") : Loc.T("Sign in to claude.ai", "登录 claude.ai");
    public string ClaudeHint => claudeHint;
    public bool HasClaudeHint => claudeHint.Length > 0;
    public string ClaudeUpdateFailure => claudeUpdateFailure ?? "";
    public bool HasClaudeUpdateFailure => claudeUpdateFailure != null && !app.Demo;
    /// <summary>The reason the last sync failed, shown with a matching action while Claude has no current reading.</summary>
    public bool HasClaudeFailure => !app.Demo && ClaudeBrowserEnabled && !ClaudeShowConnect && claudeLastOutcome is { } outcome && outcome != ClaudeSyncOutcome.Success && !CurrentClaudeReading();
    public string ClaudeFailureText => claudeLastOutcome is { } outcome ? ClaudeBrowserPresentation.Message(outcome, claudeLastProduct) : "";
    public ClaudeRemedy ClaudeRemedy => claudeLastOutcome is { } outcome ? ClaudeBrowserPresentation.Remedy(outcome) : ClaudeRemedy.None;
    // While the checklist is shown its step-3 button already opens claude.ai.
    public bool HasClaudeRemedy => HasClaudeFailure && ClaudeRemedy != ClaudeRemedy.None && !(ClaudeRemedy == ClaudeRemedy.OpenClaude && ClaudeShowChecklist);
    /// <summary>The live link line in Claude settings: hidden under the Connect card, and beside the summary unless a browser is connected.</summary>
    public bool ClaudeCanSync => !ClaudeShowConnect;
    public bool ClaudeShowLinkText => !ClaudeShowConnect && (!ClaudeShowSummary || claudeLink?.State == CompanionLinkState.Connected);
    public string ClaudeRemedyLabel => ClaudeBrowserPresentation.RemedyLabel(ClaudeRemedy, RemedyBrowser);
    private string? RemedyBrowser => claudeLastProduct is "chrome" or "edge" ? claudeLastProduct : ClaudeTargetBrowser;

    private static readonly string[] ClaudeBound =
    [
        nameof(ClaudeLinkText), nameof(ClaudeLastResult), nameof(ClaudeChecklist), nameof(ClaudeShowConnect), nameof(ClaudeConnectAvailable), nameof(ClaudeConnectLabel),
        nameof(ClaudeConnectText), nameof(ClaudeShowChecklist), nameof(ClaudeShowSummary), nameof(ClaudeSummary), nameof(ClaudeStep1Done), nameof(ClaudeStep2Done),
        nameof(ClaudeStep3Done), nameof(ClaudeStep2Text), nameof(ClaudeStep3Text), nameof(ClaudeHint), nameof(HasClaudeHint), nameof(ClaudeUpdateFailure),
        nameof(HasClaudeUpdateFailure), nameof(HasClaudeFailure), nameof(ClaudeFailureText), nameof(ClaudeRemedy), nameof(HasClaudeRemedy), nameof(ClaudeRemedyLabel), nameof(ClaudeShowLinkText), nameof(ClaudeCanSync)
    ];
    internal void ClaudeChanged() { RefreshClaudeStatus(); foreach (var name in ClaudeBound) Changed(name); }
    private void SetClaudeHint(string text) { claudeHint = text; Changed(nameof(ClaudeHint)); Changed(nameof(HasClaudeHint)); }

    internal void MarkClaudeLoaded(string? product)
    {
        var browsers = app.Settings.ClaudeBrowser.LoadedBrowsers;
        if (product is not ("chrome" or "edge" or "unknown") || browsers.Contains(product)) return;
        browsers.Add(product); browsers.Sort(StringComparer.Ordinal); main.Persist();
        // The "load the extension" hint has done its job.
        SetClaudeHint("");
    }

    /// <summary>
    /// Connect (or Repair): copy the packaged companion, register it for Chrome and Edge (HKCU), then turn Claude sync on.
    /// AUV's own companion registered from another folder is replaced without asking; another program's registration is
    /// replaced only when <paramref name="replaceForeign"/> is true. Throws <see cref="ForeignRegistrationException"/> otherwise.
    /// </summary>
    internal ClaudeCompanionManifest InstallAndEnableClaude(bool replaceForeign)
    {
        var manifest = ClaudeSetup.Install(replaceForeign);
        app.Settings.ClaudeBrowser.InstalledBuild = manifest.CompanionBuild; main.Persist();
        claudeUpdateFailure = null;
        // Turned on without an immediate read: the extension is not loaded yet, so a read would only ask to open a browser.
        // AUV reads as soon as a browser connects.
        if (!ClaudeBrowserEnabled) { app.Settings.ClaudeBrowser.Enabled = true; Changed(nameof(ClaudeBrowserEnabled)); main.Persist(); }
        RestartClaudeLink();
        SetClaudeHint(Loc.T("Registered for Chrome and Edge. Next, load the extension in your browser.", "已为 Chrome 和 Edge 注册。下一步：在浏览器中加载扩展。"));
        ClaudeChanged();
        return manifest;
    }

    /// <summary>The Connect button: one confirmation, and a second question only for another program's registration.</summary>
    internal bool ConnectClaude(Window? owner)
    {
        var setup = ClaudeSetup;
        var consent = MessageBox.Show(owner ?? main, Loc.T(
            $"Connect Claude?\n\nAUV will:\n\n• copy the companion extension and its helper to\n  {setup.InstallRoot}\n• register the helper for Chrome and Edge under your Windows account (HKEY_CURRENT_USER), no administrator rights needed.\n\nAn earlier copy is kept as a backup.",
            $"连接 Claude？\n\nAUV 将会：\n\n• 把伴侣扩展及其辅助程序复制到\n  {setup.InstallRoot}\n• 在你的 Windows 账户下（HKEY_CURRENT_USER）为 Chrome 和 Edge 注册该辅助程序，不需要管理员权限。\n\n之前的副本会保留为备份。"),
            "AUV", MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel);
        return consent == MessageBoxResult.OK && InstallInteractively(owner);
    }

    /// <summary>Install, asking only about another program's registration. Used by Connect and by Retry after a failed start-up update.</summary>
    internal bool InstallInteractively(Window? owner)
    {
        try
        {
            try { InstallAndEnableClaude(false); }
            catch (ForeignRegistrationException foreign)
            {
                var names = string.Join(", ", foreign.Browsers.Select(ClaudeBrowserPresentation.BrowserName));
                if (MessageBox.Show(owner ?? main, Loc.T($"Another program registered the same companion name for {names}. Replace that registration with AUV's? The other program's files are not touched.",
                        $"另有程序在 {names} 中注册了同一个伴侣名称。是否用 AUV 的注册替换它？对方的文件不会被改动。"), "AUV", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
                { SetClaudeHint(Loc.T("Nothing was changed.", "未做任何更改。")); return false; }
                InstallAndEnableClaude(true);
            }
            return true;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException or System.Security.SecurityException)
        { SetClaudeHint(Loc.T("Connecting did not complete: ", "连接未完成：") + error.Message); ClaudeChanged(); return false; }
    }

    /// <summary>
    /// "Load in Chrome/Edge": copy the extension folder's path, open the browser's extensions page and say what to do there.
    /// Loading an unpacked extension is the person's own step in the browser.
    /// </summary>
    internal void LoadClaudeExtensionIn(string product)
    {
        var name = ClaudeBrowserPresentation.BrowserName(product);
        var page = product == "edge" ? "edge://extensions" : "chrome://extensions";
        var copied = true;
        try { Clipboard.SetText(ClaudeSetup.ExtensionFolder); }
        catch (System.Runtime.InteropServices.COMException) { copied = false; }
        var opened = LaunchBrowser(product, page);
        SetClaudeHint((opened ? "" : Loc.T($"{name} was not found. Open {page} in it yourself. ", $"未找到 {name}。请自行在其中打开 {page}。")) + (copied
            ? Loc.T("On the extensions page: turn on Developer mode → Load unpacked → press Ctrl+V in the address bar of the folder window to paste the path, then choose Select Folder.",
                "在扩展页中：开启“开发者模式” → “加载已解压的扩展程序” → 在文件夹窗口的地址栏按 Ctrl+V 粘贴路径，然后选择“选择文件夹”。")
            : Loc.T($"The clipboard was busy. On the extensions page, turn on Developer mode, choose Load unpacked and select {ClaudeSetup.ExtensionFolder}.",
                $"剪贴板正忙。请在扩展页开启“开发者模式”，选择“加载已解压的扩展程序”，然后选择 {ClaudeSetup.ExtensionFolder}。")));
    }

    /// <summary>"Open claude.ai": the person signs in there themselves; AUV never handles sign-in or credentials.</summary>
    internal void OpenClaudeSite()
    {
        var product = RemedyBrowser ?? ClaudeTargetBrowser;
        var opened = product != null && LaunchBrowser(product, "https://claude.ai");
        SetClaudeHint(opened ? Loc.T("Sign in to claude.ai in that browser, then choose Sync now.", "请在该浏览器中登录 claude.ai，然后选择“立即同步”。")
            : Loc.T("Chrome or Edge was not found. Open https://claude.ai in the browser that has the AUV extension.", "未找到 Chrome 或 Edge。请在装有 AUV 扩展的浏览器中打开 https://claude.ai。"));
    }

    /// <summary>The button beside a failure reason on the Claude card.</summary>
    internal void RunClaudeRemedy()
    {
        var product = RemedyBrowser;
        switch (ClaudeRemedy)
        {
            case ClaudeRemedy.OpenClaude: OpenClaudeSite(); break;
            case ClaudeRemedy.OpenExtensions:
                var page = product == "edge" ? "edge://extensions" : "chrome://extensions";
                SetClaudeHint(LaunchBrowser(product ?? "chrome", page)
                    ? Loc.T($"Opened {page}. Find AUV Browser Companion for Claude there and reload it, or allow its site access.", $"已打开 {page}。请在其中找到 AUV Browser Companion for Claude 并重新加载它，或允许其网站访问权限。")
                    : Loc.T($"Open {page} in the browser yourself.", $"请自行在浏览器中打开 {page}。"));
                break;
            case ClaudeRemedy.OpenBrowser when product != null: _ = OpenBrowserAndSyncAsync(product); break;
        }
    }

    /// <summary>
    /// 0.18.6 start-up: a companion that is set up is brought up to this AUV's packaged build without asking (AUV's own files
    /// and registration only). Only a failure is shown, with Retry.
    /// </summary>
    private void UpdateClaudeAtStartup()
    {
        try
        {
            if (ClaudeSetup.UpdateIfNewer() is not { } manifest) return;
            app.Settings.ClaudeBrowser.InstalledBuild = manifest.CompanionBuild; main.Persist();
            claudeUpdateFailure = null;
            main.Model.Status = Loc.T($"Claude browser companion updated to build {manifest.CompanionBuild}.", $"Claude 浏览器伴侣已更新到构建 {manifest.CompanionBuild}。");
        }
        catch (ForeignRegistrationException)
        { claudeUpdateFailure = Loc.T("The browser companion could not be updated: another program now uses the same registration name. Choose Retry to decide what to do.", "浏览器伴侣未能更新：另有程序正在使用同一个注册名称。请选择“重试”来决定如何处理。"); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException or System.Security.SecurityException)
        { claudeUpdateFailure = Loc.T("The browser companion could not be updated: ", "浏览器伴侣未能更新：") + e.Message; }
    }
    internal void RetryClaudeUpdate(Window? owner) { if (InstallInteractively(owner)) main.Model.Status = Loc.T("Claude browser companion updated.", "Claude 浏览器伴侣已更新。"); }

    /// <summary>Remove forgets the checklist, so a later Connect starts from step 1.</summary>
    internal void ForgetClaudeChecklist()
    {
        app.Settings.ClaudeBrowser.LoadedBrowsers = []; app.Settings.ClaudeBrowser.ExactReadingSeen = false; main.Persist();
        claudeLastOutcome = null; claudeHint = ""; ClaudeChanged();
    }

    private void StartClaude()
    {
        if (!ClaudeBrowserEnabled) { Admit("claude", () => ProviderData.Unavailable("claude", ClaudeBrowserPresentation.Disabled, ConnectionState.Disconnected)); ClaudeChanged(); return; }
        if (!app.Demo) UpdateClaudeAtStartup();
        claudeSyncOnConnect = true; StartClaudeLink();
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
        var link = new ClaudeBrowserPipeServer(ClaudeBrowserPaths.PipeName(app.Store.PathName), installed, ClaudeBrowserPipeServer.InstalledHostOnly(root), () => app.Settings.ClaudeBrowser.Browser, claudeReloads);
        var coordinator = new ClaudeCompanionCoordinator(link, installed, reloads: claudeReloads);
        link.StateChanged += () => main.Dispatcher.BeginInvoke(ClaudeLinkChanged);
        coordinator.SyncRequested += request => main.Dispatcher.BeginInvoke(() => { _ = RefreshClaudeAsync(userInitiated: true); });
        coordinator.Qualified += product => main.Dispatcher.BeginInvoke(() => { if (disposed) return; MarkClaudeLoaded(product); ClaudeChanged(); });
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
        // A new link has no browser yet: read as soon as one connects instead of reporting "waiting" straight away.
        if (ClaudeBrowserEnabled) { claudeSyncOnConnect = true; StartClaudeLink(); }
    }

    private void ClaudeLinkChanged()
    {
        if (disposed || claudeLink == null) return;
        ClaudeChanged();
        // A host from another build was refused and (0.18.6) its extension asked to reload: read as soon as it comes back.
        if (claudeLink.State == CompanionLinkState.Rejected) claudeSyncOnConnect = true;
        if (claudeLink.State != CompanionLinkState.Connected) return;
        claudeAskedThisStretch = false;
        // A browser that just connected (opened after AUV, or after a prompt) is read at once when Claude has no current reading.
        if (claudeSyncOnConnect || !CurrentClaudeReading() && DateTimeOffset.UtcNow - claudeLastAttempt > TimeSpan.FromSeconds(30))
        { claudeSyncOnConnect = false; _ = RefreshClaudeAsync(userInitiated: false); }
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

    internal void ApplyClaude(ClaudeSyncResult result)
    {
        var now = DateTimeOffset.UtcNow;
        if (result is { Outcome: ClaudeSyncOutcome.Success, Observation: { } observation })
        {
            var previous = claudeSelection; var product = result.BrowserProduct;
            var presentation = ClaudeBrowserPresentation.Success(observation, product, now, previous);
            claudeSelection = presentation.Selection;
            // Rebuilt on a language change from the admitted observation only.
            Admit("claude", () => ClaudeBrowserPresentation.Success(observation, product, now, previous));
            claudeLastResult = () => Loc.T("Last sync: exact figures read ", "上次同步：已读取精确读数 ") + observation.ObservedAt.ToLocalTime().ToString("HH:mm:ss") +
                (result.Attempts > 1 ? Loc.T(" (on the retry)", "（重试时）") : "");
            main.Model.Status = Loc.T("Claude usage synchronized from the browser companion.", "已从浏览器伴侣同步 Claude 用量。");
            // Checklist steps 2 and 3: a browser answered with the expected identity and the person is signed in.
            MarkClaudeLoaded(product);
            if (!app.Settings.ClaudeBrowser.ExactReadingSeen) { app.Settings.ClaudeBrowser.ExactReadingSeen = true; main.Persist(); }
            claudeLastOutcome = null; claudeLastProduct = product;
            if (claudeHint.Length > 0) SetClaudeHint("");
        }
        else
        {
            var message = ClaudeBrowserPresentation.Message(result.Outcome, result.BrowserProduct);
            // A failed sync does not withdraw a reading that is still current; it goes out of date on the usual schedule.
            if (!CurrentClaudeReading()) Admit("claude", () => ClaudeBrowserPresentation.Failure(result.Outcome, result.BrowserProduct));
            var details = ClaudeDetails(result);
            // Rebuilt in the current language each time it is shown.
            claudeLastResult = () => Loc.T("Last sync: ", "上次同步：") + ClaudeBrowserPresentation.Message(result.Outcome, result.BrowserProduct) + details;
            main.Model.Status = "Claude: " + message;
            claudeLastOutcome = result.Outcome; claudeLastProduct = result.BrowserProduct;
            // The extension was asked to reload itself (0.18.6): read again as soon as it reconnects.
            if (result.ReloadRequested) claudeSyncOnConnect = true;
        }
        ClaudeChanged();
    }

    /// <summary>Content-free details for a failed sync: the page's failure code and its step trace (step names and milliseconds only).</summary>
    private string ClaudeDetails(ClaudeSyncResult result)
    {
        var parts = new List<string>();
        if (result.ProviderFailureReason is { } reason) parts.Add(Loc.T("code ", "代码 ") + reason);
        if (result.Attempts > 1) parts.Add(Loc.T("after a retry", "已重试"));
        if (claudeCoordinator?.LastTrace is { Length: > 0 } trace) parts.Add(Loc.T("last page steps: ", "最近一次页面步骤：") + trace);
        return parts.Count == 0 ? "" : "\n" + string.Join(" · ", parts);
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
        // 0.18.6: the prompt is an AUV card: themed surface, rounded outline, and it opens with a short fade and grow.
        var card = new System.Windows.Controls.Border { Child = body, Margin = new Thickness(12), CornerRadius = new CornerRadius(10), BorderThickness = new Thickness(1), Padding = new Thickness(8, 4, 8, 4) };
        card.SetResourceReference(System.Windows.Controls.Border.BackgroundProperty, "SurfaceBrush"); card.SetResourceReference(System.Windows.Controls.Border.BorderBrushProperty, "BorderBrush");
        card.SetResourceReference(EffectProperty, "CardEffect");
        Content = card;
        Background = (System.Windows.Media.Brush)app.Resources["CanvasBrush"]; Foreground = (System.Windows.Media.Brush)app.Resources["TextBrush"];
        SourceInitialized += (_, _) => { NativeAppearance.Apply(this, app.IsDark); AppBrandIcon.Apply(this, app.IsDark); };
        Loaded += async (_, _) => { Motion.Enter(card, 0, .98, 160); await Task.Delay(1000); accept.IsEnabled = true; };
    }
}
