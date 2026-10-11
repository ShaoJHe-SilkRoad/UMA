using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using AUV.Windows.Core;

namespace AUV.Windows.App;

/// <summary>Opt-in demo checks against actual native visuals; no provider transport or OS changes.</summary>
internal static class RefinementVerification
{
    private static IEnumerable<DependencyObject> Walk(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = VisualTreeHelper.GetChild(root, i); yield return child;
            foreach (var nested in Walk(child)) yield return nested;
        }
    }
    private static async Task Settle(MainWindow main)
    {
        await main.Dispatcher.InvokeAsync(() => main.UpdateLayout(), DispatcherPriority.ContextIdle);
        await Task.Delay(100);
    }
    private static DesktopPreferences Clone(DesktopPreferences source) => JsonSerializer.Deserialize<DesktopPreferences>(JsonSerializer.Serialize(source))!;
    private static AgentPresentation Agent(AllowanceCard card) => new(card.Id, card.Name, card.Mark, UsageSnapshot.Unknown, true, card);
    private static AllowanceCard Credits(decimal value) => new("workbuddy", "WorkBuddy", "W", null, AllowanceKind.Credits, null, value, "Native balance", "DEMO verification", "DEMO snapshot", ConnectionState.Connected);

    internal static async Task Run(App app, MainWindow main, string directory)
    {
        Directory.CreateDirectory(directory);
        if (!app.Demo) { File.WriteAllText(Path.Combine(directory, "NOT_RUN.txt"), "Requires explicit demo mode."); return; }
        var agents = main.Model.Shell.Agents; var preferences = Clone(app.Settings.Desktop);
        var theme = app.Settings.Theme; var selected = main.Model.Shell.SelectedAgent.Id; var section = main.Model.Shell.Section;
        var checks = new List<string>(); var observations = new List<object>();
        SettingsWindow? settings = null;
        void Require(bool valid, string message) { if (!valid) throw new InvalidOperationException(message); checks.Add(message); }
        DesktopWidget Wizard() => app.Windows.OfType<DesktopWidget>().Single();
        var codex = new AllowanceCard("codex", "Codex", "C", "Pro", AllowanceKind.Percentage, 0, null, "7-day", "DEMO verification", "DEMO snapshot", ConnectionState.Connected);
        var unknown = agents.Select(a => Agent(new AllowanceCard(a.Id, a.Name, a.Card.Mark, null, AllowanceKind.Unavailable, null, null, "Unavailable", "DEMO verification", "DEMO snapshot", ConnectionState.Disconnected))).ToArray();
        AgentPresentation[] Available(decimal credits) => unknown.Select(a => a.Id == "codex" ? Agent(codex) : a.Id == "workbuddy" ? Agent(Credits(credits)) : a).ToArray();
        try
        {
            main.Model.Shell.Section = "AUV"; app.Desktop.Enabled = true; app.Desktop.SetWidgetVisible(true);
            main.Model.Shell.ReplaceAdmittedPresentation(unknown); await Settle(main);
            Require(!app.Desktop.WidgetVisible && app.Desktop.WidgetRequested, "No quota hides the Wizard while retaining its requested state");
            Require(main.Model.Shell.Agents.Length == agents.Length, "Unavailable providers retain their settings routes");
            var rows = Walk(main).OfType<AllowanceRow>().Where(r => r.Name == "ProviderRow").ToArray();
            observations.Add(new { Stage = "unavailable-rail", Rows = rows.Select(r => new { r.ActualHeight, r.Height, r.MinHeight,
                Id = r.Card?.Id, r.Card?.HasDisplayableQuota, Context = r.DataContext?.GetType().Name,
                HeightSource = DependencyPropertyHelper.GetValueSource(r, FrameworkElement.HeightProperty).BaseValueSource.ToString() }).ToArray() });
            Require(rows.Length == agents.Length && rows.All(r => Math.Abs(r.ActualHeight - 36) < 1), "Unavailable native rail rows are 36 DIP");
            Require(rows.All(r => (string)r.ToolTip == r.Card!.Name), "Unavailable row tooltips contain identity only");
            Require(!main.Model.HasUsage && !main.Model.HasChart && !main.Model.HasLocalCost && !main.Model.HasData, "Unknown details have no quota/chart/cost/source placeholder blocks");
            ProductVerification.Capture((FrameworkElement)main.Content, Path.Combine(directory, "main-unavailable.png"));
            app.Desktop.ToggleWidgetCommand.Execute(null);
            Require(!app.Desktop.WidgetRequested && !app.Desktop.WidgetVisible, "Toggle can turn off an empty requested Wizard");
            main.Model.Shell.ReplaceAdmittedPresentation(Available(0)); await Settle(main);
            Require(!app.Desktop.WidgetVisible, "New data does not override an explicit Wizard-off preference");
            app.Desktop.SetWidgetVisible(true); await Settle(main);
            Require(app.Desktop.WidgetVisible && Wizard().CardCount == 2, "Verified zero percent and zero Credits remain visible");
            rows = Walk(main).OfType<AllowanceRow>().Where(r => r.Name == "ProviderRow").ToArray();
            Require(rows.All(r => Math.Abs(r.ActualHeight - (r.Card!.HasDisplayableQuota ? 64 : 36)) < 1), "Mixed native rail row heights follow quota availability");
            main.Model.Shell.ReplaceAdmittedPresentation(Available(9600)); app.Desktop.Density = WizardDensity.Regular; await Settle(main);
            Require(Math.Abs(Wizard().ActualWidth - WizardPolicy.RegularWidth) < 1, "Regular native width follows the Wizard policy");
            Require(Walk(Wizard()).OfType<AllowanceRow>().All(r => Math.Abs(r.ActualHeight - 48) < 1), "Regular native row height is 48 DIP");
            ProductVerification.Capture((FrameworkElement)Wizard().Content, Path.Combine(directory, "regular-9600.png"));
            foreach (var value in new[] { 999m, 1500, 9900, 10000, 14000, 99000, 1300000 })
            {
                main.Model.Shell.ReplaceAdmittedPresentation(Available(value)); app.Desktop.Density = WizardDensity.Minimalist; await Settle(main);
                var row = Walk(Wizard()).OfType<AllowanceRow>().Single(r => r.Card?.Id == "workbuddy");
                Require(row.Card!.MinimalistValue.Length <= 4 && ((string)row.ToolTip).Contains(row.Card.Value), $"Native Credit label and exact tooltip: {value}");
                observations.Add(new { Stage = "compact-credit", Exact = value, Label = row.Card.MinimalistValue, WizardWidth = Wizard().ActualWidth, RowHeight = row.ActualHeight });
                ProductVerification.Capture((FrameworkElement)Wizard().Content, Path.Combine(directory, $"minimalist-{value}.png"));
            }
            settings = new SettingsWindow(main, null); settings.Show();
            foreach (var choice in new[] { "Light", "Dark", "System" })
            {
                app.ApplyTheme(choice); await Settle(main);
                ProductVerification.Capture((FrameworkElement)main.Content, Path.Combine(directory, $"main-{choice}.png"));
                ProductVerification.Capture((FrameworkElement)Wizard().Content, Path.Combine(directory, $"minimalist-{choice}.png"));
                ProductVerification.Capture((FrameworkElement)settings.Content, Path.Combine(directory, $"settings-{choice}.png"));
                foreach (var target in new Window[] { main, settings })
                foreach (var big in new[] { false, true })
                {
                    var surface = target is MainWindow ? "main" : "settings";
                    var icon = SendMessage(new WindowInteropHelper(target).Handle, 0x007f, big ? 1 : 0, 0);
                    Require(icon != 0, $"Native {surface} {(big ? "taskbar" : "title")} icon exists: {choice}");
                    var bitmap = new FormatConvertedBitmap(Imaging.CreateBitmapSourceFromHIcon(icon, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions()), PixelFormats.Bgra32, null, 0);
                    var pixels = new byte[bitmap.PixelWidth * bitmap.PixelHeight * 4]; bitmap.CopyPixels(pixels, bitmap.PixelWidth * 4, 0);
                    var opaque = Enumerable.Range(0, pixels.Length / 4).Where(i => pixels[i * 4 + 3] > 200).ToArray();
                    var mean = opaque.Average(i => (pixels[i * 4] + pixels[i * 4 + 1] + pixels[i * 4 + 2]) / 3d);
                    var darkInk = big ? WindowsAppearance.ShellLight : !app.IsDark;
                    Require(SystemParameters.HighContrast || (darkInk ? mean < 90 : mean > 190), $"Native {surface} {(big ? "taskbar" : "title")} ink matches its surface: {choice}");
                    observations.Add(new { Stage = "native-icon", Surface = surface, Theme = choice, Big = big, WindowsAppearance.ShellLight, MeanInk = mean });
                    var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using var stream = File.Create(Path.Combine(directory, $"icon-{surface}-{choice}-{(big ? "taskbar" : "title")}.png")); encoder.Save(stream);
                }
            }
            settings.Close(); settings = null;
            app.Desktop.ToggleFlyout(); await Settle(main);
            var panel = app.Windows.OfType<UsageFlyout>().Single();
            var populatedHeight = panel.ActualHeight;
            Require(Walk(panel).OfType<AllowanceRow>().Count(r => r.IsVisible) == 2, "Tray lists only two fetched quotas");
            main.Model.Shell.ReplaceAdmittedPresentation(unknown); await Settle(main);
            Require(!app.Desktop.WidgetVisible && app.Desktop.WidgetRequested, "Withdrawal hides an enabled Wizard");
            Require(panel.ActualHeight < populatedHeight && !Walk(panel).OfType<AllowanceRow>().Any(r => r.IsVisible), "Tray shrinks after quotas are withdrawn");
            ProductVerification.Capture((FrameworkElement)panel.Content, Path.Combine(directory, "tray-unavailable.png"));
            app.Desktop.ToggleFlyout();
            main.Model.Shell.ReplaceAdmittedPresentation(Available(9600)); await Settle(main);
            Require(app.Desktop.WidgetVisible, "Requested Wizard reappears when valid data returns");
            var stale = Available(9600).Select(a => Agent(a.Card with { IsStale = true })).ToArray();
            main.Model.Shell.ReplaceAdmittedPresentation(stale); await Settle(main);
            Require(!app.Desktop.WidgetVisible && !main.Model.HasQuotaAgents, "Stale quotas are withdrawn from native surfaces");
            File.WriteAllLines(Path.Combine(directory, "PASS.txt"), checks);
        }
        catch (Exception error) { File.WriteAllText(Path.Combine(directory, "ERROR.txt"), error.ToString()); }
        finally
        {
            settings?.Close();
            if (app.Windows.OfType<UsageFlyout>().Any(w => w.IsVisible)) app.Desktop.ToggleFlyout();
            main.Model.Shell.ReplaceAdmittedPresentation(agents); app.Settings.Desktop = preferences;
            app.ApplyTheme(theme); app.Desktop.RefreshWizard(); main.Model.Shell.Section = section;
            main.Model.Shell.SelectedAgent = main.Model.Shell.Agents.First(a => a.Id == selected); main.Persist();
            File.WriteAllText(Path.Combine(directory, "results.json"), JsonSerializer.Serialize(observations, new JsonSerializerOptions { WriteIndented = true }));
        }
    }

    internal static async Task CheckExternalFocus(App app, MainWindow main, string directory)
    {
        Directory.CreateDirectory(directory); var preferences = Clone(app.Settings.Desktop); var observations = new List<object>();
        try
        {
            app.Desktop.Enabled = true; app.Desktop.SetWidgetVisible(true); await Settle(main);
            File.WriteAllText(Path.Combine(directory, "READY.txt"), "Activate a known external window, then create ARM.txt. No external window content is read.");
            var deadline = DateTime.UtcNow.AddSeconds(45);
            while (!File.Exists(Path.Combine(directory, "ARM.txt")) && DateTime.UtcNow < deadline) await Task.Delay(200);
            if (!File.Exists(Path.Combine(directory, "ARM.txt"))) throw new InvalidOperationException("External foreground check was not armed.");
            var before = NativeDesktop.Foreground; var process = NativeDesktop.ForegroundProcess;
            if (before == 0 || process == Environment.ProcessId) throw new InvalidOperationException("Requires a controlled external foreground window.");
            var wizard = app.Windows.OfType<DesktopWidget>().Single();
            foreach (var density in new[] { WizardDensity.Regular, WizardDensity.Minimalist })
            foreach (var area in NativeDesktop.MonitorWorkAreas())
            {
                app.Desktop.Density = density;
                NativeDesktop.Move(wizard, (int)area.Left + 24, (int)area.Top + 24); await Task.Delay(350); await Settle(main);
                NativeDesktop.ClampToMonitor(wizard);
                var after = NativeDesktop.Foreground;
                observations.Add(new { Density = density.ToString(), ForegroundBefore = before.ToInt64(), ForegroundAfter = after.ToInt64(), ExternalProcess = process,
                    WizardDpi = VisualTreeHelper.GetDpi(wizard).PixelsPerInchX });
                if (after != before) throw new InvalidOperationException("Wizard refresh or cross-monitor movement changed the external foreground.");
            }
            File.WriteAllText(Path.Combine(directory, "PASS.txt"), "Wizard refresh, density changes and movement on every connected monitor preserve the controlled external foreground.");
        }
        catch (Exception error) { File.WriteAllText(Path.Combine(directory, "ERROR.txt"), error.ToString()); }
        finally
        {
            app.Settings.Desktop = preferences; app.Desktop.RefreshWizard(); main.Persist();
            File.WriteAllText(Path.Combine(directory, "results.json"), JsonSerializer.Serialize(observations, new JsonSerializerOptions { WriteIndented = true }));
        }
    }
    [DllImport("user32.dll")] private static extern nint SendMessage(nint window, int message, nint wParam, nint lParam);
}
