using System.Windows;
using System.Windows.Controls;
using AUV.Windows.Core;
using Microsoft.Win32;
namespace AUV.Windows.App;
public partial class SettingsWindow : Window
{
    private readonly MainWindow main;
    private bool ready;
    private readonly string? providerId;
    public SettingsWindow(MainWindow main, string? agent)
    {
        this.main = main; InitializeComponent(); Owner = main;
        var app = (App)Application.Current;
        DesktopPanel.DataContext = app.Desktop;
        if (agent != null)
        {
            providerId = agent.ToLowerInvariant();
            Title = $"AUV — {agent} Settings"; Heading.Text = $"{agent} settings"; Subtitle.Text = "Connection"; ConnectionHeading.Text = "Status";
            GlobalPanel.Visibility = Visibility.Collapsed; ProviderPanel.Visibility = Visibility.Visible; ProviderPanel.DataContext = app.Providers; Height = 650;
            CodexPanel.Visibility = providerId == "codex" ? Visibility.Visible : Visibility.Collapsed;
            WorkBuddyPanel.Visibility = providerId == "workbuddy" ? Visibility.Visible : Visibility.Collapsed;
            OtherProviderNote.Visibility = providerId is "codex" or "workbuddy" ? Visibility.Collapsed : Visibility.Visible;
            if (PreparedConnections.Find(providerId) is { } plan)
                OtherProviderNote.Text = plan.UserStatus;
            UpdateConnection(); main.Model.Shell.PropertyChanged += ConnectionChanged;
            Closed += (_, _) => main.Model.Shell.PropertyChanged -= ConnectionChanged;
        }
        LightChoice.IsChecked = app.Settings.Theme == "Light"; DarkChoice.IsChecked = app.Settings.Theme == "Dark"; SystemChoice.IsChecked = app.Settings.Theme == "System";
        LargerChoice.IsChecked = app.Settings.LargerText;
        Icon = AppBrandIcon.Create(!app.IsDark);
        SourceInitialized += (_, _) => { NativeAppearance.Apply(this, app.IsDark); AppBrandIcon.Apply(this, app.IsDark); };
        Loaded += (_, _) => AppBrandIcon.Apply(this, app.IsDark);
        ready = true;
    }
    private void ThemeChoice_Checked(object sender, RoutedEventArgs e)
    {
        if (!ready) return;
        ((App)Application.Current).ApplyTheme(SystemChoice.IsChecked == true ? "System" : LightChoice.IsChecked == true ? "Light" : "Dark");
        SaveStatus.Text = main.Persist() ? "Appearance saved." : main.Model.Status;
    }
    private void Done_Click(object sender, RoutedEventArgs e) { main.Persist(); Close(); }
    private void Larger_Click(object sender, RoutedEventArgs e) { ((App)Application.Current).SetLargerText(LargerChoice.IsChecked == true); main.Persist(); }
    private void ConnectionChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e) { if (e.PropertyName == nameof(ShellState.Agents)) UpdateConnection(); }
    private void UpdateConnection()
    {
        var card = main.Model.Shell.Agents.FirstOrDefault(a => a.Id == providerId)?.Card;
        ConnectionBody.Text = PreparedConnections.Find(providerId ?? "") != null ? "" : card == null ? "Not connected" :
            card.IsStale ? "Data expired. Sync again to show usage." : card.HasDisplayableQuota ? $"{card.Value} remaining · {card.Window}\n{card.Freshness}" : card.Source;
    }
    private void ChooseCodex_Click(object sender, RoutedEventArgs e)
    {
        var picker = new OpenFileDialog { Title = "Choose installed codex.exe", Filter = "Codex executable|codex.exe", CheckFileExists = true };
        if (picker.ShowDialog(this) == true) ((App)Application.Current).Providers.CodexExecutable = picker.FileName;
    }
    private async void ReadCodex_Click(object sender, RoutedEventArgs e)
    {
        var providers = ((App)Application.Current).Providers; if (!providers.CodexEnabled) providers.CodexEnabled = true;
        SaveStatus.Text = "Reading Codex usage…"; await providers.RefreshCodexAsync(); SaveStatus.Text = main.Model.Status;
    }
    private void ConnectWorkBuddy_Click(object sender, RoutedEventArgs e) { ((App)Application.Current).Providers.OpenWorkBuddy(); Close(); }
    private async void DisconnectWorkBuddy_Click(object sender, RoutedEventArgs e)
    { try { await ((App)Application.Current).Providers.DisconnectWorkBuddyAsync(); SaveStatus.Text = "WorkBuddy disconnected from AUV. Its owned browser session was cleared."; } catch { SaveStatus.Text = "Could not clear the owned browser session. Retry Disconnect."; } }
}
