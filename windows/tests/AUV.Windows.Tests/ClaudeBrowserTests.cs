using System.Text;
using System.Text.Json;
using AUV.Windows.Core;

namespace AUV.Windows.Tests;

/// <summary>The Claude browser companion's wire contract, AUV's coordinator and the Claude card. No account data is used.</summary>
public class ClaudeBrowserTests
{
    internal const string Generation = "5f0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e";
    internal const string ExtensionId = "abcdefghijklmnopabcdefghijklmnop";
    internal static readonly ClaudeCompanionManifest Manifest = new(ExtensionId, Generation, "1.0.0", "2026110801");
    private const string Request = "11111111-2222-4333-8444-555555555555";
    private const string ObservationId = "66666666-7777-4888-9999-aaaaaaaaaaaa";

    internal static string Terminal(string request = Request, string observationId = ObservationId, string observedAt = "2026-11-08T03:00:00.000Z",
        string fiveHour = """{"usedPercentage":8,"resetAt":"2026-11-08T05:40:00.000Z"}""", string weekly = """{"usedPercentage":41,"resetAt":null}""", string generation = Generation) =>
        $$$"""{"kind":"claudeBrowserTerminalPacket","schemaVersion":2,"sourceID":"claude-browser-usage","browserFamily":"chromium","requestID":"{{{request}}}","targetRequestID":null,"runtimeGenerationID":"{{{generation}}}","status":"refreshCompleted","occurredAt":"2026-11-08T03:00:01.000Z","observation":{"kind":"claudeUsageObservation","schemaVersion":2,"sourceID":"claude-browser-usage","browserFamily":"chromium","routeState":"verifiedUsage","requestID":"{{{request}}}","observationID":"{{{observationId}}}","observation":{"fiveHour":{{{fiveHour}}},"weeklyAllModels":{{{weekly}}},"modelSpecificWeekly":null,"observedAt":"{{{observedAt}}}","extractorSchemaVersion":2,"sourceLayoutVersion":1}},"providerFailureReason":null}""";
    internal static string Failure(string request, string status, string reason = "null") =>
        $$$"""{"kind":"claudeBrowserTerminalPacket","schemaVersion":2,"sourceID":"claude-browser-usage","browserFamily":"chromium","requestID":"{{{request}}}","targetRequestID":null,"runtimeGenerationID":"{{{Generation}}}","status":"{{{status}}}","occurredAt":"2026-11-08T03:00:01.000Z","observation":null,"providerFailureReason":{{{reason}}}}""";
    internal static string Ready(string request, string status = "extensionBackgroundReady", string build = "2026110801", string extension = ExtensionId) =>
        $$$"""{"kind":"claudeBrowserAutomationEvent","schemaVersion":2,"sourceID":"claude-browser-usage","browserFamily":"chromium","requestID":"{{{request}}}","status":"{{{status}}}","occurredAt":"2026-11-08T03:00:00.000Z","companionVersion":"1.0.0","companionBuild":"{{{build}}}","protocolSchemaVersion":2,"containingApplicationIdentifier":"com.silkrd.auv.windows","extensionIdentifier":"{{{extension}}}","teamIdentifier":"","runtimeGenerationID":"{{{Generation}}}"}""";
    private static CompanionMessage Decode(string json) => CompanionMessageCodec.DecodeFromExtension(Encoding.UTF8.GetBytes(json));

    [Fact] public void ObservationKeepsOnlyPercentagesResetsAndTime()
    {
        var terminal = Assert.IsType<CompanionTerminal>(Decode(Terminal()));
        Assert.Equal("refreshCompleted", terminal.Status); Assert.Equal(ObservationId, terminal.ObservationId);
        Assert.Equal(8, terminal.Observation!.FiveHour!.UsedPercentage); Assert.Equal(DateTimeOffset.Parse("2026-11-08T05:40:00Z"), terminal.Observation.FiveHour.ResetAt);
        Assert.Equal(41, terminal.Observation.WeeklyAllModels!.UsedPercentage); Assert.Null(terminal.Observation.WeeklyAllModels.ResetAt);
    }

    [Theory]
    [InlineData("\"browserFamily\":\"chromium\",\"requestID\"", "\"browserFamily\":\"safari\",\"requestID\"")]
    [InlineData("\"usedPercentage\":8,", "\"usedPercentage\":101,")]
    [InlineData("\"usedPercentage\":8,", "\"usedPercentage\":-1,")]
    [InlineData("\"usedPercentage\":8,", "\"usedPercentage\":\"8\",")]
    [InlineData("\"routeState\":\"verifiedUsage\"", "\"routeState\":\"pending\"")]
    [InlineData("\"sourceLayoutVersion\":1}", "\"sourceLayoutVersion\":1,\"email\":\"x\"}")]
    [InlineData("\"providerFailureReason\":null}", "\"providerFailureReason\":null,\"cookie\":\"x\"}")]
    [InlineData("\"resetAt\":\"2026-11-08T05:40:00.000Z\"", "\"resetAt\":\"tomorrow\"")]
    [InlineData("\"extractorSchemaVersion\":2", "\"extractorSchemaVersion\":1")]
    [InlineData("\"observationID\":\"66666666-7777-4888-9999-aaaaaaaaaaaa\"", "\"observationID\":\"not-a-uuid\"")]
    [InlineData("\"status\":\"refreshCompleted\"", "\"status\":\"signInRequired\"")]
    public void MalformedOrExtraFieldsAreRejected(string from, string to)
    {
        var json = Terminal(); Assert.Contains(from, json);
        Assert.Throws<CompanionProtocolException>(() => Decode(json.Replace(from, to)));
    }

    [Fact] public void ObservationNeedsAnAccountWindowAndMatchingRequest()
    {
        Assert.Equal("no-account-window", Assert.Throws<CompanionProtocolException>(() => Decode(Terminal(fiveHour: "null", weekly: "null"))).Code);
        var other = Terminal().Replace($"\"routeState\":\"verifiedUsage\",\"requestID\":\"{Request}\"", "\"routeState\":\"verifiedUsage\",\"requestID\":\"99999999-2222-4333-8444-555555555555\"");
        Assert.Throws<CompanionProtocolException>(() => Decode(other));
    }

    [Fact] public void OversizedEmptyAndDuplicateMessagesAreRejected()
    {
        Assert.Equal("message-too-large", Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.DecodeFromExtension(new byte[4097])).Code);
        Assert.Equal("message-empty", Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.DecodeFromExtension([])).Code);
        Assert.Equal("duplicate-field", Assert.Throws<CompanionProtocolException>(() => Decode(Terminal().Replace("\"schemaVersion\":2,\"sourceID\"", "\"schemaVersion\":2,\"schemaVersion\":2,\"sourceID\""))).Code);
    }

    [Theory]
    [InlineData("permissionRequired", "\"SITE_PERMISSION_MISSING\"", true)]
    [InlineData("signInRequired", "\"PROVIDER_SESSION_UNAVAILABLE\"", true)]
    [InlineData("usageUnavailable", "\"PROVIDER_STRUCTURE_UNSUPPORTED\"", true)]
    [InlineData("tabUnavailable", "null", true)]
    [InlineData("ownedTabClosed", "\"PROVIDER_TAB_CLOSED\"", false)]
    [InlineData("usageUnavailable", "\"SOMETHING_ELSE\"", false)]
    [InlineData("refreshStarted", "null", false)]
    public void FailurePacketsFollowTheMacRules(string status, string reason, bool valid)
    {
        var json = Failure(Request, status, reason);
        if (valid) Assert.Equal(status, Assert.IsType<CompanionTerminal>(Decode(json)).Status);
        else Assert.Throws<CompanionProtocolException>(() => Decode(json));
    }

    [Fact] public void IdentityEventsMustCarryTheWindowsIdentity()
    {
        var ready = Assert.IsType<CompanionEvent>(Decode(Ready(Request)));
        Assert.Equal(ExtensionId, ready.Identity!.ExtensionIdentifier); Assert.Equal(Generation, ready.Identity.RuntimeGenerationId);
        Assert.Throws<CompanionProtocolException>(() => Decode(Ready(Request).Replace("com.silkrd.auv.windows", "com.silkrd.uma")));
        Assert.Throws<CompanionProtocolException>(() => Decode(Ready(Request).Replace("\"teamIdentifier\":\"\"", "\"teamIdentifier\":\"C6TUZVJ6SJ\"")));
        Assert.Throws<CompanionProtocolException>(() => Decode(Ready(Request, extension: "ABCDEFGHIJKLMNOPABCDEFGHIJKLMNOP")));
        // A status without identity may not carry identity fields.
        Assert.Throws<CompanionProtocolException>(() => Decode(Ready(Request, status: "refreshStarted")));
    }

    [Fact] public void CommandsRoundTripAndAreValidatedOnTheWay()
    {
        var command = new CompanionCommand(ClaudeBrowserContract.CloseCommand, Request, ObservationId);
        Assert.Equal(command, CompanionMessageCodec.DecodeForExtension(CompanionMessageCodec.Encode(command)));
        var read = new CompanionCommand(ClaudeBrowserContract.RefreshCommand, Request, Placement: "minimizedWindow");
        Assert.Equal(read, CompanionMessageCodec.DecodeForExtension(CompanionMessageCodec.Encode(read)));
        Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.Encode(new CompanionCommand(ClaudeBrowserContract.RefreshCommand, Request, Placement: "foreground")));
        Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.Encode(new CompanionCommand(ClaudeBrowserContract.CloseCommand, Request, Request)));
        Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.Encode(new CompanionCommand("openAnyUrl", Request)));
    }

    [Fact] public void HostHelloAcceptsOnlyAnExtensionOrigin()
    {
        var hello = new HostHello("1.0.0", "2026110801", ClaudeBrowserContract.ExtensionOrigin(ExtensionId), "chrome", Generation);
        Assert.Equal(hello, CompanionMessageCodec.DecodeFromHost(CompanionMessageCodec.Encode(hello)));
        Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.Encode(hello with { ExtensionOrigin = "https://claude.ai/" }));
        Assert.Throws<CompanionProtocolException>(() => CompanionMessageCodec.Encode(hello with { BrowserProduct = "firefox" }));
    }

    [Fact] public async Task FramingReadsWhatItWritesAndRejectsBadLengths()
    {
        using var stream = new MemoryStream();
        await CompanionFraming.WriteAsync(stream, Encoding.UTF8.GetBytes("{\"a\":1}"), 4096, CancellationToken.None);
        stream.Position = 0;
        Assert.Equal("{\"a\":1}", Encoding.UTF8.GetString((await CompanionFraming.ReadAsync(stream, 4096, CancellationToken.None))!));
        Assert.Null(await CompanionFraming.ReadAsync(stream, 4096, CancellationToken.None));
        using var big = new MemoryStream(BitConverter.GetBytes(5000));
        await Assert.ThrowsAsync<CompanionProtocolException>(() => CompanionFraming.ReadAsync(big, 4096, CancellationToken.None));
        using var cut = new MemoryStream([.. BitConverter.GetBytes(10), (byte)'{']);
        await Assert.ThrowsAsync<CompanionProtocolException>(() => CompanionFraming.ReadAsync(cut, 4096, CancellationToken.None));
    }

    [Fact] public void CompanionManifestRoundTripsAndRejectsExtras()
    {
        Assert.Equal(Manifest, ClaudeCompanionManifest.Parse(Manifest.ToJson()));
        var extra = Encoding.UTF8.GetString(Manifest.ToJson()).Replace("\"schemaVersion\": 1", "\"schemaVersion\": 1, \"token\": \"x\"");
        Assert.Throws<InvalidDataException>(() => ClaudeCompanionManifest.Parse(Encoding.UTF8.GetBytes(extra)));
    }

    // ---- Coordinator ----

    internal sealed class FakeLink : IClaudeCompanionLink
    {
        public CompanionLinkState State { get; set; } = CompanionLinkState.Connected;
        public HostHello? Host { get; set; } = new("1.0.0", "2026110801", ClaudeBrowserContract.ExtensionOrigin(ExtensionId), "chrome", Generation);
        public string? RejectionReason { get; set; }
        public HostHello? RejectedHost { get; set; }
        public event Action<CompanionMessage>? Received;
        public event Action? StateChanged;
        public List<CompanionCommand> Sent { get; } = [];
        public Func<CompanionCommand, IEnumerable<string>> Respond { get; set; } = _ => [];
        public Task<bool> SendAsync(CompanionMessage message, CancellationToken cancellationToken)
        {
            if (message is not CompanionCommand command) return Task.FromResult(true);
            lock (Sent) Sent.Add(command);
            var replies = Respond(command).ToArray();
            _ = Task.Run(async () => { await Task.Delay(5); foreach (var reply in replies) Received?.Invoke(CompanionMessageCodec.DecodeFromExtension(Encoding.UTF8.GetBytes(reply))); });
            return Task.FromResult(State == CompanionLinkState.Connected);
        }
        public void Push(string json) => Received?.Invoke(CompanionMessageCodec.DecodeFromExtension(Encoding.UTF8.GetBytes(json)));
        public void Changed() => StateChanged?.Invoke();
    }

    internal static IEnumerable<string> Healthy(CompanionCommand c, Func<string, IEnumerable<string>>? read = null) => c.Command switch
    {
        ClaudeBrowserContract.WakeCommand => [Ready(c.RequestId)],
        ClaudeBrowserContract.QualifyCommand => [Ready(c.RequestId, "bridgeReady")],
        ClaudeBrowserContract.RefreshCommand => read?.Invoke(c.RequestId) ?? [Terminal(c.RequestId, Guid.NewGuid().ToString(), DateTimeOffset.UtcNow.ToString("O"))],
        _ => []
    };
    private static readonly CompanionTimings Fast = new(TimeSpan.FromMilliseconds(300), TimeSpan.FromMilliseconds(300), TimeSpan.FromMilliseconds(400), TimeSpan.FromMinutes(5), TimeSpan.FromSeconds(30));

    [Fact] public async Task HealthySyncWakesQualifiesAndReadsOnce()
    {
        var link = new FakeLink { Respond = c => Healthy(c) };
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        var result = await coordinator.SyncAsync("backgroundTab", CancellationToken.None);
        Assert.Equal(ClaudeSyncOutcome.Success, result.Outcome); Assert.Equal(1, result.Attempts); Assert.Equal("chrome", result.BrowserProduct);
        Assert.Equal([ClaudeBrowserContract.WakeCommand, ClaudeBrowserContract.QualifyCommand, ClaudeBrowserContract.RefreshCommand], link.Sent.Select(s => s.Command));
        Assert.Equal("backgroundTab", link.Sent[2].Placement);
    }

    [Fact] public async Task UnsolicitedAndRepeatedObservationsAreRejected()
    {
        string? replay = null;
        var link = new FakeLink { Respond = c => Healthy(c, id => [replay = Terminal(id, ObservationId, DateTimeOffset.UtcNow.ToString("O"))]) };
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        link.Push(Terminal(observedAt: DateTimeOffset.UtcNow.ToString("O"))); // nobody asked for this one
        Assert.Equal(0, coordinator.AcceptedObservations);
        Assert.Equal(ClaudeSyncOutcome.Success, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
        // The same observation ID again is refused, even for a new request.
        link.Respond = c => Healthy(c, id => [Terminal(id, ObservationId, DateTimeOffset.UtcNow.ToString("O"))]);
        var second = await coordinator.SyncAsync(null, CancellationToken.None);
        Assert.NotEqual(ClaudeSyncOutcome.Success, second.Outcome); Assert.Equal(1, coordinator.AcceptedObservations);
    }

    [Fact] public async Task OldObservationsAreNotCurrent()
    {
        var link = new FakeLink { Respond = c => Healthy(c, id => [Terminal(id, Guid.NewGuid().ToString(), DateTimeOffset.UtcNow.AddMinutes(-6).ToString("O"))]) };
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        Assert.Equal(ClaudeSyncOutcome.PageUnreadable, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
    }

    [Fact] public async Task SilentPageIsClosedAndRetriedOnce()
    {
        var reads = 0;
        var link = new FakeLink { Respond = c => Healthy(c, id => ++reads == 1 ? [] : [Terminal(id, Guid.NewGuid().ToString(), DateTimeOffset.UtcNow.ToString("O"))]) };
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        var result = await coordinator.SyncAsync(null, CancellationToken.None);
        Assert.Equal(ClaudeSyncOutcome.Success, result.Outcome); Assert.Equal(2, result.Attempts);
        var close = Assert.Single(link.Sent, s => s.Command == ClaudeBrowserContract.CloseCommand);
        Assert.Equal(link.Sent.First(s => s.Command == ClaudeBrowserContract.RefreshCommand).RequestId, close.TargetRequestId);
    }

    [Fact] public async Task SignInIsNotRetried()
    {
        var link = new FakeLink { Respond = c => Healthy(c, id => [Failure(id, "signInRequired", "\"PROVIDER_SESSION_UNAVAILABLE\"")]) };
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        var result = await coordinator.SyncAsync(null, CancellationToken.None);
        Assert.Equal(ClaudeSyncOutcome.SignInRequired, result.Outcome); Assert.Equal(1, link.Sent.Count(s => s.Command == ClaudeBrowserContract.RefreshCommand));
    }

    [Fact] public async Task StructureChangeIsReportedAsUnsupportedLayout()
    {
        var link = new FakeLink { Respond = c => Healthy(c, id => [Failure(id, "usageUnavailable", "\"PROVIDER_STRUCTURE_UNSUPPORTED\"")]) };
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        Assert.Equal(ClaudeSyncOutcome.LayoutUnsupported, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
    }

    [Fact] public async Task CompanionFromAnotherBuildNeedsAnUpdate()
    {
        var link = new FakeLink { Respond = c => c.Command == ClaudeBrowserContract.WakeCommand ? [Ready(c.RequestId, build: "2026010101")] : Healthy(c) };
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        Assert.Equal(ClaudeSyncOutcome.UpdateRequired, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
        Assert.DoesNotContain(link.Sent, s => s.Command == ClaudeBrowserContract.RefreshCommand);
    }

    [Fact] public async Task SilentCompanionIsCountedAndNoReadIsSent()
    {
        var link = new FakeLink();
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        Assert.Equal(ClaudeSyncOutcome.CompanionSilent, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
        Assert.Equal(ClaudeSyncOutcome.CompanionSilent, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
        Assert.Equal(2, coordinator.ConsecutiveSilent); Assert.NotNull(coordinator.SilentSince);
        link.Respond = c => Healthy(c);
        Assert.Equal(ClaudeSyncOutcome.Success, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
        Assert.Equal(0, coordinator.ConsecutiveSilent); Assert.Null(coordinator.SilentSince);
    }

    [Fact] public async Task NoBrowserOrRejectedHostDoesNotSendAnything()
    {
        var link = new FakeLink { State = CompanionLinkState.NoBrowser };
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        Assert.Equal(ClaudeSyncOutcome.NotConnected, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
        link.State = CompanionLinkState.Rejected; link.RejectionReason = "generationMismatch";
        Assert.Equal(ClaudeSyncOutcome.UpdateRequired, (await coordinator.SyncAsync(null, CancellationToken.None)).Outcome);
        Assert.Empty(link.Sent);
    }

    [Fact] public async Task OneSyncAtATime()
    {
        var link = new FakeLink { Respond = c => Healthy(c) };
        using var coordinator = new ClaudeCompanionCoordinator(link, Manifest, Fast);
        var a = coordinator.SyncAsync(null, CancellationToken.None); var b = coordinator.SyncAsync(null, CancellationToken.None);
        Assert.Same(a, b); await a;
        Assert.Single(link.Sent, s => s.Command == ClaudeBrowserContract.RefreshCommand);
    }

    // ---- Card and settings ----

    [Fact] public void CardShowsBothWindowsLikeCodex()
    {
        var now = DateTimeOffset.Parse("2026-11-08T03:00:30Z");
        var observation = new CompanionObservation(new(8, now.AddHours(2)), new(41, now.AddDays(3)), now.AddSeconds(-30));
        using var _ = UiText.Override(UiLanguage.English);
        var agent = ClaudeBrowserPresentation.Success(observation, "edge", now, null);
        Assert.True(agent.Card.HasDisplayableQuota); Assert.Equal(2, agent.Windows.Count);
        Assert.Equal("claude.fiveHour", agent.Selection!.SelectedId); Assert.Equal(92, agent.Card.Percent);
        Assert.Equal(59, agent.Usage.WeeklyRemaining); Assert.Equal(observation.ObservedAt, agent.Card.ObservedAt);
        Assert.Contains("Edge companion", agent.Card.Source);
        // A spent weekly window is shown first, as for Codex.
        var spent = ClaudeBrowserPresentation.Success(observation with { WeeklyAllModels = new(100, now.AddDays(3)) }, "chrome", now, null);
        Assert.Equal("claude.weekly", spent.Selection!.SelectedId);
    }

    [Fact] public void FailuresShowAReasonAndNoFigure()
    {
        foreach (var outcome in Enum.GetValues<ClaudeSyncOutcome>().Where(o => o != ClaudeSyncOutcome.Success))
        {
            foreach (var language in new[] { UiLanguage.English, UiLanguage.Chinese })
            {
                using var _ = UiText.Override(language);
                var agent = ClaudeBrowserPresentation.Failure(outcome, "chrome");
                Assert.False(agent.Card.HasDisplayableQuota); Assert.False(string.IsNullOrWhiteSpace(agent.Card.Source));
            }
        }
    }

    [Fact] public void SettingsFrom0184GetTheDefaultsAndStayReadable()
    {
        var directory = Path.Combine(Path.GetTempPath(), "auv-claude-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(directory);
        try
        {
            var path = Path.Combine(directory, "settings.v1.json");
            File.WriteAllText(path, """{"Version":1,"Theme":"Light","LargerText":false,"SelectedAgent":"claude","ActiveSection":"AUV","Language":"zh","Refresh":{"Automatic":true,"IntervalMinutes":10,"OnWake":false},"AgentOrder":["claude","codex"],"TrayAgent":"","ShowCostEstimate":false}""");
            var store = new SettingsStore(path); var settings = store.Load(new ModelCatalog());
            Assert.Null(store.LastError); Assert.False(settings.ClaudeBrowser.Enabled); Assert.Equal("auto", settings.ClaudeBrowser.Browser);
            Assert.Equal("auto", settings.ClaudeBrowser.Placement); Assert.True(settings.ClaudeBrowser.AskToOpenBrowser); Assert.Null(settings.ClaudeBrowser.InstalledBuild);
            Assert.Equal(10, settings.Refresh.IntervalMinutes); Assert.Equal("zh", settings.Language);
            settings.ClaudeBrowser.Enabled = true; settings.ClaudeBrowser.Browser = "firefox"; settings.ClaudeBrowser.InstalledBuild = "12a";
            Assert.True(store.Save(settings));
            var again = store.Load(new ModelCatalog());
            Assert.True(again.ClaudeBrowser.Enabled); Assert.Equal("auto", again.ClaudeBrowser.Browser); Assert.Null(again.ClaudeBrowser.InstalledBuild);
            // A reader that does not know the new field (0.18.4) still finds every field it knows.
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            Assert.Equal("Light", document.RootElement.GetProperty("Theme").GetString());
        }
        finally { Directory.Delete(directory, true); }
    }

    [Fact] public void ClaudeIsNoLongerAPreparedPlaceholder()
    {
        Assert.Null(PreparedConnections.Find("claude"));
        Assert.NotNull(PreparedConnections.Find("antigravity"));
    }
}
