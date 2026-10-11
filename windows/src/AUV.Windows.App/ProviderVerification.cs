using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;
using AUV.Windows.Core;

namespace AUV.Windows.App;

/// <summary>Opt-in native self-test. Writes admitted display fields and method names only.</summary>
internal static class ProviderVerification
{
    internal static async Task Run(App app, MainWindow main, string directory)
    {
        Directory.CreateDirectory(directory); var checks = new List<string>();
        var previous = main.Model.Shell.SelectedAgent.Id; var density = app.Desktop.Density; var visible = app.Settings.Desktop.WidgetVisible; var enabled = app.Providers.CodexEnabled;
        void Require(bool success, string name) { if (!success) throw new InvalidOperationException(name); checks.Add(name); }
        try
        {
            if (app.Demo) throw new InvalidOperationException("Live provider self-test requires normal mode.");
            app.Providers.CodexEnabled = true;
            var first = app.Providers.RefreshCodexAsync(); var second = app.Providers.RefreshCodexAsync();
            Require(ReferenceEquals(first, second), "Concurrent Codex refresh calls coalesce"); await first;
            var codex = main.Model.Shell.Agents.Single(a => a.Id == "codex"); main.Model.Shell.SelectedAgent = codex;
            Require(ReferenceEquals(main.Model.SelectedCard, codex.Card), "Main and provider list share the admitted Codex card");
            Require(!codex.IsDemo, "Live connection never uses a fixture");
            var connected = codex.Card.Connection == ConnectionState.Connected;
            File.WriteAllText(Path.Combine(directory, "live-result.json"), JsonSerializer.Serialize(new
            {
                LiveCodexRead = connected ? "PASS" : "UNAVAILABLE",
                codex.Card.Value, codex.Card.Kind, codex.Card.Window, codex.Card.Plan, codex.Card.Source, codex.Card.Freshness,
                LifetimeTokensAvailable = codex.Usage.AccountLifetime.HasValue, DailyBucketCount = codex.Usage.Days.Count,
                TokenSource = codex.TokenSource, Diagnostics = app.Providers.Diagnostics
            }, new JsonSerializerOptions { WriteIndented = true }));
            main.UpdateLayout(); ProductVerification.Capture((FrameworkElement)main.Content, Path.Combine(directory, "live-main.png"));
            app.Desktop.SetWidgetVisible(true);
            foreach (var mode in new[] { WizardDensity.Regular, WizardDensity.Minimalist })
            {
                app.Desktop.Density = mode; await main.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ContextIdle);
                var count = main.Model.QuotaAgents.Length;
                Require(app.Desktop.WidgetVisible == (count > 0), "Wizard visibility follows fetched quotas in " + mode);
                if (count > 0)
                {
                    var wizard = app.Windows.OfType<DesktopWidget>().Single();
                    Require(wizard.CardCount == count, "Wizard receives only available quotas in " + mode);
                    ProductVerification.Capture((FrameworkElement)wizard.Content, Path.Combine(directory, "live-wizard-" + mode + ".png"));
                }
            }
            app.Desktop.ToggleFlyout(); await Task.Delay(2200);
            var flyout = app.Windows.OfType<UsageFlyout>().Single();
            ProductVerification.Capture((FrameworkElement)flyout.Content, Path.Combine(directory, "live-quick-panel.png"));
            app.Desktop.ToggleFlyout();
            app.Providers.CodexEnabled = false;
            Require(main.Model.SelectedCard.Kind == AllowanceKind.Unavailable, "Disable withdraws the allowance immediately");
            Require(main.Model.SelectedCard.Connection == ConnectionState.Disconnected, "AUV disconnect is separate from Codex sign-out");
            app.Providers.CodexEnabled = true; await app.Providers.RefreshCodexAsync();
            Require(main.Model.SelectedCard.Connection == ConnectionState.Connected || !connected, "Re-enable rereads the local Codex account");
            File.WriteAllLines(Path.Combine(directory, "PASS.txt"), checks);
            File.WriteAllText(Path.Combine(directory, "desktop-result.json"), JsonSerializer.Serialize(app.Desktop.Evidence, new JsonSerializerOptions { WriteIndented = true }));
        }
        catch (Exception e) { File.WriteAllText(Path.Combine(directory, "ERROR.txt"), e is InvalidOperationException ? e.Message : e.GetType().Name); }
        finally
        {
            app.Providers.CodexEnabled = enabled; app.Desktop.Density = density; app.Desktop.SetWidgetVisible(visible);
            main.Model.Shell.SelectedAgent = main.Model.Shell.Agents.First(a => a.Id == previous);
        }
    }
}
