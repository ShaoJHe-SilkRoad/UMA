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
        providers.ClaudeChanged();
        UpdateClaudeSetup();
        // The Connect card and the checklist act on their own; keep the Advanced file status in step with them.
        void Follow(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
        { if (e.PropertyName == nameof(ProviderController.ClaudeShowConnect)) Dispatcher.BeginInvoke(UpdateClaudeSetup); }
        providers.PropertyChanged += Follow;
        Closed += (_, _) => providers.PropertyChanged -= Follow;
    }

    private void UpdateClaudeSetup()
    {
        var providers = app.Providers;
        var setup = providers.ClaudeSetup;
        ClaudeFolder.Text = setup.ExtensionFolder;

        if (providers.ClaudeInstallStatus is not { } status) { ClaudeSetupStatus.Text = Loc.T("The companion's status could not be read.", "无法读取伴侣状态。"); return; }
        var browsers = string.Join(", ", status.RegisteredBrowsers.Select(Core.ClaudeBrowserPresentation.BrowserName));
        ClaudeSetupStatus.Text = status.State switch
        {
            CompanionInstallState.NotPackaged => Core.ClaudeBrowserPresentation.NotPackaged,
            CompanionInstallState.NotInstalled => Loc.T("Companion not set up. Choose Connect above.", "伴侣尚未设置。请选择上方的“连接”。"),
            CompanionInstallState.UpdateAvailable => Loc.T($"This AUV carries companion build {status.Packaged!.CompanionBuild}; build {status.Installed!.CompanionBuild} is set up. AUV updates a newer build by itself at start-up; choose Update to install this one now.",
                $"这份 AUV 带有伴侣构建 {status.Packaged!.CompanionBuild}；当前设置的是构建 {status.Installed!.CompanionBuild}。较新的构建会在 AUV 启动时自动更新；选择“更新”可立即安装这一构建。"),
            CompanionInstallState.RegistrationMissing => Loc.T("The companion's files are in place, but its browser registration is missing. Choose Repair above.", "伴侣文件已就位，但浏览器注册缺失。请选择上方的“修复”。"),
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
        if (app.Providers.ConnectClaude(this)) SaveStatus.Text = app.Providers.ClaudeHint;
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
            app.Settings.ClaudeBrowser.InstalledBuild = null; main.Persist(); app.Providers.ForgetClaudeChecklist();
            SaveStatus.Text = Loc.T("Registration removed. Remove the extension on the browser's extensions page.", "已删除注册。请在浏览器扩展页中移除扩展。")
                + (deleteFiles ? Loc.T(" The companion folder was deleted.", " 伴侣文件夹已删除。") : "");
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        { SaveStatus.Text = Loc.T("Removal did not complete: ", "移除未完成：") + error.Message; }
        UpdateClaudeSetup();
    }
}
