using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;

namespace AUV.Windows.App;

/// <summary>Claude settings: set up, update and remove the browser companion, and its options.</summary>
public partial class SettingsWindow
{
    private static string BrowserLabel(string choice) => choice switch
    { "chrome" => "Chrome", "edge" => "Edge", _ => Loc.T("Automatic (first that connects)", "自动（先连接的那个）") };
    private static string PlacementLabel(string choice) => choice switch
    {
        "backgroundTab" => Loc.T("A background tab", "后台标签页"),
        "minimizedWindow" => Loc.T("A small minimized window", "最小化的小窗口"),
        _ => Loc.T("Automatic (background tab, or a minimized window)", "自动（后台标签页或最小化窗口）")
    };

    private void BuildClaudeChoices()
    {
        var providers = app.Providers;
        ClaudeBrowserChoice.Items.Clear(); ClaudePlacementChoice.Items.Clear();
        foreach (var choice in providers.ClaudeBrowsers) ClaudeBrowserChoice.Items.Add(new ComboBoxItem { Content = BrowserLabel(choice), Tag = choice });
        foreach (var choice in providers.ClaudePlacements) ClaudePlacementChoice.Items.Add(new ComboBoxItem { Content = PlacementLabel(choice), Tag = choice });
        ClaudeBrowserChoice.SelectedIndex = Array.IndexOf(providers.ClaudeBrowsers, providers.ClaudeBrowser);
        ClaudePlacementChoice.SelectedIndex = Array.IndexOf(providers.ClaudePlacements, providers.ClaudePlacement);
        UpdateClaudeSetup();
    }

    private void UpdateClaudeSetup()
    {
        var setup = app.Providers.ClaudeSetup;
        ClaudeFolder.Text = setup.ExtensionFolder;
        CompanionStatus status;
        try { status = setup.Status(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException) { ClaudeSetupStatus.Text = Loc.T("The companion's status could not be read.", "无法读取伴侣状态。"); return; }
        var browsers = string.Join(", ", status.RegisteredBrowsers.Select(b => b == "edge" ? "Edge" : "Chrome"));
        ClaudeSetupStatus.Text = status.State switch
        {
            CompanionInstallState.NotPackaged => Loc.T("This copy of AUV has no browser companion package.", "这份 AUV 不含浏览器伴侣安装包。"),
            CompanionInstallState.NotInstalled => Loc.T("Companion not set up.", "伴侣尚未设置。"),
            CompanionInstallState.UpdateAvailable => Loc.T($"An updated companion (build {status.Packaged!.CompanionBuild}) is available. Choose Update, then reload the extension on the browser's extensions page.",
                $"有更新的伴侣（构建 {status.Packaged!.CompanionBuild}）。请选择“更新”，然后在浏览器扩展页重新加载扩展。"),
            CompanionInstallState.RegistrationMissing => Loc.T("The companion's files are in place, but its browser registration is missing. Choose Set Up again.", "伴侣文件已就位，但浏览器注册缺失。请再次选择“设置”。"),
            _ => Loc.T($"Companion set up · build {status.Installed!.CompanionBuild} · registered for {browsers}", $"伴侣已设置 · 构建 {status.Installed!.CompanionBuild} · 已为 {browsers} 注册")
        } + (status.ForeignRegistrations.Count > 0 ? Loc.T(" Another program uses the same registration name.", " 另有程序使用了同一个注册名称。") : "");
        ClaudeSetupButton.Content = status.State switch
        {
            CompanionInstallState.UpdateAvailable => Loc.T("Update", "更新"),
            CompanionInstallState.RegistrationMissing => Loc.T("Repair", "修复"),
            CompanionInstallState.Installed => Loc.T("Set Up again", "重新设置"),
            _ => Loc.T("Set Up", "设置")
        };
        ClaudeSetupButton.IsEnabled = status.State != CompanionInstallState.NotPackaged && status.Packaged != null;
    }

    private void ClaudeSetup_Click(object sender, RoutedEventArgs e)
    {
        var setup = app.Providers.ClaudeSetup;
        var consent = MessageBox.Show(this, Loc.T(
            $"AUV will:\n\n• copy the companion extension and its helper to\n  {setup.InstallRoot}\n• register the helper for Chrome and Edge under your Windows account (HKEY_CURRENT_USER), no administrator rights needed.\n\nAn earlier copy is kept as a backup. Continue?",
            $"AUV 将会：\n\n• 把伴侣扩展及其辅助程序复制到\n  {setup.InstallRoot}\n• 在你的 Windows 账户下（HKEY_CURRENT_USER）为 Chrome 和 Edge 注册该辅助程序，不需要管理员权限。\n\n之前的副本会保留为备份。是否继续？"),
            "AUV", MessageBoxButton.OKCancel, MessageBoxImage.Question, MessageBoxResult.Cancel);
        if (consent != MessageBoxResult.OK) return;
        try
        {
            Core.ClaudeCompanionManifest manifest;
            try { manifest = setup.Install(false); }
            catch (ForeignRegistrationException foreign)
            {
                var names = string.Join(", ", foreign.Browsers.Select(b => b == "edge" ? "Edge" : "Chrome"));
                if (MessageBox.Show(this, Loc.T($"Another program registered the same companion name for {names}. Replace that registration with AUV's? The other program's files are not touched.",
                        $"另有程序在 {names} 中注册了同一个伴侣名称。是否用 AUV 的注册替换它？对方的文件不会被改动。"), "AUV", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes) return;
                manifest = setup.Install(true);
            }
            app.Settings.ClaudeBrowser.InstalledBuild = manifest.CompanionBuild; main.Persist();
            app.Providers.RestartClaudeLink();
            SaveStatus.Text = Loc.T("Companion set up. Now load the folder above on the browser's extensions page (Developer mode → Load unpacked).", "伴侣已设置。现在请在浏览器扩展页加载上面的文件夹（开发者模式 → 加载已解压的扩展程序）。");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException or System.Security.SecurityException)
        { SaveStatus.Text = Loc.T("Set up did not complete: ", "设置未完成：") + error.Message; }
        UpdateClaudeSetup();
    }

    private void ClaudeCopyFolder_Click(object sender, RoutedEventArgs e)
    {
        try { Clipboard.SetText(ClaudeFolder.Text); SaveStatus.Text = Loc.T("Folder path copied.", "已复制文件夹路径。"); }
        catch (System.Runtime.InteropServices.COMException) { SaveStatus.Text = Loc.T("The clipboard is busy. Try again.", "剪贴板正忙，请重试。"); }
    }

    private void ClaudeOpenFolder_Click(object sender, RoutedEventArgs e)
    {
        var folder = ClaudeFolder.Text;
        if (!Directory.Exists(folder)) { SaveStatus.Text = Loc.T("Choose Set Up first.", "请先选择“设置”。"); return; }
        try { Process.Start(new ProcessStartInfo("explorer.exe") { ArgumentList = { folder }, UseShellExecute = false })?.Dispose(); }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException) { SaveStatus.Text = Loc.T("Could not open the folder.", "无法打开该文件夹。"); }
    }

    private void ClaudeExtensionsPage_Click(object sender, RoutedEventArgs e)
    {
        var product = (sender as FrameworkElement)?.Tag as string ?? "chrome";
        var page = product == "edge" ? "edge://extensions" : "chrome://extensions";
        SaveStatus.Text = ProviderController.LaunchBrowser(product, page)
            ? Loc.T($"Opened {page}. Turn on Developer mode, choose Load unpacked and select the folder above.", $"已打开 {page}。请开启“开发者模式”，选择“加载已解压的扩展程序”，然后选择上面的文件夹。")
            : Loc.T($"{(product == "edge" ? "Edge" : "Chrome")} was not found. Open {page} in the browser yourself.", $"未找到 {(product == "edge" ? "Edge" : "Chrome")}。请自行在浏览器中打开 {page}。");
    }

    private void ClaudeBrowserChoice_Changed(object sender, SelectionChangedEventArgs e)
    { if (ready && ClaudeBrowserChoice.SelectedItem is ComboBoxItem { Tag: string choice }) app.Providers.ClaudeBrowser = choice; }
    private void ClaudePlacementChoice_Changed(object sender, SelectionChangedEventArgs e)
    { if (ready && ClaudePlacementChoice.SelectedItem is ComboBoxItem { Tag: string choice }) app.Providers.ClaudePlacement = choice; }

    private async void ClaudeSync_Click(object sender, RoutedEventArgs e)
    {
        if (!app.Providers.ClaudeBrowserEnabled) { SaveStatus.Text = Core.ClaudeBrowserPresentation.Disabled; return; }
        SaveStatus.Text = Core.ClaudeBrowserPresentation.Syncing;
        try { await app.Providers.RefreshClaudeAsync(userInitiated: true); SaveStatus.Text = app.Providers.ClaudeLastResult; }
        catch (Exception error) when (error is not OutOfMemoryException) { SaveStatus.Text = Loc.T("Claude sync did not complete.", "Claude 同步未完成。"); }
    }

    private void ClaudeRemove_Click(object sender, RoutedEventArgs e)
    {
        var setup = app.Providers.ClaudeSetup;
        if (MessageBox.Show(this, Loc.T("Remove AUV's browser companion registration for Chrome and Edge, and turn Claude browser sync off?", "要删除 AUV 在 Chrome 和 Edge 中的浏览器伴侣注册，并关闭 Claude 浏览器同步吗？"),
                "AUV", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No) != MessageBoxResult.Yes) return;
        var deleteFiles = Directory.Exists(setup.InstallRoot) && MessageBox.Show(this, Loc.T(
            $"Also delete AUV's companion folder, including its backups? This cannot be undone.\n\n{setup.InstallRoot}",
            $"同时删除 AUV 的伴侣文件夹（包括其中的备份）吗？此操作无法撤销。\n\n{setup.InstallRoot}"), "AUV", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) == MessageBoxResult.Yes;
        try
        {
            app.Providers.ClaudeBrowserEnabled = false;
            setup.Remove(deleteFiles);
            app.Settings.ClaudeBrowser.InstalledBuild = null; main.Persist();
            SaveStatus.Text = Loc.T("Registration removed. Remove the extension on the browser's extensions page.", "已删除注册。请在浏览器扩展页中移除扩展。")
                + (deleteFiles ? Loc.T(" The companion folder was deleted.", " 伴侣文件夹已删除。") : "");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        { SaveStatus.Text = Loc.T("Removal did not complete: ", "移除未完成：") + error.Message; }
        UpdateClaudeSetup();
    }
}
