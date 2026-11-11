using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using AUV.Windows.Core;
using Microsoft.Win32;

namespace AUV.Windows.App;

/// <summary>
/// Opt-in check of the 0.18.6 Claude flow (--claude-check-dir, with --offline and an isolated --settings-path). It walks
/// Connect → checklist → connected with a synthetic companion package and a throwaway HKCU key (Software\AUV-Test-…),
/// and captures the Claude page and Claude settings in English and Chinese at each stage. No browser is opened or
/// registered, and the synthetic reading is a fixture: nothing is read from claude.ai.
/// </summary>
internal static class ClaudeVerification
{
    private static async Task Settle(Window window) { await window.Dispatcher.InvokeAsync(() => window.UpdateLayout(), DispatcherPriority.ContextIdle); await Task.Delay(150); }

    internal static async Task Capture(App app, MainWindow main, string directory, string prefix, bool advanced = false)
    {
        foreach (var language in new[] { "en", "zh" })
        {
            app.ApplyLanguage(language); await Settle(main); await Task.Delay(100);
            main.Model.Shell.Section = "AUV";
            main.Model.Shell.SelectedAgent = main.Model.Shell.Agents.First(a => a.Id == "claude"); await Settle(main);
            ProductVerification.Capture((FrameworkElement)main.Content, Path.Combine(directory, $"{prefix}-claude-page-{language}.png"));
            var settings = new SettingsWindow(main, "claude") { Height = 1250, Left = -12000, Top = 0 };
            settings.Show(); await Settle(settings);
            ProductVerification.Capture((FrameworkElement)settings.Content, Path.Combine(directory, $"{prefix}-claude-settings-{language}.png"));
            if (advanced && settings.FindName("ClaudeAdvanced") is Expander expander)
            {
                expander.IsExpanded = true; await Settle(settings);
                ProductVerification.Capture((FrameworkElement)settings.Content, Path.Combine(directory, $"{prefix}-claude-settings-advanced-{language}.png"));
            }
            settings.Close();
        }
    }

    /// <summary>A stand-in companion package: the real one is staged only into published builds.</summary>
    private static string StagePackage(string root)
    {
        Directory.CreateDirectory(Path.Combine(root, "host")); Directory.CreateDirectory(Path.Combine(root, "extension"));
        var manifest = new ClaudeCompanionManifest("abcdefghijklmnopabcdefghijklmnop", Guid.NewGuid().ToString("D"), "1.0.0", "2026111101");
        File.WriteAllBytes(Path.Combine(root, "companion.json"), manifest.ToJson());
        File.WriteAllText(Path.Combine(root, "host", ClaudeBrowserSetup.HostExecutable), "verification stand-in; never run");
        File.WriteAllText(Path.Combine(root, "extension", "manifest.json"), "{}");
        return root;
    }

    internal static async Task Run(App app, MainWindow main, string directory, string prefix)
    {
        Directory.CreateDirectory(directory);
        if (app.Demo) { File.WriteAllText(Path.Combine(directory, "NOT_RUN.txt"), "Run without --demo, with --offline and an isolated --settings-path."); return; }
        var language = app.Settings.Language; var providers = app.Providers;
        var checks = new List<string>();
        void Require(bool valid, string check) { if (!valid) throw new InvalidOperationException(check); checks.Add(check); }
        // A language change reads Codex again; this check is about Claude only, so the isolated profile turns Codex off
        // and no real account figure appears in the captures.
        providers.CodexEnabled = false;
        if (prefix == "before")
        {
            try { await Capture(app, main, directory, prefix); File.WriteAllText(Path.Combine(directory, "PASS.txt"), "Captured."); }
            finally { app.ApplyLanguage(language); }
            return;
        }
        var stage = Path.Combine(Path.GetDirectoryName(app.Store.PathName)!, "claude-check-package-" + Guid.NewGuid().ToString("N")[..8]);
        var registryBase = @"Software\AUV-Test-" + Guid.NewGuid().ToString("N");
        try
        {
            Require(!ClaudeBrowserSetup.IsLegacyCopy(ClaudeBrowserPaths.LegacyInstallRoot(app.Store.PathName)), "The isolated profile has no 0.18.5 companion copy");
            providers.ClaudePackageRootOverride = StagePackage(stage); providers.ClaudeRegistryBaseOverride = registryBase;
            providers.ClaudeChanged();
            Require(providers.ClaudeShowConnect && providers.ClaudeConnectAvailable && !providers.ClaudeShowChecklist, "Off: the Claude page shows the Connect card");
            await Capture(app, main, directory, "after-1-connect");

            // Connect, after its one confirmation (the dialog itself is not shown here).
            var manifest = providers.InstallAndEnableClaude(false);
            var status = providers.ClaudeSetup.Status();
            Require(status.State == CompanionInstallState.Installed && status.RegisteredBrowsers.SequenceEqual(["chrome", "edge"]) && File.Exists(Path.Combine(stage, "host", "host-config.json")) && !Directory.Exists(ClaudeBrowserPaths.LegacyInstallRoot(app.Store.PathName)), "Connect registers the companion inside the (staged) AUV folder for Chrome and Edge, copying nothing");
            Require(providers.ClaudeBrowserEnabled && app.Settings.ClaudeBrowser.InstalledBuild == manifest.CompanionBuild, "Connect turns Claude sync on");
            Require(!providers.ClaudeShowConnect && providers.ClaudeShowChecklist && providers.ClaudeStep1Done && !providers.ClaudeStep2Done && !providers.ClaudeStep3Done, "Checklist: step 1 ticked");
            using (var key = Registry.CurrentUser.OpenSubKey(registryBase + @"\" + ClaudeBrowserSetup.Browsers[0].Path))
                Require(key?.GetValue(null) as string == providers.ClaudeSetup.HostManifestPath, "Registration went to the throwaway key only");

            // Step 2: a browser's companion passed the handshake. Then a sync that needs sign-in shows its action.
            providers.MarkClaudeLoaded("chrome");
            providers.ApplyClaude(new ClaudeSyncResult(ClaudeSyncOutcome.SignInRequired, BrowserProduct: "chrome"));
            Require(providers.ClaudeStep2Done && !providers.ClaudeStep3Done && providers.HasClaudeFailure && providers.ClaudeRemedy == ClaudeRemedy.OpenClaude, "Checklist: step 2 ticked; sign-in failure offers Open claude.ai");
            await Capture(app, main, directory, "after-2-checklist");

            // Step 3: the first exact reading (a fixture: 15% left in the 5-hour window, 60% left this week).
            providers.ApplyClaude(new ClaudeSyncResult(ClaudeSyncOutcome.Success, new CompanionObservation(new(85, DateTimeOffset.UtcNow.AddHours(2)), new(40, DateTimeOffset.UtcNow.AddDays(3)), DateTimeOffset.UtcNow), BrowserProduct: "chrome"));
            var card = main.Model.Shell.Agents.First(a => a.Id == "claude").Card;
            Require(providers.ClaudeShowSummary && !providers.ClaudeShowChecklist && !providers.HasClaudeFailure && app.Settings.ClaudeBrowser.ExactReadingSeen, "All three ticked: one summary line");
            Require(card.Severity == QuotaSeverity.Low && LowRemainingPolicy.Resolve("claude", null, 60, null, AllowanceKind.Percentage) == QuotaSeverity.Normal, "Claude bars use Codex's green/red rule");
            await Capture(app, main, directory, "after-3-connected", advanced: true);
            File.WriteAllText(Path.Combine(directory, "PASS.txt"), $"{checks.Count} Claude flow checks passed.\n" + string.Join("\n", checks));
        }
        catch (Exception e) when (e is InvalidOperationException or IOException or UnauthorizedAccessException or System.Security.SecurityException)
        { File.WriteAllText(Path.Combine(directory, "ERROR.txt"), $"{checks.Count} passed before: " + e.GetType().Name + ": " + e.Message); }
        finally
        {
            try
            {
                providers.ClaudeBrowserEnabled = false;
                if (providers.ClaudeRegistryBaseOverride == registryBase) providers.ClaudeSetup.Remove();
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            Registry.CurrentUser.DeleteSubKeyTree(registryBase, false);
            try { if (Directory.Exists(stage)) Directory.Delete(stage, true); } catch (IOException) { }
            providers.ClaudePackageRootOverride = null; providers.ClaudeRegistryBaseOverride = null;
            app.ApplyLanguage(language);
        }
    }
}
