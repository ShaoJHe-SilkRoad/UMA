using System.ComponentModel;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Threading;
using AUV.Windows.Core;

namespace AUV.Windows.App;

public sealed class DesktopController : Observable, IDisposable
{
    private readonly App app;
    private readonly MainWindow window;
    private readonly PerformanceMonitor monitor = new();
    private readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromSeconds(2) };
    private TrayIcon? tray;
    private UsageFlyout? flyout;
    private DesktopWidget? widget;
    private bool disposed, quitting, started;
    public MainViewModel Main => window.Model;
    public PerformanceViewModel Performance { get; } = new();
    public bool WidgetVisible => widget?.IsVisible == true;
    public bool WidgetRequested => app.Settings.Desktop.Enabled && app.Settings.Desktop.WidgetVisible;
    public bool Enabled { get => app.Settings.Desktop.Enabled; set { app.Settings.Desktop.Enabled = value; RefreshWizard(); Changed(); window.Persist(); } }
    public WizardDensity Density { get => app.Settings.Desktop.Density; set { app.Settings.Desktop.Density = value; RefreshWizard(); Changed(); window.Persist(); } }
    public WizardDensity[] Densities => Enum.GetValues<WizardDensity>();
    public static string DensityLabel(WizardDensity density) => density switch
    { WizardDensity.Regular => Loc.T("Regular", "常规"), WizardDensity.Minimalist => Loc.T("Minimalist", "极简"), _ => Loc.T("Automatic", "自动") };
    /// <summary>Re-evaluates computed labels after a language change.</summary>
    internal void RefreshText() { Changed(string.Empty); UpdateTooltip(); }
    public bool ShowStatus { get => app.Settings.Desktop.ShowStatus; set { app.Settings.Desktop.ShowStatus = value; RefreshWizard(); Changed(); window.Persist(); } }
    public bool ShowFill { get => app.Settings.Desktop.ShowFill; set { app.Settings.Desktop.ShowFill = value; RefreshWizard(); Changed(); window.Persist(); } }
    public RelayCommand SettingsCommand { get; }
    public bool AlwaysOnTop { get => app.Settings.Desktop.AlwaysOnTop; set { app.Settings.Desktop.AlwaysOnTop = value; if (widget != null) widget.Topmost = value; Changed(); window.Persist(); } }
    public bool CloseToTray { get => app.Settings.Desktop.CloseToTray; set { app.Settings.Desktop.CloseToTray = value; Changed(); window.Persist(); } }
    public bool HideTrayIcon
    {
        get => app.Settings.Desktop.HideTrayIcon;
        set
        {
            if (HideTrayIcon == value) return;
            app.Settings.Desktop.HideTrayIcon = value;
            if (value) { flyout?.Hide(); UpdateSampling(); }
            tray?.SetVisible(!value);
            Changed(); Changed(nameof(TrayAvailable)); Changed(nameof(TrayStatus));
            Main.Status = TrayStatus;
            if (!TrayAvailable && !window.IsVisible) OpenMain();
            window.Persist();
        }
    }
    public bool TrayAvailable => tray?.IsAdded == true;
    public string TrayStatus => HideTrayIcon ? Loc.T("Tray icon hidden", "托盘图标已隐藏") : TrayAvailable ? Loc.T("Tray icon shown", "托盘图标已显示") : Loc.T("System tray unavailable", "系统托盘不可用");
    public string WidgetButton => WidgetRequested ? Loc.T("Hide Desktop Wizard", "隐藏桌面浮窗") : Loc.T("Show Desktop Wizard", "显示桌面浮窗");
    public bool ShowTrayIcon { get => !HideTrayIcon; set => HideTrayIcon = !value; }
    // Agent order (0.17.6/0.18.0): stored by agent id, applied to the rail, tray panel, tray tooltip and Wizard.
    public bool Arranged => app.Settings.AgentOrder.Count > 0;
    public string[] OrderedIds => Main.Shell.Agents.Select(a => a.Id).ToArray();
    public void MoveAgent(string id, int index)
    {
        var visible = OrderedIds; var order = AgentOrdering.Move(visible, id, index);
        if (order.SequenceEqual(visible)) return;
        app.Settings.AgentOrder = order; Main.Shell.Reorder(order); OrderChanged(); window.Persist();
    }
    public void RestoreDefaultOrder()
    { if (!Arranged) return; app.Settings.AgentOrder = []; Main.Shell.Reorder([]); OrderChanged(); window.Persist(); }
    private void OrderChanged() { Changed(nameof(Arranged)); Changed(nameof(OrderedIds)); Changed(nameof(TrayAgentDescription)); RestoreOrderCommand.Refresh(); UpdateTooltip(); }
    public RelayCommand RestoreOrderCommand { get; }
    // Tray agent pin ("" = automatic).
    public string TrayAgent
    {
        get => app.Settings.TrayAgent;
        set { var id = AgentCatalog.IsKnown(value) ? value : ""; if (id == TrayAgent) return; app.Settings.TrayAgent = id; Changed(); Changed(nameof(TrayAgentDescription)); UpdateTooltip(); window.Persist(); }
    }
    public AgentPresentation? TrayReading => TrayAgentPolicy.Select(Main.Shell.Agents, app.Settings.TrayAgent, Arranged);
    public string TrayAgentDescription => TrayReading is { } agent ? Loc.T($"Now showing {agent.Name}.", $"当前显示 {agent.Name}。") : Loc.T("No agent has a reading right now.", "目前没有智能体有读数。");
    public string TrayTooltip
    {
        get
        {
            var agent = TrayReading; var prefix = "AUV" + (Main.Demo ? " [DEMO]" : "");
            if (agent == null) return prefix;
            return agent.Card.HasDisplayableQuota ? $"{prefix} · {agent.Name} · " + Loc.T($"{agent.Card.Value} remaining", $"剩余 {agent.Card.Value}") : $"{prefix} · {agent.Name} · —";
        }
    }
    public RelayCommand RefreshAllCommand { get; }
    public RelayCommand OpenCommand { get; }
    public RelayCommand ToggleWidgetCommand { get; }
    public RelayCommand HideWidgetCommand { get; }
    public RelayCommand DockWidgetCommand { get; }
    public RelayCommand QuitCommand { get; }
    public RelayCommand HideTrayCommand { get; }
    public RelayCommand TaskbarSettingsCommand { get; }
    public DesktopController(App app, MainWindow window)
    {
        this.app = app; this.window = window;
        OpenCommand = new(OpenMain); ToggleWidgetCommand = new(() => SetWidgetVisible(!WidgetRequested));
        HideWidgetCommand = new(() => SetWidgetVisible(false)); DockWidgetCommand = new(() => { if (widget != null) { NativeDesktop.Place(widget); RememberWidgetPosition(); } });
        QuitCommand = new(Quit);
        HideTrayCommand = new(() => HideTrayIcon = true);
        TaskbarSettingsCommand = new(() =>
        {
            try { Process.Start(new ProcessStartInfo("ms-settings:taskbar") { UseShellExecute = true }); }
            catch (Exception e) when (e is Win32Exception or InvalidOperationException) { Main.Status = Loc.T("Could not open Windows taskbar settings.", "无法打开 Windows 任务栏设置。"); }
        });
        SettingsCommand = new(() => { OpenMain(); new SettingsWindow(window, null, "desktop").ShowDialog(); });
        RestoreOrderCommand = new(RestoreDefaultOrder, () => Arranged);
        RefreshAllCommand = new(() => _ = app.Providers.RefreshAllAsync());
        timer.Tick += (_, _) => Performance.Update(monitor.Sample());
        window.Closing += MainClosing;
        window.Closed += (_, _) => { if (!quitting) Quit(); };
        Main.Shell.PropertyChanged += SelectionChanged;
    }
    internal void Start()
    {
        if (started) return;
        started = true;
        tray = new(window, app.Store.PathName, !HideTrayIcon);
        tray.Activated += context => { if (context) ShowMenu(); else ToggleFlyout(); };
        tray.AvailabilityChanged += () =>
        {
            Changed(nameof(TrayAvailable)); Changed(nameof(TrayStatus));
            if (!TrayAvailable && !window.IsVisible) OpenMain();
            UpdateTooltip();
        };
        UpdateTooltip(); Changed(nameof(TrayAvailable)); Changed(nameof(TrayStatus));
        if (!TrayAvailable) Main.Status = TrayStatus;
        if (app.Settings.Desktop.WidgetVisible) SetWidgetVisible(true);
    }
    private void SelectionChanged(object? sender, PropertyChangedEventArgs e)
    { if (e.PropertyName == nameof(ShellState.Agents)) { RefreshWizard(); Changed(nameof(OrderedIds)); Changed(nameof(TrayAgentDescription)); } }
    /// <summary>The tray tooltip follows the pinned agent, else the agent order (0.17.6 parity), not the selected page.</summary>
    internal void UpdateTooltip() { tray?.SetTooltip(TrayTooltip); Changed(nameof(TrayTooltip)); }
    public void ToggleFlyout()
    {
        if (flyout?.IsVisible == true) { flyout.Hide(); UpdateSampling(); return; }
        if (flyout == null)
        {
            flyout = new(this);
            flyout.SizeChanged += (_, _) => window.Dispatcher.BeginInvoke(() =>
            {
                if (!disposed && flyout?.IsVisible == true) NativeDesktop.Place(flyout, tray?.GetRectangle());
            }, DispatcherPriority.Loaded);
        }
        flyout.MaxHeight = SystemParameters.WorkArea.Height;
        flyout.Show(); NativeDesktop.Place(flyout, tray?.GetRectangle()); flyout.MaxHeight = NativeDesktop.WorkDips(flyout).Height;
        NativeDesktop.Place(flyout, tray?.GetRectangle()); flyout.Activate(); UpdateSampling();
    }
    internal void FlyoutHidden() => UpdateSampling();
    internal void UpdateAppearance() { tray?.UpdateAppearance(); RefreshWizard(); }
    public void SetWidgetVisible(bool value)
    {
        if (disposed) return;
        app.Settings.Desktop.WidgetVisible = value;
        RefreshWizard(); window.Persist();
    }
    public void RefreshWizard()
    {
        if (disposed) return;
        var cards = Main.QuotaAgents.Select(a => a.Card).ToArray();
        var value = WidgetRequested && cards.Length > 0;
        if (value)
        {
            if (widget == null)
            {
                widget = new(SelectProvider, RememberWidgetPosition, () => SetWidgetVisible(false), CreateWizardMenu, app.DesktopAutomation) { Topmost = AlwaysOnTop };
                var pref = app.Settings.Desktop;
                if (pref.Left is double left && pref.Top is double top) { widget.Left = left; widget.Top = top; }
                widget.Present(cards, pref, app.Settings.LargerText ? 1.25 : 1);
                widget.Show();
                if (pref.Left == null || pref.Top == null) NativeDesktop.Place(widget);
                else NativeDesktop.ClampToMonitor(widget);
            }
            else { widget.Present(cards, app.Settings.Desktop, app.Settings.LargerText ? 1.25 : 1); widget.Show(); NativeDesktop.ClampToMonitor(widget); }
        }
        else widget?.Hide();
        Changed(nameof(WidgetVisible)); Changed(nameof(WidgetRequested)); Changed(nameof(WidgetButton)); UpdateTooltip(); UpdateSampling();
    }
    private void SelectProvider(string id)
    { var agent = Main.Shell.Agents.FirstOrDefault(a => a.Id == id); if (agent == null) return; Main.Shell.SelectedAgent = agent; Main.Shell.Section = "AUV"; window.Persist(); OpenMain(); }
    internal void RememberWidgetPosition()
    {
        if (widget == null || disposed) return;
        NativeDesktop.ClampToMonitor(widget);
        app.Settings.Desktop.Left = widget.Left; app.Settings.Desktop.Top = widget.Top; window.Persist();
    }
    private void UpdateSampling()
    {
        var needed = flyout?.IsVisible == true;
        if (needed && !timer.IsEnabled) { monitor.Reset(); Performance.Update(monitor.Sample()); timer.Start(); }
        else if (!needed && timer.IsEnabled) { timer.Stop(); monitor.Reset(); Performance.Update(PerformanceSnapshot.Unknown); }
    }
    public void OpenMain()
    {
        flyout?.Hide(); window.Show();
        if (window.WindowState == WindowState.Minimized) window.WindowState = WindowState.Normal;
        window.Activate(); UpdateSampling();
    }
    public void HideMain()
    {
        if (!TrayAvailable) { Main.Status = HideTrayIcon ? Loc.T("Show the tray icon in Settings before hiding the main window.", "请先在设置中显示托盘图标，再隐藏主窗口。") : Loc.T("Cannot hide: the system tray is unavailable.", "无法隐藏：系统托盘不可用。"); return; }
        window.Persist(); window.Hide();
    }
    private void MainClosing(object? sender, CancelEventArgs e)
    { if (!quitting && CloseToTray && TrayAvailable) { e.Cancel = true; HideMain(); } }
    private void ShowMenu()
    {
        var menu = new ContextMenu { Placement = PlacementMode.MousePoint,
            Background = (System.Windows.Media.Brush)app.Resources["SurfaceBrush"], Foreground = (System.Windows.Media.Brush)app.Resources["TextBrush"] };
        menu.Items.Add(new MenuItem { Header = Loc.T("Open AUV", "打开 AUV"), Command = OpenCommand });
        menu.Items.Add(new MenuItem { Header = Loc.T("Refresh All", "全部刷新"), Command = RefreshAllCommand });
        var usage = new MenuItem { Header = Loc.T("Usage panel", "用量面板") }; usage.Click += (_, _) => ToggleFlyout(); menu.Items.Add(usage);
        menu.Items.Add(new MenuItem { Header = WidgetButton, Command = ToggleWidgetCommand });
        menu.Items.Add(new MenuItem { Header = Loc.T("Desktop Wizard settings", "桌面浮窗设置"), Command = SettingsCommand });
        menu.Items.Add(new MenuItem { Header = Loc.T("Hide tray icon", "隐藏托盘图标"), Command = HideTrayCommand });
        menu.Items.Add(new Separator()); menu.Items.Add(new MenuItem { Header = Loc.T("Exit AUV", "退出 AUV"), Command = QuitCommand });
        menu.IsOpen = true;
    }
    public ContextMenu CreateWizardMenu()
    {
        var menu = new ContextMenu { Background = (System.Windows.Media.Brush)app.Resources["SurfaceBrush"], Foreground = (System.Windows.Media.Brush)app.Resources["TextBrush"] };
        menu.Items.Add(new MenuItem { Header = Loc.T("Hide Desktop Wizard", "隐藏桌面浮窗"), Command = HideWidgetCommand });
        var enabled = new MenuItem { Header = Loc.T("Enabled", "启用"), IsCheckable = true, IsChecked = Enabled }; enabled.Click += (_, _) => Enabled = enabled.IsChecked; menu.Items.Add(enabled);
        var pinned = new MenuItem { Header = Loc.T("Always on Top", "始终置顶"), IsCheckable = true, IsChecked = AlwaysOnTop }; pinned.Click += (_, _) => AlwaysOnTop = pinned.IsChecked; menu.Items.Add(pinned);
        var density = new MenuItem { Header = Loc.T("Density", "密度") };
        foreach (var choice in Densities) { var item = new MenuItem { Header = DensityLabel(choice), IsCheckable = true, IsChecked = Density == choice }; item.Click += (_, _) => Density = choice; density.Items.Add(item); }
        menu.Items.Add(density); menu.Items.Add(new MenuItem { Header = Loc.T("Desktop Wizard settings", "桌面浮窗设置"), Command = SettingsCommand });
        menu.Items.Add(new Separator()); menu.Items.Add(new MenuItem { Header = Loc.T("Exit AUV", "退出 AUV"), Command = QuitCommand });
        return menu;
    }
    public void Quit()
    {
        if (quitting) return;
        quitting = true; window.Persist(); Dispose(); app.Shutdown();
    }
    public void Dispose()
    {
        if (disposed) return;
        disposed = true; timer.Stop(); tray?.Dispose();
        Main.Shell.PropertyChanged -= SelectionChanged; window.Closing -= MainClosing;
        flyout?.CloseForExit(); widget?.CloseForExit();
    }
    internal object Evidence => new { TrayAvailable, HideTrayIcon, WidgetVisible, AlwaysOnTop, SamplingActive = timer.IsEnabled,
        FlyoutVisible = flyout?.IsVisible == true, WidgetNativeTopmost = widget != null && NativeDesktop.IsTopmost(widget),
        WidgetNonActivating = widget != null && NativeDesktop.IsNonActivating(widget), WidgetTaskbarButton = widget?.ShowInTaskbar,
        RenderedDensity = widget?.RenderedDensity.ToString(), CardCount = widget?.CardCount,
        Cpu = Performance.Snapshot.CpuPercent, Memory = Performance.Snapshot.MemoryPercent, Performance.Snapshot.SampledAt,
        WidgetLeft = widget?.Left, WidgetTop = widget?.Top, WidgetWidth = widget?.ActualWidth, WidgetHeight = widget?.ActualHeight };
}
