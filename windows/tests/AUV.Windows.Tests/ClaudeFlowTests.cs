using System.Text;
using AUV.Windows.Core;

namespace AUV.Windows.Tests;

/// <summary>0.18.6 step 1: the reload request, the checklist, failure actions and the new settings. No account data is used.</summary>
public class ClaudeFlowTests
{
    private const string Request = "11111111-2222-4333-8444-555555555555";
    private static readonly CompanionTimings Fast = new(TimeSpan.FromMilliseconds(300), TimeSpan.FromMilliseconds(300), TimeSpan.FromMilliseconds(400), TimeSpan.FromMinutes(5), TimeSpan.FromSeconds(30));

    // ---- umaClaudeReloadCompanion: allowlist ----

    [Fact] public void ReloadCommandIsAllowlistedWithNoExtraFields()
    {
        var reload = new CompanionCommand(ClaudeBrowserContract.ReloadCommand, Request);
        var bytes = CompanionMessageCodec.Encode(reload);
        Assert.Equal(reload, CompanionMessageCodec.DecodeForExtension(bytes));
        Assert.Equal(reload, CompanionMessageCodec.DecodeFromApp(bytes));
        Assert.Equal("""{"kind":"auvCompanionCommand","schemaVersion":1,"command":"umaClaudeReloadCompanion","requestID":"11111111-2222-4333-8444-555555555555"}""", Encoding.UTF8.GetString(bytes));
        // Nothing may ride along: no placement, no target, no URL.
        Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.Encode(new CompanionCommand(ClaudeBrowserContract.ReloadCommand, Request, Placement: "backgroundTab")));
        Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.Encode(new CompanionCommand(ClaudeBrowserContract.ReloadCommand, Request, "66666666-7777-4888-9999-aaaaaaaaaaaa")));
        Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.DecodeFromApp(Encoding.UTF8.GetBytes(
            """{"kind":"auvCompanionCommand","schemaVersion":1,"command":"umaClaudeReloadCompanion","requestID":"11111111-2222-4333-8444-555555555555","url":"https://example.com"}""")));
        // Only AUV sends it: the extension cannot send a command to AUV.
        Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.DecodeFromExtension(bytes));
    }

    // ---- Reload spacing ----

    [Fact] public void ThrottleSpacesEachBrowserTenMinutesApart()
    {
        var clock = DateTimeOffset.Parse("2026-11-11T10:00:00Z");
        var throttle = new CompanionReloadThrottle(now: () => clock);
        Assert.Equal(TimeSpan.FromMinutes(10), CompanionReloadThrottle.DefaultSpacing);
        Assert.True(throttle.TryRequest("chrome"));
        Assert.False(throttle.TryRequest("chrome"));
        Assert.True(throttle.TryRequest("edge")); // browsers are spaced independently
        clock = clock.AddMinutes(9).AddSeconds(59); Assert.False(throttle.TryRequest("chrome"));
        clock = clock.AddSeconds(1); Assert.True(throttle.TryRequest("chrome"));
        Assert.Equal(3, throttle.Requests);
    }

    [Fact] public async Task ConnectedExtensionFromAnotherBuildIsAskedToReloadAtMostOncePerTenMinutes()
    {
        var clock = DateTimeOffset.UtcNow;
        var link = new ClaudeBrowserTests.FakeLink { Respond = c => c.Command == ClaudeBrowserContract.WakeCommand ? [ClaudeBrowserTests.Ready(c.RequestId, build: "2026010101")] : [] };
        using var coordinator = new ClaudeCompanionCoordinator(link, ClaudeBrowserTests.Manifest, Fast, () => clock);
        string? qualified = null; coordinator.Qualified += p => qualified = p;
        var first = await coordinator.SyncAsync(null, CancellationToken.None);
        Assert.Equal(ClaudeSyncOutcome.UpdateRequired, first.Outcome); Assert.True(first.ReloadRequested); Assert.Equal("chrome", first.BrowserProduct);
        var second = await coordinator.SyncAsync(null, CancellationToken.None);
        Assert.Equal(ClaudeSyncOutcome.UpdateRequired, second.Outcome); Assert.False(second.ReloadRequested);
        Assert.Single(link.Sent, s => s.Command == ClaudeBrowserContract.ReloadCommand);
        clock = clock.AddMinutes(10);
        Assert.True((await coordinator.SyncAsync(null, CancellationToken.None)).ReloadRequested);
        Assert.Equal(2, link.Sent.Count(s => s.Command == ClaudeBrowserContract.ReloadCommand));
        // Never qualified and never read.
        Assert.Null(qualified); Assert.DoesNotContain(link.Sent, s => s.Command == ClaudeBrowserContract.RefreshCommand);
    }

    [Fact] public async Task TheSpacingIsSharedWithThePipe()
    {
        var shared = new CompanionReloadThrottle();
        Assert.True(shared.TryRequest("chrome")); // the pipe already asked Chrome's extension
        var link = new ClaudeBrowserTests.FakeLink { Respond = c => c.Command == ClaudeBrowserContract.WakeCommand ? [ClaudeBrowserTests.Ready(c.RequestId, build: "2026010101")] : [] };
        using var coordinator = new ClaudeCompanionCoordinator(link, ClaudeBrowserTests.Manifest, Fast, reloads: shared);
        Assert.False((await coordinator.SyncAsync(null, CancellationToken.None)).ReloadRequested);
        Assert.DoesNotContain(link.Sent, s => s.Command == ClaudeBrowserContract.ReloadCommand);
    }

    [Fact] public async Task CurrentExtensionIsQualifiedAndNeverAskedToReload()
    {
        var link = new ClaudeBrowserTests.FakeLink { Respond = c => ClaudeBrowserTests.Healthy(c) };
        using var coordinator = new ClaudeCompanionCoordinator(link, ClaudeBrowserTests.Manifest, Fast);
        string? qualified = null; coordinator.Qualified += p => qualified = p;
        Assert.Equal(ClaudeSyncOutcome.Success, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
        Assert.Equal("chrome", qualified);
        Assert.DoesNotContain(link.Sent, s => s.Command == ClaudeBrowserContract.ReloadCommand);
    }

    [Fact] public void UpdateMessageSaysTheFirstUpgradeNeedsOneManualReload()
    {
        using (UiText.Override(UiLanguage.English))
        {
            var message = ClaudeBrowserPresentation.Message(ClaudeSyncOutcome.UpdateRequired, "edge");
            Assert.Contains("AUV asks it to reload itself", message); Assert.Contains("0.18.5", message);
        }
        using (UiText.Override(UiLanguage.Chinese))
            Assert.Contains("0.18.5", ClaudeBrowserPresentation.Message(ClaudeSyncOutcome.UpdateRequired, "edge"));
    }

    // ---- Checklist ----

    [Fact] public void ChecklistTicksEachStepFromWhatAuvHasSeen()
    {
        var empty = ClaudeChecklist.Derive(false, [], false, null, null);
        Assert.False(empty.Registered); Assert.False(empty.ExtensionLoaded); Assert.False(empty.SignedIn); Assert.False(empty.Complete);
        var registered = ClaudeChecklist.Derive(true, [], false, null, null);
        Assert.True(registered.Registered); Assert.False(registered.Complete);
        var loaded = ClaudeChecklist.Derive(true, ["edge", "firefox", "edge"], false, null, null);
        Assert.True(loaded.ExtensionLoaded); Assert.Equal(["edge"], loaded.LoadedBrowsers); Assert.Equal("edge", loaded.Browser); Assert.False(loaded.Complete);
        var done = ClaudeChecklist.Derive(true, ["chrome", "edge"], true, "edge", null);
        Assert.True(done.Complete); Assert.Equal("edge", done.Browser); Assert.True(done.LoadedIn("chrome"));
        // A missing registration unticks step 1 and the summary goes away, whatever was seen before.
        Assert.False(ClaudeChecklist.Derive(false, ["chrome"], true, "chrome", null).Complete);
    }

    [Fact] public void CompletedChecklistCollapsesToOneLine()
    {
        var at = new DateTimeOffset(2026, 11, 11, 14, 5, 0, TimeZoneInfo.Local.GetUtcOffset(new DateTime(2026, 11, 11, 14, 5, 0)));
        var done = ClaudeChecklist.Derive(true, ["chrome"], true, null, at);
        using (UiText.Override(UiLanguage.English)) Assert.Equal("Connected · Chrome · last reading 14:05", done.Summary);
        using (UiText.Override(UiLanguage.Chinese)) Assert.Equal("已连接 · Chrome · 上次读数 14:05", done.Summary);
        using (UiText.Override(UiLanguage.English)) Assert.Equal("Connected · Edge", ClaudeChecklist.Derive(true, ["chrome"], true, "edge", null).Summary);
    }

    // ---- Failure reasons and their buttons ----

    [Theory]
    [InlineData(ClaudeSyncOutcome.SignInRequired, ClaudeRemedy.OpenClaude)]
    [InlineData(ClaudeSyncOutcome.PermissionRequired, ClaudeRemedy.OpenExtensions)]
    [InlineData(ClaudeSyncOutcome.UpdateRequired, ClaudeRemedy.OpenExtensions)]
    [InlineData(ClaudeSyncOutcome.CompanionSilent, ClaudeRemedy.OpenExtensions)]
    [InlineData(ClaudeSyncOutcome.NotConnected, ClaudeRemedy.OpenBrowser)]
    [InlineData(ClaudeSyncOutcome.LayoutUnsupported, ClaudeRemedy.None)]
    [InlineData(ClaudeSyncOutcome.PageUnreadable, ClaudeRemedy.None)]
    [InlineData(ClaudeSyncOutcome.PageTimedOut, ClaudeRemedy.None)]
    [InlineData(ClaudeSyncOutcome.Success, ClaudeRemedy.None)]
    public void EachFailureGetsItsMatchingAction(ClaudeSyncOutcome outcome, ClaudeRemedy expected)
    {
        Assert.Equal(expected, ClaudeBrowserPresentation.Remedy(outcome));
        using var _ = UiText.Override(UiLanguage.English);
        var label = ClaudeBrowserPresentation.RemedyLabel(expected, "edge");
        Assert.Equal(expected switch
        {
            ClaudeRemedy.OpenClaude => "Open claude.ai", ClaudeRemedy.OpenExtensions => "Open Edge extensions page", ClaudeRemedy.OpenBrowser => "Open Edge", _ => ""
        }, label);
    }

    // ---- Settings ----

    [Fact] public void NewChecklistSettingsHaveDefaultsAndAreNormalized()
    {
        var directory = Path.Combine(Path.GetTempPath(), "auv-claude-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(directory);
        try
        {
            var path = Path.Combine(directory, "settings.v1.json");
            // A 0.18.5 file: ClaudeBrowser without the 0.18.6 fields.
            File.WriteAllText(path, """{"Version":1,"Theme":"Dark","ClaudeBrowser":{"Enabled":true,"Browser":"edge","Placement":"auto","AskToOpenBrowser":false,"InstalledBuild":"2026111101"}}""");
            var store = new SettingsStore(path); var settings = store.Load(new ModelCatalog());
            Assert.Null(store.LastError);
            Assert.True(settings.ClaudeBrowser.Enabled); Assert.Equal("edge", settings.ClaudeBrowser.Browser); Assert.Equal("2026111101", settings.ClaudeBrowser.InstalledBuild);
            Assert.Empty(settings.ClaudeBrowser.LoadedBrowsers); Assert.False(settings.ClaudeBrowser.ExactReadingSeen);
            Assert.Null(settings.ClaudeBrowser.LoadedFolder); Assert.False(settings.ClaudeBrowser.LegacyCleanupAsked); Assert.False(settings.ClaudeBrowser.LegacyCleanupPending);
            settings.ClaudeBrowser.LoadedBrowsers = ["edge", "firefox", "chrome", "edge"]; settings.ClaudeBrowser.ExactReadingSeen = true;
            Assert.True(store.Save(settings));
            var again = store.Load(new ModelCatalog());
            Assert.Equal(["chrome", "edge"], again.ClaudeBrowser.LoadedBrowsers); Assert.True(again.ClaudeBrowser.ExactReadingSeen);
            Assert.False(again.ClaudeBrowser.AskToOpenBrowser);
        }
        finally { Directory.Delete(directory, true); }
    }

    // ---- 2026-11-11: each AUV install has its own extension folder ----

    [Fact] public void Step2StartsAgainForANewAuvFolder()
    {
        const string first = @"D:\Apps\AUV_Win_0.18.6\BrowserCompanion\extension", next = @"D:\Apps\AUV_Win_0.18.7\BrowserCompanion\extension";
        var prefs = new ClaudeBrowserPreferences();
        Assert.False(prefs.LoadedElsewhere(first)); Assert.Empty(prefs.LoadedIn(first));
        Assert.True(prefs.MarkLoaded("chrome", first)); Assert.False(prefs.MarkLoaded("chrome", first));
        Assert.Equal(["chrome"], prefs.LoadedIn(first)); Assert.Equal(first, prefs.LoadedFolder);
        Assert.Equal(["chrome"], prefs.LoadedIn(first.ToLowerInvariant())); // the same folder, whatever the case
        // The next AUV is a new folder: step 2 is not ticked there until its own build answers.
        Assert.True(prefs.LoadedElsewhere(next)); Assert.Empty(prefs.LoadedIn(next));
        Assert.False(prefs.MarkLoaded("firefox", next));
        Assert.True(prefs.MarkLoaded("edge", next));
        Assert.Equal(["edge"], prefs.LoadedIn(next)); Assert.Equal(next, prefs.LoadedFolder); Assert.True(prefs.LoadedElsewhere(first));
        // Ticks from before 0.18.6 named no folder: they count as another folder.
        Assert.True(new ClaudeBrowserPreferences { LoadedBrowsers = ["chrome"] }.LoadedElsewhere(first));
    }

    [Fact] public void MovedFolderMessageSaysReloadingDoesNotHelp()
    {
        using (UiText.Override(UiLanguage.English))
        {
            var moved = ClaudeBrowserPresentation.Message(ClaudeSyncOutcome.UpdateRequired, "chrome", movedFolder: true);
            Assert.Contains("previous AUV folder", moved); Assert.Contains("Reloading the old one does not help", moved); Assert.Contains("Load in Chrome", moved);
            Assert.DoesNotContain("previous AUV folder", ClaudeBrowserPresentation.Message(ClaudeSyncOutcome.UpdateRequired, "chrome"));
            Assert.Equal(moved, ClaudeBrowserPresentation.Failure(ClaudeSyncOutcome.UpdateRequired, "chrome", true).Card.Source);
        }
        using (UiText.Override(UiLanguage.Chinese))
            Assert.Contains("“重新加载”没有用", ClaudeBrowserPresentation.Message(ClaudeSyncOutcome.UpdateRequired, "edge", movedFolder: true));
    }

    // ---- host-config.json ----

    [Fact] public void HostConfigIsReadStrictly()
    {
        const string good = """{"schemaVersion":1,"pipeName":"AUV.Windows.Preview.0123456789ABCDEF01234567.ClaudeBrowser","allowedOrigin":"chrome-extension://abcdefghijklmnopabcdefghijklmnop/","runtimeGenerationID":"5f0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e","hostVersion":"1.0.0","hostBuild":"2026110801"}""";
        var config = ClaudeHostConfig.Parse(Encoding.UTF8.GetBytes(good));
        Assert.Equal("chrome-extension://abcdefghijklmnopabcdefghijklmnop/", config.AllowedOrigin);
        foreach (var bad in new[]
        {
            good.Replace("\"hostBuild\":\"2026110801\"}", "\"hostBuild\":\"2026110801\",\"token\":\"x\"}"),
            good.Replace("\"schemaVersion\":1", "\"schemaVersion\":2"),
            good.Replace("AUV.Windows.Preview.0123456789ABCDEF01234567.ClaudeBrowser", "Other.Pipe"),
            good.Replace("abcdefghijklmnopabcdefghijklmnop/", "abcdefghijklmnopabcdefghijklmnopx"),
            good.Replace("5f0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e", "not-a-uuid"),
            "[]", "{", ""
        })
            Assert.Throws<InvalidDataException>(() => ClaudeHostConfig.Parse(Encoding.UTF8.GetBytes(bad)));
    }
}
