using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using AUV.Windows.Core;
namespace AUV.Windows.App;

/// <summary>Explicit demo-only native WPF self-test. Does not alter OS settings or dispatch work.</summary>
internal static class ProductVerification
{
    internal static void Capture(FrameworkElement visual, string path, double scale = 1)
    {
        visual.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(visual.ActualWidth * scale), (int)Math.Ceiling(visual.ActualHeight * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
        bitmap.Render(visual); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path); encoder.Save(stream);
    }
    internal static async Task Run(App app, MainWindow main, string directory)
    {
        Directory.CreateDirectory(directory);
        if (!app.Demo) { File.WriteAllText(Path.Combine(directory, "NOT_RUN.txt"), "Synthetic provider matrix requires --demo and isolated preferences."); return; }
        var agents = main.Model.Shell.Agents; var desktop = app.Desktop;
        var original = JsonSerializer.Deserialize<DesktopPreferences>(JsonSerializer.Serialize(app.Settings.Desktop))!;
        var originalTheme = app.Settings.Theme; var originalLarger = app.Settings.LargerText;
        var originalPosition = app.Windows.OfType<DesktopWidget>().FirstOrDefault() is { } existing ? NativeDesktop.Rectangle(existing) : (NativeDesktop.Rect?)null;
        var mainPosition = NativeDesktop.Rectangle(main); var mainWidth = main.Width; var mainHeight = main.Height;
        var results = new List<object>(); var checks = new List<string>();
        void Require(bool valid, string check) { if (!valid) throw new InvalidOperationException(check); checks.Add(check); }
        async Task Settle() { await main.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ContextIdle); }
        DesktopWidget Wizard() => app.Windows.OfType<DesktopWidget>().Single();
        var fixtures = new[]
        {
            new AllowanceCard("codex", "Codex", "C", "Pro", AllowanceKind.Percentage, 100, null, "7-day", "DEMO exact source", "DEMO snapshot", ConnectionState.Connected),
            new AllowanceCard("claude", "Claude", "✳", "Pro", AllowanceKind.Estimated, 100, null, "5-hour", "DEMO estimated source", "DEMO retained snapshot", ConnectionState.Stale, true),
            new AllowanceCard("workbuddy", "WorkBuddy", "W", null, AllowanceKind.Credits, null, 1234567, "Native balance", "DEMO credits source", "DEMO snapshot", ConnectionState.Connected),
            new AllowanceCard("antigravity", "Antigravity", "A", null, AllowanceKind.Unlimited, null, null, "Verified unlimited fixture", "DEMO source", "DEMO snapshot", ConnectionState.Reconnecting),
            new AllowanceCard("test.only", "Synthetic only", "?", null, AllowanceKind.Unavailable, null, null, "Unavailable", "DEMO source", "DEMO snapshot", ConnectionState.Failed)
        };
        AgentPresentation[] Project(int count) => fixtures.Take(count).Select(c => new AgentPresentation(c.Id, c.Name, c.Mark, UsageSnapshot.Unknown, true, c)).ToArray();
        try
        {
            // Loaded runs inside the first Show(), before Windows finishes initial activation.
            // Let that expected startup transition settle before measuring subsequent focus changes.
            await Task.Delay(500); await Settle();
            main.Activate(); await Task.Delay(200); await Settle();
            results.Add(new { Stage = "startup-settled", MainForeground = NativeDesktop.Foreground == new System.Windows.Interop.WindowInteropHelper(main).Handle });
            desktop.Enabled = true; desktop.SetWidgetVisible(true);
            foreach (var preference in Enum.GetValues<WizardDensity>())
            {
                desktop.Density = preference;
                foreach (var count in new[] { 0, 1, 2, 4, 5, 4 })
                {
                    var foreground = NativeDesktop.Foreground;
                    main.Model.Shell.ReplaceAdmittedPresentation(Project(count)); await Settle();
                    var afterForeground = NativeDesktop.Foreground;
                    if (afterForeground != foreground) results.Add(new { Stage = "focus-change", Check = $"{preference}/{count}", Before = foreground.ToInt64(), After = afterForeground.ToInt64() });
                    Require(afterForeground == foreground, $"No focus theft: {preference}/{count}");
                    Require(app.Settings.Desktop.Density == preference, $"Preference retained: {preference}/{count}");
                    var visibleCount = Project(count).Count(a => a.Card.HasDisplayableQuota);
                    if (visibleCount == 0) Require(!desktop.WidgetVisible, "Zero available quotas hide Wizard");
                    else
                    {
                        var wizard = Wizard(); Require(wizard.RenderedDensity == WizardPolicy.Resolve(preference, visibleCount), $"Density resolved: {preference}/{visibleCount}");
                        Require(NativeDesktop.IsNonActivating(wizard) && !wizard.ShowInTaskbar, "Nonactivating native tool window without taskbar button");
                        if (wizard.RenderedDensity == WizardDensity.Regular) { Require(Math.Abs(wizard.ActualWidth - WizardPolicy.RegularWidth) < 1, "Regular width follows the Wizard policy"); Require(Math.Abs(wizard.ActualHeight - WizardPolicy.StackHeight(visibleCount, WizardPolicy.RegularRowHeight)) < 1, "Regular stack geometry"); }
                        Capture((FrameworkElement)wizard.Content, Path.Combine(directory, $"wizard-{preference}-{count}.png"));
                    }
                    results.Add(new { Stage = $"{preference}-{count}", State = desktop.Evidence });
                }
            }
            main.Model.Shell.ReplaceAdmittedPresentation(Project(4)); desktop.Density = WizardDensity.Minimalist; await Settle();
            var stableWidth = Wizard().ActualWidth;
            foreach (var number in new[] { 0d, 1, 9, 10, 19, 20, 50, 99, 100, 9.5, double.NaN })
            {
                var c = new AllowanceCard("codex", "Codex", "C", "Pro", AllowanceKind.Percentage, number, null, "7-day", "DEMO exact source", "DEMO snapshot", ConnectionState.Connected);
                var changed = Project(4); changed[0] = new("codex", "Codex", "C", UsageSnapshot.Unknown, true, c);
                main.Model.Shell.ReplaceAdmittedPresentation(changed); await Settle();
                Require(Math.Abs(Wizard().ActualWidth - stableWidth) < .1, $"Stable width for {number}");
                Require(ReferenceEquals(main.Model.SelectedCard, changed[0].Card), "Shared main card identity");
            }
            byte[] RowPixels(double number)
            {
                var row = new AllowanceRow { Width = 210, Height = 60, Card = new("codex", "Codex", "C", "Pro", AllowanceKind.Percentage, number, null, "7-day", "DEMO source", "DEMO snapshot", ConnectionState.Connected), ShowStatus = false };
                row.Measure(new(210, 60)); row.Arrange(new Rect(0, 0, 210, 60)); row.UpdateLayout();
                var image = new RenderTargetBitmap(210, 60, 96, 96, PixelFormats.Pbgra32); image.Render(row);
                var pixels = new byte[210 * 60 * 4]; image.CopyPixels(pixels, 210 * 4, 0); return pixels;
            }
            var baseline = RowPixels(0);
            foreach (var number in new[] { 0d, 1, 9, 10, 19, 20, 50, 99, 100, 9.5, double.NaN })
            {
                var pixels = RowPixels(number); var observed = 0;
                for (var x = 1; x < 209; x++) { var i = (50 * 210 + x) * 4; if (pixels[i] != baseline[i] || pixels[i + 1] != baseline[i + 1] || pixels[i + 2] != baseline[i + 2]) observed++; }
                var expected = double.IsNaN(number) ? 0 : Math.Clamp(Math.Ceiling(210 * number / 100) - 1, 0, 208);
                Require(Math.Abs(observed - expected) <= 1, $"Rendered proportional row fill: {number}");
                results.Add(new { Stage = "rendered-fill-pixels", Value = double.IsNaN(number) ? "invalid" : number.ToString(), ObservedColoredPixels = observed, ExpectedColoredPixels = expected, SampleRow = 50 });
            }
            main.Model.GenerateCommand.Execute(null); main.Model.CopyCommand.Execute(null);
            Require(Clipboard.ContainsText() && Clipboard.GetText() == main.Model.Generated, "Clipboard bytes equal exact generated instruction");
            foreach (var theme in new[] { "Light", "Dark", "System" })
            {
                app.ApplyTheme(theme); await Settle(); Capture((FrameworkElement)Wizard().Content, Path.Combine(directory, $"wizard-{theme}.png"));
                Require(app.Settings.Theme == theme, "Theme preference retained");
            }
            app.SetLargerText(true); await Settle(); Capture((FrameworkElement)Wizard().Content, Path.Combine(directory, "wizard-larger-text.png"));
            app.SetLargerText(false);
            var overflowCards = Enumerable.Range(0, 80).Select(i => new AgentPresentation($"fixture.{i}", "Synthetic overflow", "?", UsageSnapshot.Unknown, true,
                fixtures[0] with { Id = $"fixture.{i}", Name = "Synthetic overflow" })).ToArray();
            main.Model.Shell.ReplaceAdmittedPresentation(overflowCards); await Settle();
            Require(Wizard().ActualHeight <= NativeDesktop.WorkDips(Wizard()).Height + 1, "Overflow bounded to monitor work area");
            Capture((FrameworkElement)Wizard().Content, Path.Combine(directory, "wizard-bounded-overflow.png"));
            main.Model.Shell.ReplaceAdmittedPresentation(Project(4)); await Settle();
            Wizard().Left = 10000; Wizard().Top = -10000; NativeDesktop.ClampToMonitor(Wizard());
            var rect = NativeDesktop.Rectangle(Wizard()); var work = NativeDesktop.WorkDips(Wizard()); var dpi = VisualTreeHelper.GetDpi(Wizard()).PixelsPerDip;
            Require(rect.Left >= work.Left * dpi - 1 && rect.Top >= work.Top * dpi - 1, "Offscreen position repaired on nearest monitor");
            var nativeRectangle = rect;
            results.Add(new { Stage = "position-recovery", nativeRectangle.Left, nativeRectangle.Top, nativeRectangle.Right, nativeRectangle.Bottom });
            desktop.ShowFill = false; desktop.ShowStatus = false; await Settle(); Capture((FrameworkElement)Wizard().Content, Path.Combine(directory, "wizard-display-switches-off.png"));
            desktop.ShowFill = true; desktop.ShowStatus = true;
            // This phase moves the main window as well. Establish its known foreground first;
            // Wizard-only movement against an external foreground has a separate opt-in check.
            main.Activate(); await Task.Delay(200); await Settle();
            var monitorIndex = 0;
            foreach (var area in NativeDesktop.MonitorWorkAreas())
            {
                var foreground = NativeDesktop.Foreground;
                NativeDesktop.Move(Wizard(), (int)area.Left + 24, (int)area.Top + 24);
                NativeDesktop.Move(main, (int)area.Left + 72, (int)area.Top + 72);
                await Task.Delay(300); await Settle();
                NativeDesktop.ClampToMonitor(Wizard()); NativeDesktop.ClampToMonitor(main);
                var afterForeground = NativeDesktop.Foreground;
                if (afterForeground != foreground) results.Add(new { Stage = "focus-change", Check = "per-monitor", Before = foreground.ToInt64(), After = afterForeground.ToInt64() });
                Require(afterForeground == foreground, "Per-monitor movement does not activate windows");
                results.Add(new { Stage = "real-per-monitor", MonitorIndex = monitorIndex, WorkPixels = area, WizardDpi = VisualTreeHelper.GetDpi(Wizard()).PixelsPerInchX,
                    MainDpi = VisualTreeHelper.GetDpi(main).PixelsPerInchX, WizardWidth = Wizard().ActualWidth, WizardHeight = Wizard().ActualHeight,
                    MainClientWidth = ((FrameworkElement)main.Content).ActualWidth, MainClientHeight = ((FrameworkElement)main.Content).ActualHeight });
                Capture((FrameworkElement)Wizard().Content, Path.Combine(directory, $"wizard-monitor-{monitorIndex}.png"));
                Capture((FrameworkElement)main.Content, Path.Combine(directory, $"main-monitor-{monitorIndex}.png")); monitorIndex++;
            }
            desktop.Enabled = false; Require(!desktop.WidgetVisible && app.Settings.Desktop.WidgetVisible, "Enabled and desired visibility independent");
            desktop.Enabled = true; Require(desktop.WidgetVisible, "Re-enable restores desired visibility");
            desktop.AlwaysOnTop = false; Require(!NativeDesktop.IsTopmost(Wizard()), "Native unpin");
            desktop.AlwaysOnTop = true; Require(NativeDesktop.IsTopmost(Wizard()), "Native pin");
            desktop.HideMain(); Require(!main.IsVisible && desktop.WidgetVisible, "Wizard independent of hidden main"); desktop.OpenMain();
            Require(app.Windows.OfType<DesktopWidget>().Count() == 1, "One Wizard instance");
            desktop.SetWidgetVisible(false); results.Add(new { Stage = "hidden", State = desktop.Evidence });
            desktop.ToggleFlyout(); await Task.Delay(2200); results.Add(new { Stage = "quick-panel-live-counters", State = desktop.Evidence });
            Capture((FrameworkElement)app.Windows.OfType<UsageFlyout>().Single().Content, Path.Combine(directory, "quick-panel.png")); desktop.ToggleFlyout();
            main.Model.Storage.FixtureError = true; main.Model.Shell.Section = "Sectorium"; await Settle(); Capture((FrameworkElement)main.Content, Path.Combine(directory, "sectorium-error.png"));
            main.Model.Shell.Section = "AUV"; main.Model.Shell.Section = "Sectorium"; Require(main.Model.Storage.FixtureError, "Storage fixture survives navigation");
            var measure = WizardTypography.Measure(fixtures.Select(c => c.Value));
            Require(app.FluentComboStyleAvailable, "Installed Fluent ComboBox base style available");
            results.Add(new { Stage = "measured-font", measure.Width, measure.Height, measure.ValueWidth, Dpi = VisualTreeHelper.GetDpi(main).PixelsPerInchX });
            File.WriteAllText(Path.Combine(directory, "PASS.txt"), string.Join(Environment.NewLine, checks));
        }
        catch (Exception e) { File.WriteAllText(Path.Combine(directory, "ERROR.txt"), e.ToString()); }
        finally
        {
            main.Model.Shell.ReplaceAdmittedPresentation(agents); main.Model.Storage.FixtureError = false; main.Model.Shell.Section = "AUV";
            app.Settings.Desktop = original; app.ApplyTheme(originalTheme); app.SetLargerText(originalLarger); desktop.RefreshWizard();
            if (originalPosition is NativeDesktop.Rect point && app.Windows.OfType<DesktopWidget>().FirstOrDefault() is { } restored)
            { NativeDesktop.Move(restored, point.Left, point.Top); NativeDesktop.ClampToMonitor(restored); }
            NativeDesktop.Move(main, mainPosition.Left, mainPosition.Top); main.Width = mainWidth; main.Height = mainHeight; NativeDesktop.ClampToMonitor(main);
            await Settle(); main.Persist();
            File.WriteAllText(Path.Combine(directory, "results.json"), JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        }
    }
}
