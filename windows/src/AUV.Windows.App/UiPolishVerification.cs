using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Threading;

namespace AUV.Windows.App;

/// <summary>
/// Opt-in captures for the 0.18.6 UI polish (--ui-check-dir, with --demo --offline and an isolated --settings-path):
/// the Codex and Claude pages, the six settings panes, Claude settings and the tray panel, in dark and light, English
/// and Chinese. With --idle-seconds N it then leaves AUV idle on the Codex page and records AUV's own CPU time.
/// </summary>
internal static class UiPolishVerification
{
    private static async Task Settle(Window window)
    {
        await window.Dispatcher.InvokeAsync(() => window.UpdateLayout(), DispatcherPriority.ContextIdle);
        await Task.Delay(450); // longer than any transition, so captures show the end state
        await window.Dispatcher.InvokeAsync(() => window.UpdateLayout(), DispatcherPriority.ContextIdle);
    }

    internal static async Task Run(App app, MainWindow main, string directory, int idleSeconds)
    {
        Directory.CreateDirectory(directory);
        if (!app.Demo) { File.WriteAllText(Path.Combine(directory, "NOT_RUN.txt"), "Run with --demo --offline and an isolated --settings-path."); return; }
        var theme = app.Settings.Theme; var language = app.Settings.Language;
        var captures = new List<string>();
        void Shot(FrameworkElement visual, string name) { ProductVerification.Capture(visual, Path.Combine(directory, name + ".png")); captures.Add(name); }
        try
        {
            main.WindowState = WindowState.Normal; main.Width = 1056; main.Height = 800;
            foreach (var themeChoice in new[] { "Dark", "Light" })
                foreach (var lang in new[] { "en", "zh" })
                {
                    app.ApplyTheme(themeChoice); app.ApplyLanguage(lang); await Settle(main);
                    var tag = $"{themeChoice.ToLowerInvariant()}-{lang}";
                    main.Model.Shell.Section = "AUV";
                    foreach (var agent in new[] { "codex", "claude" })
                    {
                        main.Model.Shell.SelectedAgent = main.Model.Shell.Agents.First(a => a.Id == agent); await Settle(main);
                        Shot((FrameworkElement)main.Content, $"main-{agent}-{tag}");
                    }
                    var settings = new SettingsWindow(main, null) { Width = 760, Height = 620, Left = -12000, Top = 0 };
                    settings.Show(); await Settle(settings);
                    foreach (var pane in SettingsWindow.Panes) { settings.ShowPane(pane); await Settle(settings); Shot((FrameworkElement)settings.Content, $"settings-{pane}-{tag}"); }
                    settings.Close();
                    var claude = new SettingsWindow(main, "claude") { Height = 1000, Left = -12000, Top = 0 };
                    claude.Show(); await Settle(claude); Shot((FrameworkElement)claude.Content, $"settings-claude-{tag}"); claude.Close();
                    app.Desktop.ToggleFlyout(); await Settle(main);
                    if (app.Windows.OfType<UsageFlyout>().FirstOrDefault(w => w.IsVisible) is { } flyout) { await Settle(flyout); Shot((FrameworkElement)flyout.Content, $"tray-{tag}"); app.Desktop.ToggleFlyout(); }
                }
            // With motion off (Windows "Show animations" off, or --no-animations), every surface is at its end state at once.
            object? endState = null;
            if (!Motion.Enabled)
            {
                main.Model.Shell.SelectedAgent = main.Model.Shell.Agents.First(a => a.Id == "claude");
                var page = (FrameworkElement)main.FindName("DetailPage");
                var atOnce = page.Opacity == 1 && page.RenderTransform.Value.IsIdentity && !page.HasAnimatedProperties;
                var settings = new SettingsWindow(main, null) { Left = -12000, Top = 0 }; settings.Show(); settings.ShowPane("desktop");
                var pane = (FrameworkElement)settings.FindName("DesktopPane");
                var root = (FrameworkElement)settings.FindName("SettingsRoot");
                var settingsAtOnce = pane.Opacity == 1 && pane.RenderTransform.Value.IsIdentity && !pane.HasAnimatedProperties && root.Opacity == 1 && !root.HasAnimatedProperties;
                settings.Close();
                app.Desktop.ToggleFlyout();
                var flyout = app.Windows.OfType<UsageFlyout>().First(w => w.IsVisible); var card = (FrameworkElement)flyout.Content;
                var trayAtOnce = card.Opacity == 1 && card.RenderTransform.Value.IsIdentity && !card.HasAnimatedProperties;
                app.Desktop.ToggleFlyout();
                if (!(atOnce && settingsAtOnce && trayAtOnce)) throw new InvalidOperationException($"Motion off but a surface was not at its end state: page {atOnce}, settings {settingsAtOnce}, tray {trayAtOnce}");
                endState = new { Page = atOnce, Settings = settingsAtOnce, Tray = trayAtOnce };
            }
            object? idle = null;
            if (idleSeconds > 0)
            {
                app.ApplyTheme(theme); app.ApplyLanguage(language);
                main.Model.Shell.SelectedAgent = main.Model.Shell.Agents.First(a => a.Id == "codex"); await Settle(main);
                await Task.Delay(3000);
                using var self = Process.GetCurrentProcess();
                var cpu0 = self.TotalProcessorTime; var clock = Stopwatch.StartNew();
                await Task.Delay(TimeSpan.FromSeconds(idleSeconds));
                self.Refresh();
                var used = self.TotalProcessorTime - cpu0;
                idle = new { Seconds = clock.Elapsed.TotalSeconds, CpuMilliseconds = used.TotalMilliseconds,
                    CpuPercentOfOneCore = used.TotalMilliseconds / clock.Elapsed.TotalMilliseconds * 100, WorkingSetMB = self.WorkingSet64 / 1048576d,
                    PrivateMB = self.PrivateMemorySize64 / 1048576d, Animations = Motion.Enabled };
            }
            File.WriteAllText(Path.Combine(directory, "ui-results.json"), JsonSerializer.Serialize(new { Captures = captures, Animations = Motion.Enabled, EndStateWithoutMotion = endState, Idle = idle }, new JsonSerializerOptions { WriteIndented = true }));
            File.WriteAllText(Path.Combine(directory, "PASS.txt"), $"{captures.Count} captures.");
        }
        catch (Exception e) when (e is InvalidOperationException or IOException or UnauthorizedAccessException)
        { File.WriteAllText(Path.Combine(directory, "ERROR.txt"), e.ToString()); }
        finally { app.ApplyTheme(theme); app.ApplyLanguage(language); }
    }
}
