using System.Windows;
using System.Windows.Controls;

namespace AUV.Windows.App;

/// <summary>0.18.6: Connect Claude, the three-step checklist and failure actions. The state lives in <see cref="ProviderController"/>.</summary>
public partial class ClaudeConnectPanel : UserControl
{
    public ClaudeConnectPanel() { InitializeComponent(); }
    private static ProviderController Providers => ((App)Application.Current).Providers;
    private void Connect_Click(object sender, RoutedEventArgs e) => Providers.ConnectClaude(Window.GetWindow(this));
    private void Load_Click(object sender, RoutedEventArgs e) { if ((sender as FrameworkElement)?.Tag is string product) Providers.LoadClaudeExtensionIn(product); }
    private void OpenClaude_Click(object sender, RoutedEventArgs e) => Providers.OpenClaudeSite();
    private void Remedy_Click(object sender, RoutedEventArgs e) => Providers.RunClaudeRemedy();
    private void RetryUpdate_Click(object sender, RoutedEventArgs e) => Providers.RetryClaudeUpdate(Window.GetWindow(this));
}
