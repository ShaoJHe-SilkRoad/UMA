using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using AUV.Windows.Core;

namespace AUV.Windows.App;

/// <summary>
/// Opt-in 0.18.4 parity checks. --feature-check-dir runs in demo mode with isolated preferences and writes
/// screenshots plus PASS/ERROR. --refresh-check-dir records automatic refresh ticks in normal mode: times,
/// connection state and the displayed value only; no account identity, credentials or file content.
/// </summary>
internal static class FeatureVerification
{
    private static IEnumerable<DependencyObject> Walk(DependencyObject root)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(root); i++)
        { var child = VisualTreeHelper.GetChild(root, i); yield return child; foreach (var nested in Walk(child)) yield return nested; }
    }
    private static async Task Settle(Window window) { await window.Dispatcher.InvokeAsync(() => window.UpdateLayout(), DispatcherPriority.ContextIdle); await Task.Delay(120); }

    internal static async Task Run(App app, MainWindow main, string directory)
    {
        Directory.CreateDirectory(directory);
        if (!app.Demo) { File.WriteAllText(Path.Combine(directory, "NOT_RUN.txt"), "Requires --demo and isolated preferences."); return; }
        var checks = new List<string>(); var observations = new List<object>();
        void Require(bool valid, string message) { if (!valid) throw new InvalidOperationException(message); checks.Add(message); }
        var language = app.Settings.Language; var order = app.Settings.AgentOrder.ToList(); var pin = app.Settings.TrayAgent; var section = main.Model.Shell.Section;
        SettingsWindow? settings = null;
        try
        {
            main.Model.Shell.Section = "AUV"; await Settle(main);
            // Navigation: ThreadOS is no longer a top-level tab.
            var navIds = Walk(main).OfType<RadioButton>().Select(r => System.Windows.Automation.AutomationProperties.GetAutomationId(r)).Where(id => id.StartsWith("auv.nav.")).ToArray();
            Require(navIds.SequenceEqual(["auv.nav.auv", "auv.nav.sectorium"]), "Top navigation has only AUV and Sectorium");
            foreach (var lang in new[] { "en", "zh" })
            {
                app.ApplyLanguage(lang); await Settle(main);
                foreach (var id in new[] { "codex", "workbuddy", "claude" })
                {
                    main.Model.Shell.SelectedAgent = main.Model.Shell.Agents.First(a => a.Id == id); await Settle(main);
                    ProductVerification.Capture((FrameworkElement)main.Content, Path.Combine(directory, $"main-{id}-{lang}.png"));
                }
                // Six global panes.
                settings = new SettingsWindow(main, null); settings.Show(); await Settle(settings);
                foreach (var pane in SettingsWindow.Panes)
                {
                    settings.ShowPane(pane); await Settle(settings);
                    Require(settings.SelectedPane == pane, $"Settings pane opens: {pane}/{lang}");
                    ProductVerification.Capture((FrameworkElement)settings.Content, Path.Combine(directory, $"settings-{pane}-{lang}.png"));
                }
                settings.Close(); settings = null;
                foreach (var id in new[] { "codex", "claude" })
                {
                    settings = new SettingsWindow(main, id); settings.Show(); await Settle(settings);
                    ProductVerification.Capture((FrameworkElement)settings.Content, Path.Combine(directory, $"agent-settings-{id}-{lang}.png"));
                    settings.Close(); settings = null;
                }
            }
            Require(UiText.Current == UiLanguage.Chinese && main.Model.RemainingLabel == "剩余", "Chinese applies to view-model text immediately");
            app.ApplyLanguage("en"); await Settle(main);
            Require(main.Model.RemainingLabel == "Remaining", "English applies back immediately");
            // ThreadOS from Codex settings, then Back to Codex.
            main.Model.Shell.SelectedAgent = main.Model.Shell.Agents.First(a => a.Id == "codex");
            settings = new SettingsWindow(main, "codex"); settings.Show(); await Settle(settings);
            var open = Walk(settings).OfType<Button>().Single(b => System.Windows.Automation.AutomationProperties.GetAutomationId(b) == "auv.agent.settings.threados");
            open.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); settings = null; await Settle(main);
            Require(main.Model.Shell.Section == "ThreadOS", "Codex settings opens ThreadOS");
            var back = Walk(main).OfType<Button>().Single(b => System.Windows.Automation.AutomationProperties.GetAutomationId(b) == "auv.threados.back");
            Require(back.IsVisible, "Back to Codex is visible on ThreadOS");
            ProductVerification.Capture((FrameworkElement)main.Content, Path.Combine(directory, "threados-from-codex.png"));
            back.RaiseEvent(new RoutedEventArgs(Button.ClickEvent)); await Settle(main);
            Require(main.Model.Shell.Section == "AUV" && main.Model.Shell.SelectedAgent.Id == "codex" && !back.IsVisible, "Back to Codex returns to the Codex page");
            // Ultra label and catalogue.
            Require(ThinkingLabels.Label("ultra") == "Ultra" && main.Model.Catalog.Revision == "sol-luna-ultra-20261010.1", "ThreadOS catalogue and Ultra label");
            // Order: persisted by id, applied to rail, tray panel, tooltip and Wizard.
            app.Desktop.RestoreDefaultOrder(); app.Desktop.TrayAgent = "";
            app.Desktop.MoveAgent("workbuddy", 0); await Settle(main);
            Require(main.Model.Shell.Agents[0].Id == "workbuddy" && app.Settings.AgentOrder.SequenceEqual(["workbuddy", "codex", "claude", "antigravity"]), "Move writes the complete visible order");
            using (var saved = JsonDocument.Parse(File.ReadAllText(app.Store.PathName)))
                Require(saved.RootElement.GetProperty("AgentOrder").EnumerateArray().Select(e => e.GetString()).SequenceEqual(["workbuddy", "codex", "claude", "antigravity"]), "Order is saved to the preference file at once");
            var reloaded = new SettingsStore(app.Store.PathName).Load(new());
            var restarted = new MainViewModel(true, reloaded);
            Require(restarted.Shell.Agents.Select(a => a.Id).SequenceEqual(["workbuddy", "codex", "claude", "antigravity"]), "Saved order is restored on next launch");
            Require(app.Desktop.TrayReading?.Id == "codex", "Arranged order: demo WorkBuddy has no reading, tray falls through to Codex");
            app.Desktop.TrayAgent = "claude"; Require(app.Desktop.TrayReading?.Id == "claude" && app.Desktop.TrayTooltip.Contains("Claude"), "Tray pin to Claude");
            app.Desktop.TrayAgent = "";
            app.Desktop.ToggleFlyout(); await Settle(main);
            var flyout = app.Windows.OfType<UsageFlyout>().Single();
            var flyoutIds = Walk(flyout).OfType<AllowanceRow>().Where(r => r.IsVisible).Select(r => r.Card!.Id).ToArray();
            Require(flyoutIds.SequenceEqual(main.Model.QuotaAgents.Select(a => a.Id)) && Walk(flyout).OfType<AllowanceRow>().All(r => r.ShowReset), "Tray panel follows the order and shows reset times");
            ProductVerification.Capture((FrameworkElement)flyout.Content, Path.Combine(directory, "tray-panel-ordered.png"));
            app.Desktop.ToggleFlyout();
            app.Desktop.Enabled = true; app.Desktop.SetWidgetVisible(true); await Settle(main);
            var wizard = app.Windows.OfType<DesktopWidget>().Single();
            Require(Walk(wizard).OfType<AllowanceRow>().Select(r => r.Card!.Id).SequenceEqual(main.Model.QuotaAgents.Select(a => a.Id)), "Desktop Wizard follows the order");
            ProductVerification.Capture((FrameworkElement)wizard.Content, Path.Combine(directory, "wizard-ordered.png"));
            var rail = Walk(main).OfType<AllowanceRow>().Where(r => r.Name == "ProviderRow").ToArray();
            Require(rail.All(r => !r.ShowReset), "Main rail does not show reset times");
            // Cost estimate switch: off by default and hidden while off.
            Require(!app.Settings.ShowCostEstimate && !main.Model.HasLocalCost, "Local Cost Estimate is off and hidden by default");
            main.Model.ShowCostEstimate = true; Require(main.Model.HasLocalCost, "Demo cost appears only after turning the switch on");
            main.Model.ShowCostEstimate = false; Require(!main.Model.HasLocalCost, "Turning the switch off hides it again");
            // Refresh preferences.
            Require(app.Providers.Intervals.SequenceEqual([5, 10, 15, 30, 60]) && app.Settings.Refresh.Automatic && app.Settings.Refresh.IntervalMinutes == 5, "Refresh offers 5/10/15/30/60 and defaults to automatic every 5 minutes");
            observations.Add(new { Stage = "order", Order = app.Settings.AgentOrder, Tooltip = app.Desktop.TrayTooltip });
            File.WriteAllLines(Path.Combine(directory, "PASS.txt"), checks);
        }
        catch (Exception e) { File.WriteAllText(Path.Combine(directory, "ERROR.txt"), e.ToString()); }
        finally
        {
            settings?.Close();
            if (app.Windows.OfType<UsageFlyout>().Any(w => w.IsVisible)) app.Desktop.ToggleFlyout();
            app.ApplyLanguage(language); app.Settings.AgentOrder = order; main.Model.Shell.Reorder(order); app.Settings.TrayAgent = pin;
            main.Model.Shell.Section = section; main.Persist();
            File.WriteAllText(Path.Combine(directory, "results.json"), JsonSerializer.Serialize(new { Checks = checks.Count, Observations = observations }, new JsonSerializerOptions { WriteIndented = true }));
        }
    }

    /// <summary>Normal mode: waits for the configured automatic refresh to fire the given number of times.</summary>
    internal static async Task RecordRefresh(App app, MainWindow main, string directory, int ticks)
    {
        Directory.CreateDirectory(directory); var rows = new List<object>();
        var started = DateTimeOffset.Now; var interval = TimeSpan.FromMinutes(app.Settings.Refresh.IntervalMinutes);
        try
        {
            if (app.Demo) throw new InvalidOperationException("Requires normal mode.");
            if (!app.Providers.ScheduleActive) throw new InvalidOperationException("Automatic refresh is off.");
            var seen = app.Providers.AutomaticRefreshCount; var deadline = started + interval * (ticks + 0.5);
            rows.Add(new { Stage = "start", At = started, IntervalMinutes = interval.TotalMinutes, Codex = Snapshot(main) });
            while (DateTimeOffset.Now < deadline && app.Providers.AutomaticRefreshCount < seen + ticks)
            {
                await Task.Delay(1000);
                if (app.Providers.AutomaticRefreshCount == seen) continue;
                seen = app.Providers.AutomaticRefreshCount; await Task.Delay(8000);
                rows.Add(new { Stage = "tick", Number = seen, FiredAt = app.Providers.LastAutomaticRefresh, SinceStartMinutes = (app.Providers.LastAutomaticRefresh!.Value - started).TotalMinutes, Codex = Snapshot(main) });
                ProductVerification.Capture((FrameworkElement)main.Content, Path.Combine(directory, $"after-tick-{seen}.png"));
            }
            File.WriteAllText(Path.Combine(directory, app.Providers.AutomaticRefreshCount >= ticks ? "PASS.txt" : "INCOMPLETE.txt"),
                $"Automatic refresh fired {app.Providers.AutomaticRefreshCount} time(s) at a {interval.TotalMinutes}-minute interval.");
        }
        catch (Exception e) { File.WriteAllText(Path.Combine(directory, "ERROR.txt"), e.Message); }
        finally { File.WriteAllText(Path.Combine(directory, "refresh-results.json"), JsonSerializer.Serialize(rows, new JsonSerializerOptions { WriteIndented = true })); }
    }
    private static object Snapshot(MainWindow main)
    {
        var card = main.Model.Shell.Agents.First(a => a.Id == "codex").Card;
        return new { card.Connection, card.Value, card.WindowMinutes, card.ObservedAt, card.IsStale, Displayed = card.HasDisplayableQuota };
    }
}
