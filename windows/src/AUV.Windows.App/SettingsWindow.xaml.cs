using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using AUV.Windows.Core;
using Microsoft.Win32;
namespace AUV.Windows.App;
/// <summary>Global settings in six panes, or one agent's own settings (opened from its page).</summary>
public partial class SettingsWindow : Window
{
    private readonly MainWindow main;
    private readonly App app = (App)Application.Current;
    private bool ready;
    private readonly string? providerId;
    public static readonly string[] Panes = ["general", "refresh", "agents", "tray", "desktop", "privacy"];
    public string? SelectedPane => (PaneList.SelectedItem as ListBoxItem)?.Tag as string;
    public SettingsWindow(MainWindow main, string? agent, string? pane = null)
    {
        this.main = main; InitializeComponent(); Owner = main; DataContext = app;
        if (agent != null)
        {
            providerId = agent.ToLowerInvariant();
            var name = AgentCatalog.Name(providerId);
            Title = Loc.T($"AUV — {name} Settings", $"AUV — {name} 设置");
            Heading.Text = Loc.T($"{name} Settings", $"{name} 设置");
            PaneList.Visibility = Visibility.Collapsed; NavColumn.Width = new GridLength(0);
            foreach (var panel in AllPanes()) panel.Visibility = Visibility.Collapsed;
            ProviderPanel.Visibility = Visibility.Visible; Width = 540; Height = 700;
            CodexPanel.Visibility = providerId == "codex" ? Visibility.Visible : Visibility.Collapsed;
            WorkBuddyPanel.Visibility = providerId == "workbuddy" ? Visibility.Visible : Visibility.Collapsed;
            ClaudePanel.Visibility = providerId == "claude" ? Visibility.Visible : Visibility.Collapsed;
            if (providerId == "claude") BuildClaudeChoices();
            OtherProviderNote.Visibility = providerId is "codex" or "workbuddy" or "claude" ? Visibility.Collapsed : Visibility.Visible;
            OtherProviderNote.Text = PreparedConnections.Find(providerId) is { } plan ? plan.UserStatus : "";
            UpdateConnection(); main.Model.Shell.PropertyChanged += ConnectionChanged;
            Closed += (_, _) => main.Model.Shell.PropertyChanged -= ConnectionChanged;
        }
        else
        {
            Title = Loc.T("AUV — Settings", "AUV — 设置");
            if (app.Settings.SettingsWidth is double w) Width = w;
            if (app.Settings.SettingsHeight is double h) Height = h;
            PaneList.SelectedIndex = Math.Max(0, Array.IndexOf(Panes, pane ?? "general"));
            BuildTrayChoices(); app.Desktop.PropertyChanged += DesktopChanged;
            Closed += (_, _) => app.Desktop.PropertyChanged -= DesktopChanged;
            // 0.18.0: the Settings window keeps the size you leave it at.
            Closing += (_, _) => { if (WindowState == WindowState.Normal) { app.Settings.SettingsWidth = ActualWidth; app.Settings.SettingsHeight = ActualHeight; } main.Persist(); };
        }
        LightChoice.IsChecked = app.Settings.Theme == "Light"; DarkChoice.IsChecked = app.Settings.Theme == "Dark"; SystemChoice.IsChecked = app.Settings.Theme == "System";
        LanguageSystem.IsChecked = app.Settings.Language == "System"; LanguageEnglish.IsChecked = app.Settings.Language == "en"; LanguageChinese.IsChecked = app.Settings.Language == "zh";
        LargerChoice.IsChecked = app.Settings.LargerText;
        PreferencePath.Text = app.Store.PathName;
        Icon = AppBrandIcon.Create(!app.IsDark);
        SourceInitialized += (_, _) => { NativeAppearance.Apply(this, app.IsDark); AppBrandIcon.Apply(this, app.IsDark); };
        Loaded += (_, _) => AppBrandIcon.Apply(this, app.IsDark);
        ready = true;
    }
    private IEnumerable<FrameworkElement> AllPanes() => [GeneralPane, RefreshPane, AgentsPane, TrayPane, DesktopPane, PrivacyPane];
    private void PaneList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    { var tag = SelectedPane; foreach (var panel in AllPanes()) panel.Visibility = Equals(panel.Tag, tag) ? Visibility.Visible : Visibility.Collapsed; }
    /// <summary>Opens a pane by its tag (general, refresh, agents, tray, desktop, privacy).</summary>
    public void ShowPane(string tag) => PaneList.SelectedIndex = Math.Max(0, Array.IndexOf(Panes, tag));
    private void DesktopChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    { if (e.PropertyName is nameof(DesktopController.TrayAgent) or nameof(DesktopController.OrderedIds) or "") BuildTrayChoices(); }
    private void BuildTrayChoices()
    {
        TrayAgentChoices.Children.Clear();
        void Add(string id, string text)
        {
            var choice = new RadioButton { Content = text, GroupName = "TrayAgent", IsChecked = app.Settings.TrayAgent == id, Margin = new Thickness(0, 3, 0, 3), Tag = id };
            System.Windows.Automation.AutomationProperties.SetAutomationId(choice, "auv.settings.tray-agent." + (id == "" ? "automatic" : id));
            choice.Checked += (_, _) => { if (ready) app.Desktop.TrayAgent = id; };
            TrayAgentChoices.Children.Add(choice);
        }
        Add("", Loc.T("Automatic: first agent in the order with a reading", "自动：顺序中第一个有读数的智能体"));
        foreach (var agent in main.Model.Shell.Agents) Add(agent.Id, agent.Name);
    }
    private void ThemeChoice_Checked(object sender, RoutedEventArgs e)
    {
        if (!ready) return;
        app.ApplyTheme(SystemChoice.IsChecked == true ? "System" : LightChoice.IsChecked == true ? "Light" : "Dark");
        SaveStatus.Text = main.Persist() ? Loc.T("Appearance saved.", "外观已保存。") : main.Model.Status;
    }
    private void Language_Checked(object sender, RoutedEventArgs e)
    {
        if (!ready) return;
        app.ApplyLanguage(LanguageChinese.IsChecked == true ? "zh" : LanguageEnglish.IsChecked == true ? "en" : "System");
        Title = providerId == null ? Loc.T("AUV — Settings", "AUV — 设置") : Title; BuildTrayChoices();
        SaveStatus.Text = main.Persist() ? Loc.T("Language saved.", "语言已保存。") : main.Model.Status;
    }
    private void Done_Click(object sender, RoutedEventArgs e) { main.Persist(); Close(); }
    private void Larger_Click(object sender, RoutedEventArgs e) { app.SetLargerText(LargerChoice.IsChecked == true); main.Persist(); }
    private async void RefreshAll_Click(object sender, RoutedEventArgs e)
    {
        SaveStatus.Text = Loc.T("Refreshing every agent…", "正在刷新所有智能体…");
        try { await app.Providers.RefreshAllAsync(); SaveStatus.Text = main.Model.Status; }
        catch (Exception error) when (error is not OutOfMemoryException) { SaveStatus.Text = Loc.T("Refresh did not complete. Try again.", "刷新未完成，请重试。"); }
    }
    private void MoveUp_Click(object sender, RoutedEventArgs e) => Move(sender, -1);
    private void MoveDown_Click(object sender, RoutedEventArgs e) => Move(sender, 1);
    private void Move(object sender, int delta)
    {
        if ((sender as FrameworkElement)?.Tag is not string id) return;
        var index = Array.IndexOf(app.Desktop.OrderedIds, id); app.Desktop.MoveAgent(id, index + delta);
    }
    private void OpenPreferences_Click(object sender, RoutedEventArgs e)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe") { ArgumentList = { Path.GetDirectoryName(app.Store.PathName)! }, UseShellExecute = false }); }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException) { SaveStatus.Text = Loc.T("Could not open the folder.", "无法打开该文件夹。"); }
    }
    private void ConnectionChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e) { if (e.PropertyName == nameof(ShellState.Agents)) UpdateConnection(); }
    private void UpdateConnection()
    {
        var card = main.Model.Shell.Agents.FirstOrDefault(a => a.Id == providerId)?.Card;
        ConnectionBody.Text = PreparedConnections.Find(providerId ?? "") != null ? "" : card == null ? Loc.T("Not connected", "未连接") :
            card.IsStale ? Loc.T("Reading is out of date and hidden. Refresh to show usage.", "读数已过期并已隐藏。刷新后显示用量。") :
            card.HasDisplayableQuota ? Loc.T($"{card.Value} remaining · {card.Window}", $"剩余 {card.Value} · {card.Window}") + $"\n{card.Freshness}" : card.Source;
    }
    private void ChooseCodex_Click(object sender, RoutedEventArgs e)
    {
        var picker = new OpenFileDialog { Title = Loc.T("Choose installed codex.exe", "选择已安装的 codex.exe"), Filter = "Codex executable|codex.exe", CheckFileExists = true };
        if (picker.ShowDialog(this) == true) app.Providers.CodexExecutable = picker.FileName;
    }
    private async void ReadCodex_Click(object sender, RoutedEventArgs e)
    {
        var providers = app.Providers; if (!providers.CodexEnabled) providers.CodexEnabled = true;
        SaveStatus.Text = Loc.T("Reading Codex usage…", "正在读取 Codex 用量…");
        try { await providers.RefreshCodexAsync(); SaveStatus.Text = main.Model.Status; }
        catch (Exception error) when (error is not OutOfMemoryException) { SaveStatus.Text = Loc.T("Codex usage could not be read.", "无法读取 Codex 用量。"); }
    }
    /// <summary>0.18.4: ThreadOS opens from Codex settings; the main window shows Back to Codex.</summary>
    private void OpenThreadOS_Click(object sender, RoutedEventArgs e) { Close(); main.OpenThreadOS(); }
    private void ConnectWorkBuddy_Click(object sender, RoutedEventArgs e) { app.Providers.OpenWorkBuddy(); Close(); }
    private async void DisconnectWorkBuddy_Click(object sender, RoutedEventArgs e)
    {
        try { await app.Providers.DisconnectWorkBuddyAsync(); SaveStatus.Text = Loc.T("WorkBuddy disconnected from AUV. Its own browser session was cleared.", "已断开 WorkBuddy 与 AUV 的连接，并清除了它自己的浏览器会话。"); }
        catch { SaveStatus.Text = Loc.T("Could not clear the browser session. Retry Disconnect.", "无法清除浏览器会话，请重试断开连接。"); }
    }
}
