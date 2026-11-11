using System.Diagnostics;
using System.Text;
using System.Text.Json;
using AUV.Windows.App;
using AUV.Windows.Core;
using Microsoft.Win32;

namespace AUV.Windows.Tests;

/// <summary>Registration under a throwaway HKCU test key, and the real native host relaying between a stand-in browser and AUV's pipe.</summary>
public class ClaudeBrowserBridgeTests : IDisposable
{
    private readonly string temp = Path.Combine(Path.GetTempPath(), "auv-companion-" + Guid.NewGuid().ToString("N"));
    private readonly string registryBase = @"Software\AUV-Test-" + Guid.NewGuid().ToString("N");
    public ClaudeBrowserBridgeTests() => Directory.CreateDirectory(temp);
    public void Dispose()
    {
        Registry.CurrentUser.DeleteSubKeyTree(registryBase, false);
        try { Directory.Delete(temp, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    /// <summary>A stand-in AUV install: &lt;temp&gt;\&lt;name&gt;\BrowserCompanion with companion.json, host\AUV.BrowserHost.exe and extension\.</summary>
    private string Package(string build, string generation = ClaudeBrowserTests.Generation, string? name = null)
    {
        var root = Path.Combine(temp, name ?? "AUV_Win_" + build, "BrowserCompanion");
        Directory.CreateDirectory(Path.Combine(root, "host")); Directory.CreateDirectory(Path.Combine(root, "extension", "Shared"));
        File.WriteAllBytes(Path.Combine(root, "companion.json"), (ClaudeBrowserTests.Manifest with { CompanionBuild = build, RuntimeGenerationId = generation }).ToJson());
        File.WriteAllText(Path.Combine(root, "host", ClaudeBrowserSetup.HostExecutable), "stand-in " + build);
        File.WriteAllText(Path.Combine(root, "extension", "manifest.json"), "{\"build\":\"" + build + "\"}");
        File.WriteAllText(Path.Combine(root, "extension", "Shared", "x.js"), "//");
        return root;
    }
    private static string[] Tree(string root) => Directory.GetFiles(root, "*", SearchOption.AllDirectories).Select(f => Path.GetRelativePath(root, f)).Order(StringComparer.Ordinal).ToArray();
    private string? Value(string browserPath) { using var key = Registry.CurrentUser.OpenSubKey(registryBase + @"\" + browserPath); return key?.GetValue(null) as string; }
    private const string PipeName = "AUV.Windows.Preview.0123456789ABCDEF01234567.ClaudeBrowser";
    private ClaudeBrowserSetup Setup(string package) => new(package, PipeName, Registry.CurrentUser, registryBase);
    private string[] TopFolders() => Directory.GetDirectories(temp).Select(d => Path.GetFileName(d)!).Order(StringComparer.Ordinal).ToArray();

    // ---- 2026-11-11: the companion is used where it is, inside the AUV install folder ----

    [Fact] public void SetUpRegistersTheFolderInsideAuvAndCopiesNothing()
    {
        var package = Package("2026110801"); var before = Tree(package);
        var setup = Setup(package);
        Assert.Equal(CompanionInstallState.NotInstalled, setup.Status().State);
        var manifest = setup.Install(false);
        var status = setup.Status();
        Assert.Equal(CompanionInstallState.Installed, status.State); Assert.Equal(["chrome", "edge"], status.RegisteredBrowsers); Assert.Equal(manifest, status.Installed);
        Assert.Equal(Path.Combine(package, "extension"), setup.ExtensionFolder);
        Assert.Equal(Path.Combine(package, "host", ClaudeBrowserContract.NativeHostName + ".json"), setup.HostManifestPath);
        foreach (var (_, path) in ClaudeBrowserSetup.Browsers) Assert.Equal(setup.HostManifestPath, Value(path));
        // Only the two setup files were added, beside the host; nothing else changed and nothing went anywhere else.
        Assert.Equal(before.Concat([Path.Combine("host", "com.silkrd.auv.claude_browser.json"), Path.Combine("host", "host-config.json")]).Order(StringComparer.Ordinal), Tree(package));
        Assert.Equal(["AUV_Win_2026110801"], TopFolders());
        using var host = JsonDocument.Parse(File.ReadAllText(setup.HostManifestPath));
        Assert.Equal(["name", "description", "path", "type", "allowed_origins"], host.RootElement.EnumerateObject().Select(p => p.Name));
        Assert.Equal("AUV.BrowserHost.exe", host.RootElement.GetProperty("path").GetString());
        Assert.Equal([ClaudeBrowserTests.Manifest.ExtensionOrigin], host.RootElement.GetProperty("allowed_origins").EnumerateArray().Select(e => e.GetString()));
        var config = ClaudeHostConfig.Parse(File.ReadAllBytes(Path.Combine(package, "host", "host-config.json")));
        Assert.Equal(PipeName, config.PipeName); Assert.Equal(ClaudeBrowserTests.Generation, config.RuntimeGenerationId);
        var written = string.Join("\n", Directory.GetFiles(package, "*.json", SearchOption.AllDirectories).Select(File.ReadAllText));
        Assert.DoesNotContain("token", written, StringComparison.OrdinalIgnoreCase); Assert.DoesNotContain("cookie", written, StringComparison.OrdinalIgnoreCase);
    }

    [Fact] public void ForeignRegistrationIsReportedNotReplacedOrRemoved()
    {
        using (var key = Registry.CurrentUser.CreateSubKey(registryBase + @"\" + ClaudeBrowserSetup.Browsers[0].Path)) key.SetValue(null, @"C:\Other\host.json");
        var package = Package("2026110801"); var before = Tree(package);
        var setup = Setup(package);
        Assert.Equal(["chrome"], setup.Status().ForeignRegistrations);
        Assert.Equal(["chrome"], Assert.Throws<ForeignRegistrationException>(() => setup.Install(false)).Browsers);
        Assert.Equal(before, Tree(package));
        setup.Remove();
        Assert.Equal(@"C:\Other\host.json", Value(ClaudeBrowserSetup.Browsers[0].Path));
    }

    [Fact] public void RemoveDeletesOnlyAuvsKeysAndItsTwoSetupFiles()
    {
        var package = Package("2026110801"); var before = Tree(package);
        var setup = Setup(package);
        setup.Install(false); setup.Remove();
        foreach (var (_, path) in ClaudeBrowserSetup.Browsers) Assert.Null(Value(path));
        Assert.Equal(before, Tree(package)); // the package itself stays
    }

    [Fact] public void ANonWritableAuvFolderFailsWithAClearMessageAndNoFallback()
    {
        var package = Package("2026110801"); var hostFolder = Path.Combine(package, "host");
        var info = new DirectoryInfo(hostFolder);
        var security = info.GetAccessControl();
        var me = System.Security.Principal.WindowsIdentity.GetCurrent().User!;
        var deny = new System.Security.AccessControl.FileSystemAccessRule(me, System.Security.AccessControl.FileSystemRights.CreateFiles | System.Security.AccessControl.FileSystemRights.WriteData,
            System.Security.AccessControl.AccessControlType.Deny);
        security.AddAccessRule(deny); info.SetAccessControl(security);
        try
        {
            var setup = Setup(package);
            var error = Assert.Throws<CompanionFolderNotWritableException>(() => setup.Install(false));
            Assert.Equal(package, error.Folder);
            using (UiText.Override(UiLanguage.English)) Assert.Contains("Move the AUV folder", new CompanionFolderNotWritableException(package, error).Message);
            using (UiText.Override(UiLanguage.Chinese)) Assert.Contains("移到你有写入权限的位置", new CompanionFolderNotWritableException(package, error).Message);
            // Nothing was registered and nothing was written anywhere else.
            foreach (var (_, path) in ClaudeBrowserSetup.Browsers) Assert.Null(Value(path));
            Assert.Equal(["AUV_Win_2026110801"], TopFolders());
        }
        finally { security.RemoveAccessRule(deny); info.SetAccessControl(security); }
    }

    // ---- Upgrades: each AUV version has its own folder ----

    [Fact] public void StartupMovesTheRegistrationFromAnotherAuvInstallWithoutTouchingIt()
    {
        var previous = Package("2026110801", name: "AUV_Win_0.18.6");
        Setup(previous).Install(false);
        var previousTree = Tree(previous);
        var current = Package("2026112001", "7a0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e", name: "AUV_Win_0.18.7");
        var setup = Setup(current);
        var status = setup.Status();
        Assert.Equal(CompanionInstallState.NotInstalled, status.State); Assert.Empty(status.ForeignRegistrations); Assert.Equal(["chrome", "edge"], status.AuvRegistrationsElsewhere);
        Assert.True(setup.ReRegisterIfMoved());
        foreach (var (_, path) in ClaudeBrowserSetup.Browsers) Assert.Equal(setup.HostManifestPath, Value(path));
        Assert.Equal(CompanionInstallState.Installed, setup.Status().State);
        Assert.False(setup.ReRegisterIfMoved()); // nothing more to do
        Assert.Equal(previousTree, Tree(previous)); // the previous install folder is never touched
        Assert.Equal(["chrome", "edge"], Setup(previous).Status().AuvRegistrationsElsewhere);
    }

    [Fact] public void StartupMovesTheRegistrationFromThe0185Copy()
    {
        // AUV 0.18.5 copied the companion to %LOCALAPPDATA%\…\browser-companion\host\<build>.
        var legacy = Path.Combine(temp, "AUV.Windows.UI.Preview", "browser-companion");
        var legacyHost = Path.Combine(legacy, "host", "2026111101"); Directory.CreateDirectory(legacyHost);
        File.WriteAllText(Path.Combine(legacyHost, ClaudeBrowserSetup.HostExecutable), "0.18.5 host");
        File.WriteAllText(Path.Combine(legacyHost, "host-config.json"), $$"""{"schemaVersion":1,"pipeName":"{{PipeName}}","allowedOrigin":"{{ClaudeBrowserTests.Manifest.ExtensionOrigin}}","runtimeGenerationID":"{{ClaudeBrowserTests.Generation}}","hostVersion":"1.0.0","hostBuild":"2026111101"}""");
        var legacyManifest = Path.Combine(legacyHost, ClaudeBrowserContract.NativeHostName + ".json");
        File.WriteAllText(legacyManifest, $$"""{"name":"{{ClaudeBrowserContract.NativeHostName}}","description":"AUV","path":"AUV.BrowserHost.exe","type":"stdio","allowed_origins":[]}""");
        foreach (var (_, path) in ClaudeBrowserSetup.Browsers) using (var key = Registry.CurrentUser.CreateSubKey(registryBase + @"\" + path)) key.SetValue(null, legacyManifest);
        var setup = Setup(Package("2026112001"));
        Assert.Equal(["chrome", "edge"], setup.Status().AuvRegistrationsElsewhere);
        Assert.True(setup.ReRegisterIfMoved());
        foreach (var (_, path) in ClaudeBrowserSetup.Browsers) Assert.Equal(setup.HostManifestPath, Value(path));
        Assert.True(File.Exists(Path.Combine(legacyHost, ClaudeBrowserSetup.HostExecutable))); // not deleted without a yes
        Assert.True(ClaudeBrowserSetup.IsLegacyCopy(legacy));
    }

    [Fact] public void OnlyAWellFormedAuvHostCountsAsAuvsOwn()
    {
        var other = Path.Combine(temp, "lookalike"); Directory.CreateDirectory(other);
        var manifestPath = Path.Combine(other, ClaudeBrowserContract.NativeHostName + ".json");
        File.WriteAllText(manifestPath, $$"""{"name":"{{ClaudeBrowserContract.NativeHostName}}","path":"AUV.BrowserHost.exe","type":"stdio","allowed_origins":[]}""");
        Assert.False(ClaudeBrowserSetup.IsAuvCompanion(manifestPath)); // no host, no host-config.json
        File.WriteAllText(Path.Combine(other, ClaudeBrowserSetup.HostExecutable), "stand-in");
        Assert.False(ClaudeBrowserSetup.IsAuvCompanion(manifestPath));
        File.WriteAllText(Path.Combine(other, "host-config.json"), """{"schemaVersion":1,"pipeName":"Other"}""");
        Assert.False(ClaudeBrowserSetup.IsAuvCompanion(manifestPath)); // malformed config
        File.WriteAllText(Path.Combine(other, "host-config.json"), $$"""{"schemaVersion":1,"pipeName":"{{PipeName}}","allowedOrigin":"{{ClaudeBrowserTests.Manifest.ExtensionOrigin}}","runtimeGenerationID":"{{ClaudeBrowserTests.Generation}}","hostVersion":"1.0.0","hostBuild":"2026110801"}""");
        Assert.True(ClaudeBrowserSetup.IsAuvCompanion(manifestPath));
        File.WriteAllText(manifestPath, """{"name":"com.example.other","path":"AUV.BrowserHost.exe","type":"stdio","allowed_origins":[]}""");
        Assert.False(ClaudeBrowserSetup.IsAuvCompanion(manifestPath)); // another host name
        Assert.False(ClaudeBrowserSetup.IsAuvCompanion(@"relative\host.json")); Assert.False(ClaudeBrowserSetup.IsAuvCompanion(null));
        // A real third-party registration is still reported, and Install and the start-up move still stop.
        using (var key = Registry.CurrentUser.CreateSubKey(registryBase + @"\" + ClaudeBrowserSetup.Browsers[1].Path)) key.SetValue(null, manifestPath);
        var setup = Setup(Package("2026110801"));
        Assert.Equal(["edge"], setup.Status().ForeignRegistrations); Assert.Empty(setup.Status().AuvRegistrationsElsewhere);
        Assert.Throws<ForeignRegistrationException>(() => setup.Install(false));
        Assert.Throws<ForeignRegistrationException>(() => setup.ReRegisterIfMoved());
    }

    [Fact] public void TwoProfilesInOneFolderEachSeeOnlyTheirOwnSetUp()
    {
        var package = Package("2026110801");
        Setup(package).Install(false);
        var other = new ClaudeBrowserSetup(package, "AUV.Windows.Preview.FEDCBA9876543210FEDCBA98.ClaudeBrowser", Registry.CurrentUser, registryBase);
        Assert.Equal(CompanionInstallState.NotInstalled, other.Status().State); // host-config names the first profile's pipe
    }

    // ---- The 0.18.5 copy under %LOCALAPPDATA%: asked once, deleted only on yes ----

    private string LegacyCopy()
    {
        var legacy = Path.Combine(temp, "AUV.Windows.UI.Preview", "browser-companion");
        Directory.CreateDirectory(Path.Combine(legacy, "extension"));
        File.WriteAllBytes(Path.Combine(legacy, "companion.json"), ClaudeBrowserTests.Manifest.ToJson());
        return legacy;
    }

    [Fact] public void LegacyCopyIsOfferedOnceAndKeptOnNo()
    {
        var legacy = LegacyCopy(); var prefs = new ClaudeBrowserPreferences(); var asked = 0; var saved = 0;
        Assert.Equal(LegacyCleanupResult.Declined, LegacyCleanup.Offer(prefs, legacy, () => { asked++; return false; }, () => saved++));
        Assert.True(Directory.Exists(legacy)); Assert.True(prefs.LegacyCleanupAsked); Assert.Equal(1, saved);
        // Never asked again, whatever happens later.
        Assert.Equal(LegacyCleanupResult.AlreadyAsked, LegacyCleanup.Offer(prefs, legacy, () => { asked++; return true; }, () => saved++));
        Assert.Equal(1, asked); Assert.True(Directory.Exists(legacy));
    }

    [Fact] public void LegacyCopyIsDeletedOnlyOnYes()
    {
        var legacy = LegacyCopy(); var prefs = new ClaudeBrowserPreferences();
        Assert.Equal(LegacyCleanupResult.Deleted, LegacyCleanup.Offer(prefs, legacy, () => true, () => { }));
        Assert.False(Directory.Exists(legacy));
        Assert.True(Directory.Exists(Path.GetDirectoryName(legacy))); // the preferences folder itself stays
    }

    [Fact] public void NoQuestionWithoutAnAuvLegacyCopy()
    {
        var prefs = new ClaudeBrowserPreferences();
        var missing = Path.Combine(temp, "nothing-here");
        Assert.Equal(LegacyCleanupResult.NotNeeded, LegacyCleanup.Offer(prefs, missing, () => throw new InvalidOperationException("asked"), () => { }));
        // A folder of that name that AUV did not make is neither offered nor deleted.
        var strange = Path.Combine(temp, "x", "browser-companion"); Directory.CreateDirectory(strange); File.WriteAllText(Path.Combine(strange, "notes.txt"), "mine");
        Assert.Equal(LegacyCleanupResult.NotNeeded, LegacyCleanup.Offer(prefs, strange, () => throw new InvalidOperationException("asked"), () => { }));
        Assert.Equal(LegacyDeleteOutcome.NotACopy, ClaudeBrowserSetup.DeleteLegacyCopy(strange).Outcome); Assert.True(File.Exists(Path.Combine(strange, "notes.txt")));
        Assert.False(prefs.LegacyCleanupAsked);
    }

    /// <summary>The 0.18.5 layout: companion.json, README, extension\…, host\&lt;build&gt;\{AUV.BrowserHost.exe, host-config.json, manifest}.</summary>
    private string FullLegacyCopy()
    {
        var legacy = LegacyCopy();
        Directory.CreateDirectory(Path.Combine(legacy, "extension", "Shared"));
        File.WriteAllText(Path.Combine(legacy, "extension", "background.js"), "//"); File.WriteAllText(Path.Combine(legacy, "extension", "Shared", "x.js"), "//");
        File.WriteAllText(Path.Combine(legacy, "README.txt"), "0.18.5");
        var host = Path.Combine(legacy, "host", "202611111505"); Directory.CreateDirectory(host);
        File.WriteAllText(Path.Combine(host, ClaudeBrowserSetup.HostExecutable), "0.18.5 host");
        File.WriteAllText(Path.Combine(host, "host-config.json"), "{}"); File.WriteAllText(Path.Combine(host, ClaudeBrowserContract.NativeHostName + ".json"), "{}");
        File.SetAttributes(Path.Combine(legacy, "README.txt"), FileAttributes.ReadOnly);
        return legacy;
    }

    [Fact] public void ALockedHelperIsLeftSaidAndRemovedOnRetry()
    {
        var legacy = FullLegacyCopy(); var prefs = new ClaudeBrowserPreferences(); var saved = 0;
        var exe = Path.Combine(legacy, "host", "202611111505", ClaudeBrowserSetup.HostExecutable);
        using (new FileStream(exe, FileMode.Open, FileAccess.Read, FileShare.Read)) // like a running helper: no delete sharing
        {
            Assert.Equal(LegacyCleanupResult.Pending, LegacyCleanup.Offer(prefs, legacy, () => true, () => saved++));
            Assert.True(prefs.LegacyCleanupPending); Assert.True(saved >= 2); // asked, then pending, both saved
            Assert.Equal([Path.Combine("host", "202611111505", ClaudeBrowserSetup.HostExecutable)], Tree(legacy)); // everything else went
            Assert.True(ClaudeBrowserSetup.IsLegacyCopy(legacy)); // what is left is still recognisably AUV's copy
            Assert.Equal(LegacyCleanupResult.Pending, LegacyCleanup.Retry(prefs, legacy, () => { })); // still in use
        }
        Assert.Equal(LegacyCleanupResult.Deleted, LegacyCleanup.Retry(prefs, legacy, () => saved++));
        Assert.False(Directory.Exists(legacy)); Assert.False(prefs.LegacyCleanupPending);
        Assert.Equal(LegacyCleanupResult.NotNeeded, LegacyCleanup.Retry(prefs, legacy, () => throw new InvalidOperationException("nothing to save")));
    }

    [Fact] public void WithAnotherFileLockedTheMarkersStayUntilTheRestIsGone()
    {
        var legacy = FullLegacyCopy(); var prefs = new ClaudeBrowserPreferences();
        using (new FileStream(Path.Combine(legacy, "extension", "Shared", "x.js"), FileMode.Open, FileAccess.Read, FileShare.None))
        {
            var result = ClaudeBrowserSetup.DeleteLegacyCopy(legacy);
            Assert.Equal(new LegacyDeleteResult(LegacyDeleteOutcome.Partial, 1), result);
            Assert.Equal(["companion.json", Path.Combine("extension", "Shared", "x.js"), Path.Combine("host", "202611111505", ClaudeBrowserSetup.HostExecutable)], Tree(legacy));
            Assert.True(ClaudeBrowserSetup.IsLegacyCopy(legacy));
        }
        prefs.LegacyCleanupPending = true;
        Assert.Equal(LegacyCleanupResult.Deleted, LegacyCleanup.Retry(prefs, legacy, () => { }));
        Assert.False(Directory.Exists(legacy)); Assert.True(Directory.Exists(Path.GetDirectoryName(legacy)));
    }

    [Fact] public void APendingCleanUpNeverTouchesAFolderThatIsNoLongerAuvsCopy()
    {
        var prefs = new ClaudeBrowserPreferences { LegacyCleanupPending = true }; var saved = 0;
        var strange = Path.Combine(temp, "AUV.Windows.UI.Preview", "browser-companion"); Directory.CreateDirectory(strange);
        File.WriteAllText(Path.Combine(strange, "notes.txt"), "mine");
        Assert.Equal(LegacyCleanupResult.NotNeeded, LegacyCleanup.Retry(prefs, strange, () => saved++));
        Assert.True(File.Exists(Path.Combine(strange, "notes.txt"))); Assert.False(prefs.LegacyCleanupPending); Assert.Equal(1, saved);
        // Without a yes on record nothing is deleted, even from AUV's copy.
        var legacy = FullLegacyCopy();
        Assert.Equal(LegacyCleanupResult.NotNeeded, LegacyCleanup.Retry(new ClaudeBrowserPreferences(), legacy, () => { }));
        Assert.True(File.Exists(Path.Combine(legacy, "companion.json")));
    }

    [Fact] public void AFolderLinkInsideTheCopyIsNotFollowed()
    {
        var legacy = FullLegacyCopy();
        var outside = Path.Combine(temp, "outside"); Directory.CreateDirectory(outside); File.WriteAllText(Path.Combine(outside, "keep.txt"), "keep");
        var link = Path.Combine(legacy, "extension", "linked");
        try { Directory.CreateSymbolicLink(link, outside); } catch (IOException) { return; } catch (UnauthorizedAccessException) { return; } // needs Developer Mode
        Assert.Equal(LegacyDeleteOutcome.Partial, ClaudeBrowserSetup.DeleteLegacyCopy(legacy).Outcome);
        Assert.True(File.Exists(Path.Combine(outside, "keep.txt")));
    }

    [Fact] public void LegacyHostPathsAreRecognisedExactly()
    {
        var legacy = Path.Combine(temp, "AUV.Windows.UI.Preview", "browser-companion");
        Assert.True(LegacyCleanup.IsLegacyHost(Path.Combine(legacy, "host", "202611111505", "AUV.BrowserHost.exe"), legacy));
        Assert.True(LegacyCleanup.IsLegacyHost(Path.Combine(legacy, "HOST", "1", "auv.browserhost.EXE"), legacy));
        Assert.False(LegacyCleanup.IsLegacyHost(Path.Combine(legacy, "host", "AUV.BrowserHost.exe"), legacy));
        Assert.False(LegacyCleanup.IsLegacyHost(Path.Combine(legacy, "host", "1", "2", "AUV.BrowserHost.exe"), legacy));
        Assert.False(LegacyCleanup.IsLegacyHost(Path.Combine(temp, "AUV_Win_0.18.6", "BrowserCompanion", "host", "AUV.BrowserHost.exe"), legacy));
        Assert.False(LegacyCleanup.IsLegacyHost(Path.Combine(legacy, "..", "host", "1", "AUV.BrowserHost.exe"), legacy));
        Assert.False(LegacyCleanup.IsLegacyHost(null, legacy));
    }

    /// <summary>The live case: a browser keeps the old helper running, so its exe cannot be deleted until the helper exits.</summary>
    [Fact] public async Task ARunningOldHelperIsWaitedForAndThenRemoved()
    {
        var legacy = LegacyCopy(); var prefs = new ClaudeBrowserPreferences();
        // No AUV pipe listens on this name: the helper keeps retrying and runs until its stdin (the browser) closes.
        var (host, input, _) = StartHostIn(Path.Combine(legacy, "host", "202611111505"), "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser", ClaudeBrowserTests.Manifest.ExtensionOrigin);
        try
        {
            Assert.Equal(LegacyCleanupResult.Pending, LegacyCleanup.Offer(prefs, legacy, () => true, () => { }));
            Assert.True(prefs.LegacyCleanupPending);
            Assert.Equal([Path.Combine("host", "202611111505", ClaudeBrowserSetup.HostExecutable)], Tree(legacy).Where(f => f.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)));
            var exited = new TaskCompletionSource();
            using var watcher = new LegacyHostWatcher(legacy, () => exited.TrySetResult());
            Assert.Equal(1, watcher.Start());
            Assert.False(exited.Task.IsCompleted);
            input.Dispose(); // the browser closes
            await exited.Task.WaitAsync(TimeSpan.FromSeconds(15));
            var result = LegacyCleanup.Retry(prefs, legacy, () => { });
            for (var i = 0; i < 20 && result == LegacyCleanupResult.Pending; i++) { await Task.Delay(250); result = LegacyCleanup.Retry(prefs, legacy, () => { }); } // the image is released just after exit
            Assert.Equal(LegacyCleanupResult.Deleted, result);
            Assert.False(Directory.Exists(legacy)); Assert.False(prefs.LegacyCleanupPending);
        }
        finally { if (!host.HasExited) host.Kill(); host.Dispose(); }
    }

    [Fact] public void TheWatcherIgnoresHelpersOutsideTheOldCopy()
    {
        using var watcher = new LegacyHostWatcher(Path.Combine(temp, "AUV.Windows.UI.Preview", "browser-companion"), () => throw new InvalidOperationException("called"));
        Assert.Equal(0, watcher.Start());
    }

    // ---- Trust: only the host inside the running AUV's own BrowserCompanion\host ----

    [Fact] public void PipeTrustsOnlyThisAuvsOwnHost()
    {
        var package = Path.Combine(temp, "AUV_Win_0.18.6", "BrowserCompanion");
        Assert.True(ClaudeBrowserPipeServer.IsOwnHost(Path.Combine(package, "host", "AUV.BrowserHost.exe"), package));
        Assert.True(ClaudeBrowserPipeServer.IsOwnHost(Path.Combine(package, "host", "auv.browserhost.EXE"), package));
        Assert.False(ClaudeBrowserPipeServer.IsOwnHost(Path.Combine(temp, "AUV_Win_0.18.5", "BrowserCompanion", "host", "AUV.BrowserHost.exe"), package)); // another install
        Assert.False(ClaudeBrowserPipeServer.IsOwnHost(Path.Combine(temp, "AUV.Windows.UI.Preview", "browser-companion", "host", "2026111101", "AUV.BrowserHost.exe"), package)); // the 0.18.5 copy
        Assert.False(ClaudeBrowserPipeServer.IsOwnHost(Path.Combine(package, "host", "sub", "AUV.BrowserHost.exe"), package));
        Assert.False(ClaudeBrowserPipeServer.IsOwnHost(Path.Combine(package, "host", "Other.exe"), package));
        Assert.False(ClaudeBrowserPipeServer.IsOwnHost(Path.Combine(package, "host", "..", "..", "evil", "AUV.BrowserHost.exe"), package));
        Assert.False(ClaudeBrowserPipeServer.IsOwnHost(null, package));
    }

    [Fact] public async Task RefusedHostFromAnotherBuildCarriesOneReloadRequestPerTenMinutes()
    {
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        var newer = ClaudeBrowserTests.Manifest with { RuntimeGenerationId = "9b0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e" };
        var throttle = new CompanionReloadThrottle();
        using var server = new ClaudeBrowserPipeServer(pipeName, newer, _ => true, () => "auto", throttle);
        server.Start();
        async Task<CompanionMessage?> AfterWelcome()
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            using var client = new System.IO.Pipes.NamedPipeClientStream(".", pipeName, System.IO.Pipes.PipeDirection.InOut, System.IO.Pipes.PipeOptions.Asynchronous | System.IO.Pipes.PipeOptions.CurrentUserOnly);
            await client.ConnectAsync(5000, deadline.Token);
            await CompanionFraming.WriteAsync(client, CompanionMessageCodec.Encode(new HostHello("1.0.0", "2026110801", ClaudeBrowserTests.Manifest.ExtensionOrigin, "chrome", ClaudeBrowserTests.Generation)), 8192, deadline.Token);
            Assert.Equal(new HostWelcome(false, "generationMismatch"), CompanionMessageCodec.DecodeFromApp((await CompanionFraming.ReadAsync(client, 8192, deadline.Token))!));
            var next = await CompanionFraming.ReadAsync(client, 8192, deadline.Token);
            return next == null ? null : CompanionMessageCodec.DecodeFromApp(next);
        }
        var first = Assert.IsType<CompanionCommand>(await AfterWelcome());
        Assert.Equal(ClaudeBrowserContract.ReloadCommand, first.Command);
        Assert.Null(await AfterWelcome()); // within ten minutes: the refusal only
        Assert.Equal(1, throttle.Requests);
    }

    // ---- The real host process between a stand-in browser (stdio) and AUV's pipe ----

    private static string HostBuildOutput()
    {
        var testBin = AppContext.BaseDirectory; // …\tests\AUV.Windows.Tests\bin\<Configuration>\net10.0-windows\
        var configuration = new DirectoryInfo(testBin).Parent!.Name;
        var windows = Path.GetFullPath(Path.Combine(testBin, "..", "..", "..", "..", ".."));
        return Path.Combine(windows, "src", "AUV.Windows.BrowserHost", "bin", configuration, "net10.0", "win-x64");
    }

    private (Process Host, Stream Input, Stream Output) StartHost(string install, string pipeName, string origin) => StartHostIn(Path.Combine(install, "host"), pipeName, origin);
    private static (Process Host, Stream Input, Stream Output) StartHostIn(string folder, string pipeName, string origin)
    {
        Directory.CreateDirectory(folder);
        foreach (var file in Directory.GetFiles(HostBuildOutput())) File.Copy(file, Path.Combine(folder, Path.GetFileName(file)), true);
        File.WriteAllText(Path.Combine(folder, "host-config.json"), $$"""{"schemaVersion":1,"pipeName":"{{pipeName}}","allowedOrigin":"{{ClaudeBrowserTests.Manifest.ExtensionOrigin}}","runtimeGenerationID":"{{ClaudeBrowserTests.Generation}}","hostVersion":"1.0.0","hostBuild":"2026110801"}""");
        var start = new ProcessStartInfo(Path.Combine(folder, "AUV.BrowserHost.exe")) { RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
        start.ArgumentList.Add(origin); start.ArgumentList.Add("--parent-window=0");
        var host = Process.Start(start)!;
        return (host, host.StandardInput.BaseStream, host.StandardOutput.BaseStream);
    }

    private static async Task<CompanionMessage> NextForExtension(Stream output)
    {
        var frame = await CompanionFraming.ReadAsync(output, 4096, CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(15));
        return CompanionMessageCodec.DecodeForExtension(frame!);
    }

    [Fact] public async Task HostRelaysBothWaysAndOnlyForTheConfiguredExtension()
    {
        var install = Path.Combine(temp, "browser-companion");
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        using var server = new ClaudeBrowserPipeServer(pipeName, ClaudeBrowserTests.Manifest, ClaudeBrowserPipeServer.InstalledHostOnly(install), () => "auto");
        var received = new List<CompanionMessage>(); var connected = new TaskCompletionSource();
        server.Received += m => { lock (received) received.Add(m); };
        server.StateChanged += () => { if (server.State == CompanionLinkState.Connected) connected.TrySetResult(); };
        server.Start();
        var (host, input, output) = StartHost(install, pipeName, ClaudeBrowserTests.Manifest.ExtensionOrigin);
        try
        {
            Assert.Equal(new HostStatus(true), await NextForExtension(output));
            await connected.Task.WaitAsync(TimeSpan.FromSeconds(15));
            Assert.Equal(ClaudeBrowserTests.Manifest.ExtensionOrigin, server.Host!.ExtensionOrigin);
            // AUV → extension
            var wake = new CompanionCommand(ClaudeBrowserContract.WakeCommand, ClaudeBrowserContract.NewRequestId());
            Assert.True(await server.SendAsync(wake, CancellationToken.None));
            Assert.Equal(wake, await NextForExtension(output));
            // extension → AUV, including a message the allowlist refuses (it is dropped, the link stays up)
            await CompanionFraming.WriteAsync(input, Encoding.UTF8.GetBytes("{\"kind\":\"claudeBrowserTerminalPacket\",\"cookie\":\"x\"}"), 4096, CancellationToken.None);
            await CompanionFraming.WriteAsync(input, Encoding.UTF8.GetBytes(ClaudeBrowserTests.Ready(wake.RequestId)), 4096, CancellationToken.None);
            for (var i = 0; i < 100 && received.Count == 0; i++) await Task.Delay(100);
            var ready = Assert.IsType<CompanionEvent>(Assert.Single(received));
            Assert.Equal(wake.RequestId, ready.RequestId);
            // The extension's own ping is answered by the host.
            await CompanionFraming.WriteAsync(input, CompanionMessageCodec.Encode(new CompanionPing(ClaudeBrowserContract.NewRequestId())), 4096, CancellationToken.None);
            Assert.Equal(new HostStatus(true), await NextForExtension(output));
            // The browser closing the port ends the host, and AUV sees the browser go.
            input.Close();
            Assert.True(host.WaitForExit(15000)); Assert.Equal(0, host.ExitCode);
            for (var i = 0; i < 50 && server.State == CompanionLinkState.Connected; i++) await Task.Delay(100);
            Assert.Equal(CompanionLinkState.NoBrowser, server.State);
        }
        finally { if (!host.HasExited) host.Kill(); host.Dispose(); }
    }

    [Fact] public async Task HostRelaysAuvsReloadRequestAfterARefusal()
    {
        // After an update, the browser still runs the host and extension from before: AUV refuses the host and asks the
        // extension, through it, to reload itself. Nothing else crosses a refused connection.
        var install = Path.Combine(temp, "browser-companion");
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        var newer = ClaudeBrowserTests.Manifest with { RuntimeGenerationId = "9b0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e" };
        using var server = new ClaudeBrowserPipeServer(pipeName, newer, ClaudeBrowserPipeServer.InstalledHostOnly(install), () => "auto", new CompanionReloadThrottle());
        server.Start();
        var (host, input, output) = StartHost(install, pipeName, ClaudeBrowserTests.Manifest.ExtensionOrigin);
        try
        {
            var reload = Assert.IsType<CompanionCommand>(await NextForExtension(output));
            Assert.Equal(ClaudeBrowserContract.ReloadCommand, reload.Command); Assert.Null(reload.Placement); Assert.Null(reload.TargetRequestId);
            Assert.Equal(CompanionLinkState.Rejected, server.State);
            input.Close();
            Assert.True(host.WaitForExit(15000));
        }
        finally { if (!host.HasExited) host.Kill(); host.Dispose(); }
    }

    [Fact] public async Task HostRefusesAnotherExtension()
    {
        var install = Path.Combine(temp, "browser-companion");
        var (host, _, _) = StartHost(install, PipeName, "chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/");
        try { Assert.True(await Task.Run(() => host.WaitForExit(15000))); Assert.Equal(2, host.ExitCode); }
        finally { if (!host.HasExited) host.Kill(); host.Dispose(); }
    }

    [Fact] public async Task PipeRefusesAProcessThatIsNotTheInstalledHost()
    {
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        using var server = new ClaudeBrowserPipeServer(pipeName, ClaudeBrowserTests.Manifest, ClaudeBrowserPipeServer.InstalledHostOnly(Path.Combine(temp, "browser-companion")), () => "auto");
        server.Start();
        using var client = new System.IO.Pipes.NamedPipeClientStream(".", pipeName, System.IO.Pipes.PipeDirection.InOut, System.IO.Pipes.PipeOptions.Asynchronous | System.IO.Pipes.PipeOptions.CurrentUserOnly);
        await client.ConnectAsync(5000);
        // This test process is not AUV.BrowserHost.exe, so the server hangs up without a welcome.
        var hello = CompanionMessageCodec.Encode(new HostHello("1.0.0", "2026110801", ClaudeBrowserTests.Manifest.ExtensionOrigin, "chrome", ClaudeBrowserTests.Generation));
        try { await CompanionFraming.WriteAsync(client, hello, 8192, CancellationToken.None); } catch (IOException) { }
        Assert.Null(await CompanionFraming.ReadAsync(client, 8192, CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10)));
        Assert.Equal(CompanionLinkState.NoBrowser, server.State);
    }

    [Fact] public async Task WrongBuildIsRejectedAsNeedingAnUpdate()
    {
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        var newer = ClaudeBrowserTests.Manifest with { RuntimeGenerationId = "9b0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e" };
        using var server = new ClaudeBrowserPipeServer(pipeName, newer, _ => true, () => "auto");
        var changed = new TaskCompletionSource(); server.StateChanged += () => changed.TrySetResult();
        server.Start();
        using var client = new System.IO.Pipes.NamedPipeClientStream(".", pipeName, System.IO.Pipes.PipeDirection.InOut, System.IO.Pipes.PipeOptions.Asynchronous | System.IO.Pipes.PipeOptions.CurrentUserOnly);
        await client.ConnectAsync(5000);
        await CompanionFraming.WriteAsync(client, CompanionMessageCodec.Encode(new HostHello("1.0.0", "2026110801", ClaudeBrowserTests.Manifest.ExtensionOrigin, "edge", ClaudeBrowserTests.Generation)), 8192, CancellationToken.None);
        var welcome = Assert.IsType<HostWelcome>(CompanionMessageCodec.DecodeFromApp((await CompanionFraming.ReadAsync(client, 8192, CancellationToken.None))!));
        Assert.Equal(new HostWelcome(false, "generationMismatch"), welcome);
        await changed.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(CompanionLinkState.Rejected, server.State);
    }

    [Fact] public async Task ARestartedServerIsTheOnlyOneListening()
    {
        // Found live: after Update restarted the server, a host could land on the old, cancelled pipe instance and get no welcome.
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        var first = new ClaudeBrowserPipeServer(pipeName, ClaudeBrowserTests.Manifest, _ => true, () => "auto");
        // Restarted immediately, as Update does; a pipe write blocks until the server reads, so every step has a deadline.
        first.Start(); await Task.Delay(300); first.Dispose();
        using var second = new ClaudeBrowserPipeServer(pipeName, ClaudeBrowserTests.Manifest, _ => true, () => "auto");
        second.Start();
        for (var attempt = 0; attempt < 5; attempt++)
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            using var client = new System.IO.Pipes.NamedPipeClientStream(".", pipeName, System.IO.Pipes.PipeDirection.InOut, System.IO.Pipes.PipeOptions.Asynchronous | System.IO.Pipes.PipeOptions.CurrentUserOnly);
            await client.ConnectAsync(5000, deadline.Token);
            await CompanionFraming.WriteAsync(client, CompanionMessageCodec.Encode(new HostHello("1.0.0", "2026110801", ClaudeBrowserTests.Manifest.ExtensionOrigin, "chrome", ClaudeBrowserTests.Generation)), 8192, deadline.Token);
            var reply = await CompanionFraming.ReadAsync(client, 8192, deadline.Token);
            Assert.Equal(new HostWelcome(true, "accepted"), CompanionMessageCodec.DecodeFromApp(reply!));
            client.Dispose(); for (var i = 0; i < 50 && second.State == CompanionLinkState.Connected; i++) await Task.Delay(100);
        }
    }

    [Fact] public async Task AnOutdatedBrowserDoesNotHideAConnectedOne()
    {
        // Found live (issue A): after Update, Edge still ran the older extension and its host retried every 30 seconds;
        // each refusal set the whole link to "needs update" although Chrome was connected and current.
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        using var server = new ClaudeBrowserPipeServer(pipeName, ClaudeBrowserTests.Manifest, _ => true, () => "auto");
        server.Start();
        async Task<(System.IO.Pipes.NamedPipeClientStream Client, HostWelcome Welcome)> Hello(string product, string generation)
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            var client = new System.IO.Pipes.NamedPipeClientStream(".", pipeName, System.IO.Pipes.PipeDirection.InOut, System.IO.Pipes.PipeOptions.Asynchronous | System.IO.Pipes.PipeOptions.CurrentUserOnly);
            await client.ConnectAsync(5000, deadline.Token);
            await CompanionFraming.WriteAsync(client, CompanionMessageCodec.Encode(new HostHello("1.0.0", "2026110801", ClaudeBrowserTests.Manifest.ExtensionOrigin, product, generation)), 8192, deadline.Token);
            return (client, (HostWelcome)CompanionMessageCodec.DecodeFromApp((await CompanionFraming.ReadAsync(client, 8192, deadline.Token))!));
        }
        const string older = "9b0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e";
        var (chrome, chromeWelcome) = await Hello("chrome", ClaudeBrowserTests.Generation);
        using (chrome)
        {
            Assert.True(chromeWelcome.Accepted);
            for (var i = 0; i < 50 && server.State != CompanionLinkState.Connected; i++) await Task.Delay(50);
            var (edge, edgeWelcome) = await Hello("edge", older);
            using (edge) Assert.Equal(new HostWelcome(false, "generationMismatch"), edgeWelcome);
            await Task.Delay(300);
            Assert.Equal(CompanionLinkState.Connected, server.State);
            Assert.Equal("chrome", server.Host!.BrowserProduct);
            Assert.Equal("edge", server.RejectedHost!.BrowserProduct);
        }
        // With no browser connected, the refusal is what AUV reports, naming the browser to reload.
        for (var i = 0; i < 50 && server.State == CompanionLinkState.Connected; i++) await Task.Delay(100);
        var (again, _) = await Hello("edge", older);
        using (again)
        {
            for (var i = 0; i < 50 && server.State != CompanionLinkState.Rejected; i++) await Task.Delay(50);
            Assert.Equal(CompanionLinkState.Rejected, server.State);
            using var coordinator = new ClaudeCompanionCoordinator(server, ClaudeBrowserTests.Manifest);
            var result = await coordinator.SyncAsync(null, CancellationToken.None);
            Assert.Equal(ClaudeSyncOutcome.UpdateRequired, result.Outcome); Assert.Equal("edge", result.BrowserProduct);
            using var _ = UiText.Override(UiLanguage.English);
            var message = ClaudeBrowserPresentation.Message(result.Outcome, result.BrowserProduct);
            Assert.Contains("reload it once on Edge's extensions page", message);
        }
    }

    [Fact] public void PipeNameFollowsTheProfileKey()
    {
        var name = ClaudeBrowserPaths.PipeName(@"C:\Users\x\AppData\Local\AUV.Windows.UI.Preview\settings.v1.json");
        Assert.Matches("^AUV\\.Windows\\.Preview\\.[0-9A-F]{24}\\.ClaudeBrowser$", name);
        Assert.Equal(name, ClaudeBrowserPaths.PipeName(@"c:\users\x\appdata\local\AUV.Windows.UI.Preview\settings.v1.json"));
        Assert.Equal(@"C:\Users\x\AppData\Local\AUV.Windows.UI.Preview\browser-companion", ClaudeBrowserPaths.LegacyInstallRoot(@"C:\Users\x\AppData\Local\AUV.Windows.UI.Preview\settings.v1.json"));
    }
}
