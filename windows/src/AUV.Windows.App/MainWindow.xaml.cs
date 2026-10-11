using System.Globalization;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Interop;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shell;
using AUV.Windows.Core;
namespace AUV.Windows.App;
public sealed class SectionConverter : IValueConverter
{
    public object Convert(object value, Type type, object parameter, CultureInfo culture) => type == typeof(bool?) || type == typeof(bool)
        ? Equals(value, parameter) : Equals(value, parameter) ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object value, Type type, object parameter, CultureInfo culture) => value is true ? parameter : Binding.DoNothing;
}
public sealed class InverseVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type type, object parameter, CultureInfo culture) => value is true ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object value, Type type, object parameter, CultureInfo culture) => Binding.DoNothing;
}
internal static class NativeAppearance
{
    [DllImport("dwmapi.dll")] private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    public static void Apply(Window window, bool dark)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero) return;
        int enabled = dark ? 1 : 0;
        _ = DwmSetWindowAttribute(handle, 20, ref enabled, sizeof(int));
        int backdrop = window is MainWindow && WindowsAppearance.Transparency ? 2 : 1;
        _ = DwmSetWindowAttribute(handle, 38, ref backdrop, sizeof(int));
    }
}
public partial class MainWindow : Window
{
    public MainViewModel Model { get; }
    private App Host => (App)Application.Current;
    private bool maximizeHovered, maximizePressed;
    public MainWindow(MainViewModel model)
    {
        Model = model; InitializeComponent(); DataContext = model;
        Icon = AppBrandIcon.Create(!Host.IsDark);
        InputBindings.Add(new KeyBinding(new RelayCommand(() => Host.Desktop.ToggleWidgetCommand.Execute(null)), new KeyGesture(Key.W, ModifierKeys.Control | ModifierKeys.Shift)));
        InputBindings.Add(new KeyBinding(new RelayCommand(() => Host.Desktop.ToggleFlyout()), new KeyGesture(Key.U, ModifierKeys.Control | ModifierKeys.Shift)));
        InputBindings.Add(new KeyBinding(new RelayCommand(() => new SettingsWindow(this, null).ShowDialog()), new KeyGesture(Key.OemComma, ModifierKeys.Control)));
        InputBindings.Add(new KeyBinding(new RelayCommand(() => Host.Desktop.Quit()), new KeyGesture(Key.Q, ModifierKeys.Control | ModifierKeys.Shift)));
        InputBindings.Add(new KeyBinding(new RelayCommand(async () => await Host.Providers.RefreshSelectedAsync()), new KeyGesture(Key.F5)));
        FontSize = Host.Settings.LargerText ? 17.5 : 14;
        if (model.Demo) Title += " [DEMO — sample data]";
        var bounds = Host.Settings.Geometry; bounds.Normalize();
        var work = SystemParameters.WorkArea;
        Width = Math.Min(bounds.Width, work.Width); Height = Math.Min(bounds.Height, work.Height);
        if (bounds.Left is double left && bounds.Top is double top)
        { WindowStartupLocation = WindowStartupLocation.Manual; Left = Math.Clamp(left, work.Left, Math.Max(work.Left, work.Right - Width)); Top = Math.Clamp(top, work.Top, Math.Max(work.Top, work.Bottom - Height)); }
        SourceInitialized += (_, _) => { NativeAppearance.Apply(this, Host.IsDark); AppBrandIcon.Apply(this, Host.IsDark); HwndSource.FromHwnd(new WindowInteropHelper(this).Handle)?.AddHook(DisplayMessage); };
        StateChanged += (_, _) => Dispatcher.BeginInvoke(UpdateFrameInsets, System.Windows.Threading.DispatcherPriority.Loaded);
        var hasSavedGeometry = System.IO.File.Exists(Host.Store.PathName);
        Loaded += (_, _) =>
        {
            if (!hasSavedGeometry)
            {
                Width = Math.Min(1040 + ActualWidth - RootLayout.ActualWidth, work.Width);
                Height = Math.Min(760 + ActualHeight - RootLayout.ActualHeight, work.Height);
            }
            if (bounds.Maximized) WindowState = WindowState.Maximized;
            // WPF initializes its native icons while showing the first window.
            AppBrandIcon.Apply(this, Host.IsDark);
        };
        Closing += (_, _) => Persist();
        Model.CopyText = text =>
        {
            try { Clipboard.SetText(text); Model.InstructionStatus = "Instruction copied. Paste it to your receiving Leader; no setting has been applied."; }
            catch (ExternalException) { Model.InstructionStatus = "Clipboard is busy. Select the preview and copy manually, or try again."; }
        };
    }
    public bool Persist()
    {
        var settings = Host.Settings;
        settings.ActiveSection = Model.Shell.Section; settings.SelectedAgent = Model.Shell.SelectedAgent.Id;
        settings.Roles = Model.Roles.ToDictionary(r => r.Key, r => r.Selection);
        var rect = WindowState == WindowState.Normal ? new Rect(Left, Top, ActualWidth, ActualHeight) : RestoreBounds;
        settings.Geometry = new() { Width = rect.Width, Height = rect.Height, Left = rect.Left, Top = rect.Top, Maximized = WindowState == WindowState.Maximized };
        var success = Host.Store.Save(settings);
        if (!success) Model.Status = Host.Store.LastError!;
        return success;
    }
    private void GlobalSettings_Click(object sender, RoutedEventArgs e) => new SettingsWindow(this, null).ShowDialog();
    private void Minimize_Click(object sender, RoutedEventArgs e) => SystemCommands.MinimizeWindow(this);
    private void MaximizeRestore_Click(object sender, RoutedEventArgs e)
    {
        if (WindowState == WindowState.Maximized) SystemCommands.RestoreWindow(this);
        else SystemCommands.MaximizeWindow(this);
    }
    private void Close_Click(object sender, RoutedEventArgs e) => SystemCommands.CloseWindow(this);
    private void AgentSettings_Click(object sender, RoutedEventArgs e) => new SettingsWindow(this, Model.Shell.SelectedAgent.Name).ShowDialog();
    private void UsagePopup_Click(object sender, RoutedEventArgs e) => Host.Desktop.ToggleFlyout();
    private async void RefreshUsage_Click(object sender, RoutedEventArgs e) => await Host.Providers.RefreshSelectedAsync();
    private void Widget_Click(object sender, RoutedEventArgs e) => Host.Desktop.ToggleWidgetCommand.Execute(null);
    private void HideToTray_Click(object sender, RoutedEventArgs e) => Host.Desktop.HideMain();
    private void Exit_Click(object sender, RoutedEventArgs e) => Host.Desktop.Quit();
    private void MoreActions_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button { ContextMenu: { } menu } button) return;
        menu.PlacementTarget = button; menu.Placement = System.Windows.Controls.Primitives.PlacementMode.Top; menu.IsOpen = true;
    }
    private void StorageSettings_Click(object sender, RoutedEventArgs e) { StorageTechnical.IsExpanded = true; StorageTechnical.BringIntoView(); StorageTechnical.Focus(); }
    private void StorageSelection_Changed(object sender, RoutedPropertyChangedEventArgs<object> e)
    { if (e.NewValue is System.Windows.Controls.TreeViewItem item) Model.Storage.VolumeSelected = Equals(item.Tag, "Volume"); }
    private nint DisplayMessage(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message is 0x0084 or 0x00a1 or 0x00a2 && IsEnabled && MaximizeButton.IsVisible)
        {
            var packed = lParam.ToInt64();
            var point = MaximizeButton.PointFromScreen(new Point((short)(packed & 0xffff), (short)((packed >> 16) & 0xffff)));
            var over = new Rect(0, 0, MaximizeButton.ActualWidth, MaximizeButton.ActualHeight).Contains(point);
            if (message == 0x0084) // WM_NCHITTEST
            {
                SetMaximizeHover(over);
                // HTMAXBUTTON enables the Windows 11 Snap Layouts menu. Mouse clicks
                // arrive as non-client messages instead of WPF Button events.
                if (over) { handled = true; return 9; }
            }
            else if (message == 0x00a1 && over) // WM_NCLBUTTONDOWN
            {
                maximizePressed = true; MaximizeButton.Opacity = .6;
                handled = true; return 0;
            }
            else if (message == 0x00a2 && maximizePressed) // WM_NCLBUTTONUP
            {
                ResetMaximizePress();
                if (over) Dispatcher.BeginInvoke(() => MaximizeRestore_Click(MaximizeButton, new RoutedEventArgs()));
                handled = true; return 0;
            }
        }
        if (message == 0x02a2) SetMaximizeHover(false); // WM_NCMOUSELEAVE
        if (message == 0x0202 || message == 0x0006 && wParam == 0) ResetMaximizePress(); // Client release / deactivation
        if (message is 0x007e or 0x02e0) Dispatcher.BeginInvoke(() =>
        {
            AppBrandIcon.Apply(this, Host.IsDark);
            UpdateFrameInsets();
            if (WindowState != WindowState.Normal) return;
            var area = NativeDesktop.WorkDips(this); Width = Math.Min(Width, area.Width); Height = Math.Min(Height, area.Height);
            NativeDesktop.ClampToMonitor(this);
        });
        return 0;
    }
    private void SetMaximizeHover(bool value)
    {
        if (maximizeHovered == value) return;
        maximizeHovered = value;
        if (value) MaximizeButton.SetResourceReference(Control.BackgroundProperty, "RaisedBrush");
        else MaximizeButton.ClearValue(Control.BackgroundProperty);
    }
    private void ResetMaximizePress()
    { maximizePressed = false; MaximizeButton.ClearValue(OpacityProperty); }
    private void UpdateFrameInsets()
    {
        var inset = new Thickness();
        if (WindowState == WindowState.Maximized)
        {
            // Windows places the invisible resize frame outside the monitor work area.
            // Keep the extended client content inside the visible area at this monitor's DPI.
            var bounds = NativeDesktop.Rectangle(this); var area = NativeDesktop.WorkDips(this);
            var dpi = VisualTreeHelper.GetDpi(this);
            inset = new(Math.Max(0, area.Left - bounds.Left / dpi.DpiScaleX),
                Math.Max(0, area.Top - bounds.Top / dpi.DpiScaleY),
                Math.Max(0, bounds.Right / dpi.DpiScaleX - area.Left - area.Width),
                Math.Max(0, bounds.Bottom / dpi.DpiScaleY - area.Top - area.Height));
        }
        RootLayout.Margin = inset;
        WindowChrome.GetWindowChrome(this).CaptionHeight = 46 + inset.Top;
    }
}
