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
        // 0.18.7: tell the controller when the panel closed itself, so the click that took its focus does not reopen it.
        Deactivated += (_, _) => { if (exiting) return; var open = IsVisible; Hide(); if (open) desktop.FlyoutDismissed(); desktop.FlyoutHidden(); };
        Closing += (_, e) => { if (!exiting) { e.Cancel = true; Hide(); desktop.FlyoutHidden(); } };
        // 0.18.6: Windows 11 rounds the panel's corners like other flyouts (ignored on Windows 10).
        SourceInitialized += (_, _) => { var handle = new System.Windows.Interop.WindowInteropHelper(this).Handle; var round = 2; _ = DwmSetWindowAttribute(handle, 33, ref round, sizeof(int)); };
        PreviewKeyDown +=(_, e) => { if (e.Key == Key.Escape) { Hide(); desktop.FlyoutHidden(); e.Handled = true; } };
    }
    private void Hide_Click(object sender, RoutedEventArgs e) { Hide(); desktop.FlyoutHidden(); }
    private void Widget_Click(object sender, RoutedEventArgs e) => desktop.ToggleWidgetCommand.Execute(null);
    internal void CloseForExit() { exiting = true; Close(); }
    [System.Runtime.InteropServices.DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
