using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using AUV.Windows.Core;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace AUV.Windows.App;

/// <summary>Human-operated official account page, isolated from installed clients and other browsers.</summary>
public sealed class WorkBuddyConnectionWindow : Window
{
    private const string UsageUrl = "https://www.workbuddy.cn/profile/plans-usage";
    private readonly ProviderController provider;
    private readonly string settingsPath;
    private readonly WebView2 browser = new();
    private readonly TextBlock status = new() { Text = Loc.T("Sign in on the official website, then choose Sync Credits.", "请在官方网站登录，然后选择“同步 Credits”。"), TextWrapping = TextWrapping.Wrap };
    private readonly Button sync = new() { Content = Loc.T("Sync Credits", "同步 Credits"), IsEnabled = false, Margin = new Thickness(8, 0, 0, 0) };
    private readonly TextBlock address = new() { Text = "www.workbuddy.cn", FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 8) };
    private readonly List<WebView2> popups = [];
    private bool closed, reading;
    private long pageGeneration;
    public WorkBuddyConnectionWindow(ProviderController provider, string settingsPath)
    {
        this.provider = provider; this.settingsPath = settingsPath;
        Title = Loc.T("AUV — WorkBuddy connection", "AUV — WorkBuddy 连接"); Width = 1000; Height = 760; MinWidth = 760; MinHeight = 500; WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var root = new DockPanel(); var controls = new StackPanel { Margin = new Thickness(16, 12, 16, 8) }; DockPanel.SetDock(controls, Dock.Top);
        controls.Children.Add(new TextBlock { Text = Loc.T("WorkBuddy · official account connection", "WorkBuddy · 官方账户连接"), FontSize = 20, FontWeight = FontWeights.SemiBold });
        controls.Children.Add(new TextBlock { Text = Loc.T("AUV reads Credit pools only when you sync. This login session is separate from your other apps and browsers. Credentials stay in the browser's own session store.", "AUV 只在你同步时读取 Credit 额度池。这个登录会话与你的其他应用和浏览器分开，凭据只保存在该浏览器自己的会话中。"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 5, 0, 8), FontSize = 12 });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        var usage = new Button { Content = Loc.T("Plan and Usage", "套餐与用量") }; usage.Click += (_, _) => browser.CoreWebView2?.Navigate(UsageUrl); buttons.Children.Add(usage);
        sync.Click += async (_, _) => await SyncAsync(); buttons.Children.Add(sync);
        var disconnect = new Button { Content = Loc.T("Disconnect from AUV", "断开与 AUV 的连接"), Margin = new Thickness(8, 0, 0, 0) };
        disconnect.Click += async (_, _) => { try { await provider.DisconnectWorkBuddyAsync(); Close(); } catch { status.Text = Loc.T("The owned browser session could not be cleared. Close this window and retry Disconnect.", "无法清除 AUV 自己的浏览器会话。请关闭此窗口后重试断开连接。"); } }; buttons.Children.Add(disconnect);
        controls.Children.Add(buttons); controls.Children.Add(address); controls.Children.Add(status); root.Children.Add(controls); root.Children.Add(browser); Content = root;
        var app = (App)Application.Current; Icon = AppBrandIcon.Create(!app.IsDark);
        SourceInitialized += (_, _) => { NativeAppearance.Apply(this, app.IsDark); AppBrandIcon.Apply(this, app.IsDark); };
        Loaded += (_, _) => { AppBrandIcon.Apply(this, app.IsDark); Motion.Enter(root, 0, .98, 160); };
        Loaded += async (_, _) => await Initialize();
        Closed += (_, _) => { closed = true; pageGeneration++; foreach (var popup in popups.ToArray()) popup.Dispose(); browser.Dispose(); };
    }
    internal static Task<CoreWebView2Environment> EnvironmentFor(string settingsPath)
    {
        var profile = "workbuddy-web-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(settingsPath).ToUpperInvariant())))[..16];
        return CoreWebView2Environment.CreateAsync(null, Path.Combine(Path.GetDirectoryName(settingsPath)!, profile));
    }
    private async Task Initialize()
    {
        if (browser.CoreWebView2 != null || closed) return;
        try
        {
            await browser.EnsureCoreWebView2Async(await EnvironmentFor(settingsPath)); if (closed) return;
            var core = browser.CoreWebView2 ?? throw new InvalidDataException("Browser initialization failed."); Configure(core);
            core.NavigationStarting += (_, e) =>
            {
                pageGeneration++; sync.IsEnabled = false;
                if (Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri)) address.Text = uri.Host;
                provider.WorkBuddyUnavailable(Loc.T("WorkBuddy page is navigating. Sync the official Plan and Usage page after signing in.", "WorkBuddy 页面正在跳转。登录后请在官方套餐与用量页同步。"));
            };
            core.NavigationCompleted += async (_, e) =>
            {
                if (closed) return;
                sync.IsEnabled = e.IsSuccess && WorkBuddyCreditsDecoder.IsUsagePage(browser.Source);
                status.Text = sync.IsEnabled ? Loc.T("Official Plan and Usage page loaded. Sync Credits when its figures are visible.", "官方套餐与用量页已加载。数字显示后即可同步 Credits。") : Loc.T("Sign in on the official website, then open Plan and Usage.", "请在官方网站登录，然后打开套餐与用量。");
                if (sync.IsEnabled)
                {
                    var generation = pageGeneration; await Task.Delay(800);
                    if (!closed && generation == pageGeneration && ((App)Application.Current).Settings.Providers.WorkBuddyConsent) await SyncAsync();
                }
            };
            core.Navigate(UsageUrl);
        }
        catch { if (!closed) status.Text = Loc.T("The Windows WebView2 browser could not open. Check that Microsoft Edge WebView2 Runtime is installed, then reopen this connection window.", "无法打开 Windows WebView2 浏览器。请确认已安装 Microsoft Edge WebView2 Runtime，然后重新打开此连接窗口。"); }
    }
    private void Configure(CoreWebView2 core)
    {
        core.Settings.AreDevToolsEnabled = false; core.Settings.IsStatusBarEnabled = true;
        core.DownloadStarting += (_, e) => e.Cancel = true;
        core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
        core.NavigationStarting += (_, e) => { if (!Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) || uri.Scheme != "https" || !uri.IsDefaultPort || uri.UserInfo.Length > 0) e.Cancel = true; };
        core.NewWindowRequested += async (_, e) =>
        {
            var deferral = e.GetDeferral();
            try
            {
                if (closed || !Uri.TryCreate(e.Uri, UriKind.Absolute, out var uri) || uri.Scheme != "https") { e.Handled = true; return; }
                var popup = new WebView2(); popups.Add(popup);
                var window = new Window { Title = Loc.T("WorkBuddy — official sign-in", "WorkBuddy — 官方登录"), Owner = this, Width = 700, Height = 720, Content = popup, WindowStartupLocation = WindowStartupLocation.CenterOwner };
                await popup.EnsureCoreWebView2Async(await EnvironmentFor(settingsPath)); Configure(popup.CoreWebView2);
                popup.CoreWebView2.WindowCloseRequested += (_, _) => window.Close(); window.Closed += (_, _) => { popups.Remove(popup); popup.Dispose(); };
                e.NewWindow = popup.CoreWebView2; e.Handled = true; window.Show();
            }
            catch { e.Handled = true; if (!closed) status.Text = Loc.T("The sign-in popup could not open. Retry from the official page.", "无法打开登录弹窗。请在官方页面重试。"); }
            finally { deferral.Complete(); }
        };
        core.ProcessFailed += (_, _) => { provider.WorkBuddyUnavailable(Loc.T("WorkBuddy browser session stopped. Reopen and synchronize the official page.", "WorkBuddy 浏览器会话已停止。请重新打开并同步官方页面。")); if (!closed) { sync.IsEnabled = false; status.Text = Loc.T("Browser session stopped. Close and reopen this connection.", "浏览器会话已停止。请关闭并重新打开此连接。"); } };
    }
    internal async Task SyncAsync()
    {
        if (reading || closed || browser.CoreWebView2 == null) return;
        var generation = pageGeneration; reading = true; sync.IsEnabled = false;
        provider.WorkBuddyUnavailable(Loc.T("Verifying current WorkBuddy Credits from the official page.", "正在从官方页面验证当前的 WorkBuddy Credits。"));
        try
        {
            if (!WorkBuddyCreditsDecoder.IsUsagePage(browser.Source)) throw new InvalidDataException();
            using var stream = typeof(WorkBuddyConnectionWindow).Assembly.GetManifestResourceStream("AUV.Assets.WorkBuddyCredits.js") ?? throw new InvalidDataException();
            using var reader = new StreamReader(stream); var script = await reader.ReadToEndAsync();
            for (var attempt = 0; attempt < 8; attempt++)
            {
                var raw = await browser.ExecuteScriptAsync(script).WaitAsync(TimeSpan.FromSeconds(15));
                if (closed || generation != pageGeneration || !WorkBuddyCreditsDecoder.IsUsagePage(browser.Source)) return;
                if (raw.Length > 256 * 1024) throw new InvalidDataException();
                using var document = JsonDocument.Parse(raw);
                if (document.RootElement.TryGetProperty("failure", out var failure) && failure.GetString() == "pageNotStabilized" && attempt < 7)
                { await Task.Delay(450); continue; }
                var payload = document.RootElement.Clone(); var observed = DateTimeOffset.UtcNow;
                var result = WorkBuddyCreditsDecoder.Decode(payload, observed);
                // Keep only the admitted payload in memory so labels can follow a language change.
                provider.AdmitWorkBuddy(() => WorkBuddyCreditsDecoder.Decode(payload, observed)); status.Text = Loc.T("Verified ", "已验证 ") + result.Card.Value + " · " + result.Card.Freshness; break;
            }
        }
        catch (Exception e) { if (!closed && generation == pageGeneration) { provider.WorkBuddyUnavailable(Loc.T("WorkBuddy Credits could not be verified. Sign in, show all current pools and retry Sync Credits.", "无法验证 WorkBuddy Credits。请登录、显示所有当前额度池，然后重试同步。")); status.Text = Loc.T("Credits unavailable: sign in and show all current pools, then retry. ", "Credits 不可用：请登录并显示所有当前额度池，然后重试。") + (e is InvalidDataException ? e.Message : Loc.T("The page read did not complete.", "页面读取未完成。")); } }
        finally { reading = false; if (!closed) sync.IsEnabled = WorkBuddyCreditsDecoder.IsUsagePage(browser.Source); }
    }
    internal async Task ClearSessionAsync()
    { pageGeneration++; if (browser.CoreWebView2 != null) await browser.CoreWebView2.Profile.ClearBrowsingDataAsync(); }
}
