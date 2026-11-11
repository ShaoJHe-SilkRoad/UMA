using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Controls;
using System.Windows.Input;
using AUV.Windows.Core;
using Microsoft.Win32;
namespace AUV.Windows.App;
public partial class App : Application, System.ComponentModel.INotifyPropertyChanged
{
    public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;
    public SettingsStore Store { get; private set; } = null!;
    public PreviewSettings Settings { get; private set; } = null!;
    public bool Demo { get; private set; }
    public bool DesktopAutomation { get; private set; }
    public DesktopController Desktop { get; private set; } = null!;
    public ProviderController Providers { get; private set; } = null!;
    private PreviewInstance? instance;
    private void ComboBox_PreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is ComboBox combo && combo.IsEnabled && !combo.IsKeyboardFocusWithin) combo.Focus();
    }
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        Demo = e.Args.Contains("--demo");
        DesktopAutomation = e.Args.Contains("--desktop-automation");
        var index = Array.IndexOf(e.Args, "--settings-path");
        var path = index >= 0 && index + 1 < e.Args.Length ? Path.GetFullPath(e.Args[index + 1]) :
            Demo ? Path.Combine(Path.GetDirectoryName(SettingsStore.DefaultPath)!, "demo.settings.v1.json") : SettingsStore.DefaultPath;
        instance = new(path, () => { if (!Dispatcher.HasShutdownStarted) Dispatcher.BeginInvoke(() => Desktop?.OpenMain()); });
        if (!instance.IsOwner) { Shutdown(); return; }
        Store = new(path); Settings = Store.Load(new ModelCatalog());
        // 0.17.5 parity: a provider failure must never end the whole app. Keep running and say so.
        DispatcherUnhandledException += (_, args) =>
        {
            if (args.Exception is OutOfMemoryException or StackOverflowException) return;
            args.Handled = true;
            // Opt-in developer diagnostics: exception type and stack only, never provider payloads.
            var logIndex = Array.IndexOf(e.Args, "--error-log-dir");
            if (logIndex >= 0 && logIndex + 1 < e.Args.Length)
                try { Directory.CreateDirectory(e.Args[logIndex + 1]); File.AppendAllText(Path.Combine(e.Args[logIndex + 1], "errors.txt"), DateTimeOffset.Now.ToString("O") + " " + args.Exception + Environment.NewLine); } catch (IOException) { }
            if (MainWindow is AUV.Windows.App.MainWindow main) main.Model.Status = UiText.T("An operation did not complete. AUV kept running; try again.", "有一项操作未完成。AUV 仍在运行，请重试。");
        };
        TaskScheduler.UnobservedTaskException += (_, args) => args.SetObserved();
        UiText.Current = UiText.Resolve(Settings.Language);
        if (e.Args.Contains("--show-widget")) Settings.Desktop.WidgetVisible = true;
        ApplyTheme(Settings.Theme);
        SystemEvents.UserPreferenceChanged += SystemPreferenceChanged;
        SystemParameters.StaticPropertyChanged += SystemParameterChanged;
        var window = new MainWindow(new MainViewModel(Demo, Settings)); MainWindow = window;
        Desktop = new(this, window);
        Providers = new(this, window);
        PropertyChanged?.Invoke(this, new(nameof(Desktop)));
        PropertyChanged?.Invoke(this, new(nameof(Providers)));
        var startupHandled = false;
        window.Loaded += async (_, _) =>
        {
            if (startupHandled) return;
            startupHandled = true;
            Desktop.Start();
            var productIndex = Array.IndexOf(e.Args, "--product-check-dir");
            if (productIndex >= 0 && productIndex + 1 < e.Args.Length)
                await ProductVerification.Run(this, window, Path.GetFullPath(e.Args[productIndex + 1]));
            var refinementIndex = Array.IndexOf(e.Args, "--refinement-check-dir");
            if (refinementIndex >= 0 && refinementIndex + 1 < e.Args.Length)
                await RefinementVerification.Run(this, window, Path.GetFullPath(e.Args[refinementIndex + 1]));
            var desktopIndex = Array.IndexOf(e.Args, "--desktop-check-dir");
            if (desktopIndex >= 0 && desktopIndex + 1 < e.Args.Length)
                await DesktopVerification.Run(this, window, Path.GetFullPath(e.Args[desktopIndex + 1]));
            var layoutIndex = Array.IndexOf(e.Args, "--layout-check-dir");
            if (layoutIndex >= 0 && layoutIndex + 1 < e.Args.Length)
                await LayoutVerification.Run(window, Path.GetFullPath(e.Args[layoutIndex + 1]));
            var featureIndex = Array.IndexOf(e.Args, "--feature-check-dir");
            if (featureIndex >= 0 && featureIndex + 1 < e.Args.Length)
                await FeatureVerification.Run(this, window, Path.GetFullPath(e.Args[featureIndex + 1]));
            var companionIndex = Array.IndexOf(e.Args, "--companion-check-dir");
            if (companionIndex >= 0 && companionIndex + 1 < e.Args.Length)
                await CompanionVerification.Run(Path.GetFullPath(e.Args[companionIndex + 1]));
            var claudeIndex = Array.IndexOf(e.Args, "--claude-check-dir");
            if (claudeIndex >= 0 && claudeIndex + 1 < e.Args.Length && e.Args.Contains("--offline"))
                await ClaudeVerification.Run(this, window, Path.GetFullPath(e.Args[claudeIndex + 1]), e.Args.Contains("--claude-check-before") ? "before" : "after");
            if (!e.Args.Contains("--offline")) Providers.Start();
            var refreshIndex = Array.IndexOf(e.Args, "--refresh-check-dir");
            if (refreshIndex >= 0 && refreshIndex + 1 < e.Args.Length)
                await FeatureVerification.RecordRefresh(this, window, Path.GetFullPath(e.Args[refreshIndex + 1]), 2);
            var liveIndex = Array.IndexOf(e.Args, "--live-check-dir"); var stageIndex = Array.IndexOf(e.Args, "--live-stage"); var baselineIndex = Array.IndexOf(e.Args, "--upgrade-baseline");
            if (liveIndex >= 0 && liveIndex + 1 < e.Args.Length && stageIndex >= 0 && stageIndex + 1 < e.Args.Length)
                await FeatureVerification.Live(this, window, Path.GetFullPath(e.Args[liveIndex + 1]), e.Args[stageIndex + 1],
                    baselineIndex >= 0 && baselineIndex + 1 < e.Args.Length ? Path.GetFullPath(e.Args[baselineIndex + 1]) : null);
            var providerIndex = Array.IndexOf(e.Args, "--provider-check-dir");
            if (providerIndex >= 0 && providerIndex + 1 < e.Args.Length)
                await ProviderVerification.Run(this, window, Path.GetFullPath(e.Args[providerIndex + 1]));
            var focusIndex = Array.IndexOf(e.Args, "--focus-check-dir");
            if (focusIndex >= 0 && focusIndex + 1 < e.Args.Length && Demo && e.Args.Contains("--offline"))
                await RefinementVerification.CheckExternalFocus(this, window, Path.GetFullPath(e.Args[focusIndex + 1]));
            if (e.Args.Contains("--quit-after-checks")) Desktop.Quit();
        };
        window.Show();
        if (Store.LastError != null) window.Model.Status = Store.LastError;
    }
    private void SystemPreferenceChanged(object sender, UserPreferenceChangedEventArgs e) => Dispatcher.BeginInvoke(() => ApplyTheme(Settings.Theme));
    private void SystemParameterChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e) => Dispatcher.BeginInvoke(() => ApplyTheme(Settings.Theme));
    protected override void OnExit(ExitEventArgs e) { SystemEvents.UserPreferenceChanged -= SystemPreferenceChanged; SystemParameters.StaticPropertyChanged -= SystemParameterChanged; Providers?.Dispose(); Desktop?.Dispose(); instance?.Dispose(); base.OnExit(e); }
    /// <summary>"System", "en" or "zh". Applies at once to every window, the tray and provider text.</summary>
    public void ApplyLanguage(string language)
    {
        Settings.Language = language is "en" or "zh" ? language : "System";
        UiText.Current = UiText.Resolve(Settings.Language);
        if (MainWindow is AUV.Windows.App.MainWindow main) { if (main.Model.Status is "Ready" or "就绪") main.Model.Status = UiText.T("Ready", "就绪"); main.Model.RefreshText(); }
        Desktop?.RefreshText(); Desktop?.RefreshWizard();
    }
    public bool IsDark { get; private set; }
    public bool FluentComboStyleAvailable { get; private set; }
    public void SetLargerText(bool larger) { Settings.LargerText = larger; foreach (Window w in Windows) w.FontSize = larger ? 17.5 : 14; Desktop?.RefreshWizard(); }
    public void ApplyTheme(string theme)
    {
        var light = theme == "Light" || theme == "System" && WindowsAppearance.SystemLight;
        IsDark = !light;
        // WPF 10 still marks the code setter experimental. Limit suppression to this single adapter.
#pragma warning disable WPF0001
        ThemeMode = light ? System.Windows.ThemeMode.Light : System.Windows.ThemeMode.Dark;
#pragma warning restore WPF0001
        Resources.Remove(typeof(ComboBox));
        var fluentCombo = TryFindResource(typeof(ComboBox)) as Style;
        FluentComboStyleAvailable = fluentCombo != null;
        var compactCombo = new Style(typeof(ComboBox), fluentCombo);
        compactCombo.Setters.Add(new Setter(Control.MinHeightProperty, 32d));
        compactCombo.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch));
        Resources[typeof(ComboBox)] = compactCombo;
        var colors = new Dictionary<string, string>
        {
            ["CanvasBrush"] = light ? "#F3F5F8" : "#1C1F24", ["SurfaceBrush"] = light ? "#FFFFFF" : "#22262C",
            ["RaisedBrush"] = light ? "#E6EAF0" : "#2B3039", ["BorderBrush"] = light ? "#C5CBD5" : "#3B424F",
            ["TextBrush"] = light ? "#20252D" : "#EBEDF3", ["MutedBrush"] = light ? "#596373" : "#A8AFBC",
            ["AccentBrush"] = light ? "#864495" : "#CA72DA", ["SelectionBrush"] = light ? "#EADDF0" : "#393044",
            ["WarningBrush"] = light ? "#86541D" : "#F2C27B"
        };
        foreach (var pair in colors) Resources[pair.Key] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(pair.Value));
        Resources["AccentBrush"] = SystemColors.AccentColorBrush;
        Resources["SelectionBrush"] = new SolidColorBrush(SystemColors.AccentColor) { Opacity = light ? .15 : .24 };
        Resources["QuotaLowBrush"] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(light ? "#CC3535" : "#FF7777"));
        Resources["QuotaNormalBrush"] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(light ? "#12865A" : "#42DFA0"));
        Resources["QuotaNeutralBrush"] = new SolidColorBrush((Color)ColorConverter.ConvertFromString(light ? "#2563EB" : "#60A5FA"));
        Resources["ChartBrush"] = Resources["QuotaNeutralBrush"];
        if (SystemParameters.HighContrast)
        {
            foreach (var key in new[] { "CanvasBrush", "SurfaceBrush", "RaisedBrush" }) Resources[key] = SystemColors.WindowBrush;
            foreach (var key in new[] { "TextBrush", "MutedBrush", "BorderBrush", "QuotaLowBrush", "QuotaNormalBrush", "QuotaNeutralBrush", "ChartBrush", "WarningBrush" }) Resources[key] = SystemColors.WindowTextBrush;
            Resources["AccentBrush"] = SystemColors.HighlightBrush;
        }
        if (Settings != null) Settings.Theme = theme;
        foreach (Window window in Windows)
        {
            NativeAppearance.Apply(window, !light);
            if (window is AUV.Windows.App.MainWindow or SettingsWindow or WorkBuddyConnectionWindow) AppBrandIcon.Apply(window, !light);
            // Custom-drawn quota rows also need repainting after replacing semantic brushes.
            InvalidateRows(window);
        }
        Desktop?.UpdateAppearance();
    }
    private static void InvalidateRows(DependencyObject parent)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = VisualTreeHelper.GetChild(parent, i);
            if (child is AllowanceRow row) row.InvalidateVisual();
            else if (child is DetailQuotaBar bar) bar.InvalidateVisual();
            InvalidateRows(child);
        }
    }
}
internal static class WindowsAppearance
{
    private static int Preference(string name, int fallback)
    { using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"); return key?.GetValue(name) is int value ? value : fallback; }
    public static bool SystemLight => Preference("AppsUseLightTheme", 1) != 0;
    public static bool ShellLight => Preference("SystemUsesLightTheme", 1) != 0;
    public static bool Transparency => Preference("EnableTransparency", 1) != 0 && !SystemParameters.HighContrast;
}
