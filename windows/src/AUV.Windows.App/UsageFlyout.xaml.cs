using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
namespace AUV.Windows.App;
public partial class UsageFlyout : Window
{
    private readonly DesktopController desktop;
    private bool exiting;
    public UsageFlyout(DesktopController desktop)
    {
        this.desktop = desktop; InitializeComponent(); DataContext = desktop;
        ShowInTaskbar = ((App)Application.Current).DesktopAutomation;
        Deactivated += (_, _) => { if (!exiting) { Hide(); desktop.FlyoutHidden(); } };
        Closing += (_, e) => { if (!exiting) { e.Cancel = true; Hide(); desktop.FlyoutHidden(); } };
        PreviewKeyDown += (_, e) => { if (e.Key == Key.Escape) { Hide(); desktop.FlyoutHidden(); e.Handled = true; } };
    }
    private void Hide_Click(object sender, RoutedEventArgs e) { Hide(); desktop.FlyoutHidden(); }
    private void Widget_Click(object sender, RoutedEventArgs e) => desktop.ToggleWidgetCommand.Execute(null);
    internal void CloseForExit() { exiting = true; Close(); }
}
