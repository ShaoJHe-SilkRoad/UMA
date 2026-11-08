using System.Text.Json;
using AUV.Windows.Core;

namespace AUV.Windows.Tests;

/// <summary>Windows 0.18.4 parity rules ported from Mac 0.17.2–0.18.4.</summary>
public sealed class QuotaWindowPolicyTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 7, 12, 0, 0, TimeSpan.Zero);
    private static QuotaWindow Five(double remaining, int resetMinutes = 120) => new("codex.primary", 300, remaining, Now.AddMinutes(resetMinutes));
    private static QuotaWindow Seven(double remaining, int resetHours = 72) => new("codex.secondary", 10080, remaining, Now.AddHours(resetHours));

    [Fact] public void FirstReadingShowsFiveHourWindow() => Assert.Equal("codex.primary", QuotaWindowPolicy.Select([Seven(40), Five(90)], null, Now));
    [Fact] public void SpentWindowComesFirstEvenWithoutHistory() => Assert.Equal("codex.secondary", QuotaWindowPolicy.Select([Five(80), Seven(0)], null, Now));
    [Fact] public void SpentShorterWindowWinsTie() => Assert.Equal("codex.primary", QuotaWindowPolicy.Select([Seven(0), Five(0)], null, Now));
    [Fact] public void LargestDropSinceLastReadingWins()
    {
        var previous = new QuotaSelection("codex.primary", [Five(90), Seven(50)]);
        Assert.Equal("codex.secondary", QuotaWindowPolicy.Select([Five(89), Seven(45)], previous, Now));
    }
    [Fact] public void IncreasesDoNotCountAsChange()
    {
        var previous = new QuotaSelection("codex.secondary", [Five(10), Seven(50)]);
        Assert.Equal("codex.secondary", QuotaWindowPolicy.Select([Five(100, 300), Seven(50)], previous, Now));
    }
    [Fact] public void NoChangeKeepsPreviousSelection()
    {
        var previous = new QuotaSelection("codex.secondary", [Five(90), Seven(50)]);
        Assert.Equal("codex.secondary", QuotaWindowPolicy.Select([Five(90), Seven(50)], previous, Now));
    }
    [Fact] public void DropAcrossDifferentResetEpochIsIgnored()
    {
        var previous = new QuotaSelection("codex.secondary", [new("codex.primary", 300, 95, Now.AddMinutes(-30)), Seven(50)]);
        Assert.Equal("codex.secondary", QuotaWindowPolicy.Select([Five(60, 240), Seven(50)], previous, Now));
    }
    [Fact] public void ExpiredWindowIsNotEligible() => Assert.Equal("codex.secondary", QuotaWindowPolicy.Select([Five(0, -1), Seven(40)], null, Now));
    [Fact] public void EmptyWindowsSelectNothing() => Assert.Null(QuotaWindowPolicy.Select([], null, Now));
}

public sealed class CodexParityTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 7, 12, 0, 0, TimeSpan.Zero);
    private static JsonElement Json(string value) { using var document = JsonDocument.Parse(value); return document.RootElement.Clone(); }
    private static readonly JsonElement Account = Json("""{"account":{"type":"chatgpt","planType":"pro"}}""");
    private static JsonElement Limits(double fiveUsed, double weekUsed, string lengthKey = "windowDurationMins") =>
        Json(JsonSerializer.Serialize(new { rateLimits = new { limitId = "codex", primary = Window(fiveUsed, 300, Now.AddHours(2), lengthKey), secondary = Window(weekUsed, 10080, Now.AddDays(3), lengthKey) } }));
    private static Dictionary<string, object> Window(double used, int minutes, DateTimeOffset reset, string lengthKey) => new() { ["usedPercent"] = used, [lengthKey] = minutes, ["resetsAt"] = reset.ToUnixTimeSeconds() };

    [Fact] public void DecodeCarriesBothWindowsAndStructuredResetAndObservation()
    {
        var value = CodexUsageDecoder.Decode(Account, Limits(10, 60), default, Now);
        Assert.Equal(2, value.Windows.Count); Assert.Equal("codex.primary", value.Selection!.SelectedId);
        Assert.Equal("90%", value.Card.Value); Assert.Equal(300, value.Card.WindowMinutes); Assert.Equal("5h", value.Card.WizardWindow);
        Assert.Equal(Now.AddHours(2).ToUnixTimeSeconds(), value.Card.ResetsAt!.Value.ToUnixTimeSeconds()); Assert.Equal(Now, value.Card.ObservedAt);
        Assert.True(value.HasSecondaryWindow); Assert.Equal(40, value.Usage.WeeklyRemaining); Assert.Equal(90, value.Usage.ShortRemaining);
    }
    [Fact] public void SecondReadFollowsTheWindowThatDropped()
    {
        var first = CodexUsageDecoder.Decode(Account, Limits(10, 60), default, Now);
        var second = CodexUsageDecoder.Decode(Account, Limits(10, 70), default, Now.AddMinutes(5), first.Selection);
        Assert.Equal("codex.secondary", second.Selection!.SelectedId); Assert.Equal("30%", second.Card.Value); Assert.Equal("7d", second.Card.WizardWindow);
    }
    [Fact] public void NewerWindowDurationFieldNameIsAccepted()
    {
        var value = CodexUsageDecoder.Decode(Account, Limits(0, 100, "windowDurationMinutes"), default, Now);
        Assert.Equal("0%", value.Card.Value); Assert.Equal("codex.secondary", value.Selection!.SelectedId);
    }
    [Fact] public void VerifiedZeroRemainsDisplayable()
    {
        var value = CodexUsageDecoder.Decode(Account, Limits(100, 100), default, Now);
        Assert.True(value.Card.HasDisplayableQuota); Assert.Equal("0%", value.Card.Value);
    }
}

public sealed class OrderingAndTrayTests
{
    private static AgentPresentation Agent(string id, double? remaining)
    {
        var card = new AllowanceCard(id, AgentCatalog.Name(id), "x", null, remaining == null ? AllowanceKind.Unavailable : AllowanceKind.Percentage, remaining, null, "w", "s", "f",
            remaining == null ? ConnectionState.Unavailable : ConnectionState.Connected);
        return new(id, card.Name, "x", UsageSnapshot.Unknown, false, card);
    }
    [Fact] public void SavedOrderPlacesListedAgentsFirstAndAppendsUnplaced()
    {
        var ordered = AgentOrdering.Apply(AgentCatalog.DefaultOrder, x => x, ["workbuddy", "codex"]);
        Assert.Equal(["workbuddy", "codex", "claude", "antigravity"], ordered);
    }
    [Fact] public void EmptyOrderKeepsOriginal() => Assert.Equal(AgentCatalog.DefaultOrder, AgentOrdering.Apply(AgentCatalog.DefaultOrder, x => x, []));
    [Fact] public void MoveReturnsCompleteVisibleOrder()
    {
        Assert.Equal(["claude", "codex", "workbuddy", "antigravity"], AgentOrdering.Move(AgentCatalog.DefaultOrder, "claude", 0));
        Assert.Equal(["codex", "workbuddy", "antigravity", "claude"], AgentOrdering.Move(AgentCatalog.DefaultOrder, "claude", 99));
        Assert.Equal(AgentCatalog.DefaultOrder, AgentOrdering.Move(AgentCatalog.DefaultOrder, "missing", 0));
    }
    [Fact] public void UnknownAndDuplicateSavedIdsAreDropped() => Assert.Equal(["claude", "codex"], AgentOrdering.Normalize(["claude", "bogus", "codex", "claude"]));
    [Fact] public void ShellReorderAndRestoreDefault()
    {
        var shell = new ShellState(false); shell.Reorder(["antigravity", "workbuddy"]);
        Assert.Equal(["antigravity", "workbuddy", "codex", "claude"], shell.Agents.Select(a => a.Id));
        shell.Reorder([]); Assert.Equal(AgentCatalog.DefaultOrder, shell.Agents.Select(a => a.Id));
    }
    [Fact] public void TrayPrefersCodexUntilArranged()
    {
        var agents = new[] { Agent("workbuddy", 50), Agent("codex", 70) };
        Assert.Equal("codex", TrayAgentPolicy.Select(agents, "", arranged: false)!.Id);
        Assert.Equal("workbuddy", TrayAgentPolicy.Select(agents, "", arranged: true)!.Id);
    }
    [Fact] public void TrayFallsToNextAgentWithReading()
    {
        var agents = new[] { Agent("codex", null), Agent("claude", null), Agent("workbuddy", 12) };
        Assert.Equal("workbuddy", TrayAgentPolicy.Select(agents, "", arranged: true)!.Id);
        Assert.Null(TrayAgentPolicy.Select([Agent("codex", null)], "", false));
    }
    [Fact] public void PinnedTrayAgentIsUsedEvenWithoutReading()
    {
        var agents = new[] { Agent("codex", 70), Agent("claude", null) };
        Assert.Equal("claude", TrayAgentPolicy.Select(agents, "claude", false)!.Id);
        Assert.Equal("codex", TrayAgentPolicy.Select(agents, "antigravity", false)!.Id);
    }
}

public sealed class RefreshAndFreshnessTests
{
    private static readonly DateTimeOffset Now = new(2026, 11, 7, 12, 0, 0, TimeSpan.Zero);
    [Theory] [InlineData(5)] [InlineData(10)] [InlineData(15)] [InlineData(30)] [InlineData(60)]
    public void SupportedIntervalsAreKept(int minutes) { var r = new RefreshPreferences { IntervalMinutes = minutes }; r.Normalize(); Assert.Equal(minutes, r.IntervalMinutes); }
    [Theory] [InlineData(0)] [InlineData(1)] [InlineData(7)] [InlineData(-5)] [InlineData(120)]
    public void UnsupportedIntervalFallsBackToFive(int minutes) { var r = new RefreshPreferences { IntervalMinutes = minutes }; r.Normalize(); Assert.Equal(5, r.IntervalMinutes); }
    [Fact] public void ReadingIsCurrentForIntervalPlusGraceOnly()
    {
        var refresh = new RefreshPreferences { IntervalMinutes = 10 };
        Assert.True(ReadingFreshness.IsCurrent(Now.AddMinutes(-12), Now, refresh));
        Assert.False(ReadingFreshness.IsCurrent(Now.AddMinutes(-12.5), Now, refresh));
        Assert.False(ReadingFreshness.IsCurrent(null, Now, refresh));
        Assert.False(ReadingFreshness.IsCurrent(Now.AddMinutes(5), Now, refresh));
    }
    [Fact] public void ManualModeUsesFifteenMinuteValidity()
    {
        var refresh = new RefreshPreferences { Automatic = false, IntervalMinutes = 60 };
        Assert.True(ReadingFreshness.IsCurrent(Now.AddMinutes(-17), Now, refresh)); Assert.False(ReadingFreshness.IsCurrent(Now.AddMinutes(-18), Now, refresh));
    }
}

public sealed class UpgradeSettingsTests
{
    private static string Fixture => Path.Combine(AppContext.BaseDirectory, "Fixtures", "settings-0.16.3.json");
    private static void WithCopy(Action<string> run)
    {
        var directory = Path.Combine(Path.GetTempPath(), "AUV.Windows.Tests", Guid.NewGuid().ToString("N")); Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "settings.v1.json"); File.Copy(Fixture, path);
        try { run(path); } finally { Directory.Delete(directory, true); }
    }
    [Fact] public void OldPreferencesLoadUnchangedWithNewDefaults() => WithCopy(path =>
    {
        var store = new SettingsStore(path); var settings = store.Load(new());
        Assert.Null(store.LastError);
        Assert.Equal("Light", settings.Theme); Assert.True(settings.LargerText); Assert.Equal("workbuddy", settings.SelectedAgent); Assert.Equal("ThreadOS", settings.ActiveSection);
        Assert.Equal(1100, settings.Geometry.Width); Assert.Equal(80.5, settings.Geometry.Top);
        Assert.True(settings.Desktop.WidgetVisible); Assert.False(settings.Desktop.AlwaysOnTop); Assert.False(settings.Desktop.CloseToTray); Assert.True(settings.Desktop.HideTrayIcon);
        Assert.Equal(WizardDensity.Minimalist, settings.Desktop.Density); Assert.False(settings.Desktop.ShowStatus); Assert.Equal(1500, settings.Desktop.Left);
        Assert.False(settings.Providers.CodexEnabled); Assert.True(settings.Providers.WorkBuddyConsent);
        Assert.Equal(new RoleSelection("gpt-6.1-sol", "ultra"), settings.Roles["leader"]); Assert.Equal(4, settings.Roles.Count);
        Assert.Equal("System", settings.Language); Assert.True(settings.Refresh.Automatic); Assert.Equal(5, settings.Refresh.IntervalMinutes); Assert.False(settings.Refresh.OnWake);
        Assert.Empty(settings.AgentOrder); Assert.Equal("", settings.TrayAgent); Assert.False(settings.ShowCostEstimate); Assert.Null(settings.SettingsWidth);
    });
    [Fact] public void SavingKeepsEveryOldFieldAndAddsNewOnes() => WithCopy(path =>
    {
        var store = new SettingsStore(path); var settings = store.Load(new());
        settings.AgentOrder = ["workbuddy", "codex"]; settings.Refresh.IntervalMinutes = 30; settings.TrayAgent = "codex"; settings.Language = "zh"; settings.ShowCostEstimate = true;
        Assert.True(store.Save(settings));
        using var json = JsonDocument.Parse(File.ReadAllText(path)); var root = json.RootElement;
        foreach (var key in new[] { "Version", "Theme", "LargerText", "SelectedAgent", "ActiveSection", "CatalogRevision", "Geometry", "Desktop", "Providers", "Roles" }) Assert.True(root.TryGetProperty(key, out _), key);
        Assert.Equal(1, root.GetProperty("Version").GetInt32());
        var reloaded = new SettingsStore(path).Load(new());
        Assert.Equal(["workbuddy", "codex"], reloaded.AgentOrder); Assert.Equal(30, reloaded.Refresh.IntervalMinutes); Assert.Equal("codex", reloaded.TrayAgent); Assert.Equal("zh", reloaded.Language); Assert.True(reloaded.ShowCostEstimate);
        Assert.True(reloaded.Desktop.HideTrayIcon); Assert.Equal(WizardDensity.Minimalist, reloaded.Desktop.Density);
    });
    [Fact] public void InvalidNewFieldsAreNormalized()
    {
        var settings = new PreviewSettings { Language = "fr", Refresh = null!, AgentOrder = null!, TrayAgent = "bogus", SettingsWidth = double.NaN, SettingsHeight = 10 };
        settings.Normalize(new());
        Assert.Equal("System", settings.Language); Assert.Equal(5, settings.Refresh.IntervalMinutes); Assert.Empty(settings.AgentOrder); Assert.Equal("", settings.TrayAgent);
        Assert.Null(settings.SettingsWidth); Assert.Null(settings.SettingsHeight);
    }
    [Fact] public void DefaultPreferenceDirectoryIsUnchanged() =>
        Assert.EndsWith(Path.Combine("AUV.Windows.UI.Preview", "settings.v1.json"), SettingsStore.DefaultPath);
}

public sealed class LocalCostTests
{
    private static readonly TimeZoneInfo Utc = TimeZoneInfo.Utc;
    private static string Line(string type, object payload, string timestamp = "2026-11-06T10:00:00Z") =>
        JsonSerializer.Serialize(new { timestamp, type, payload });
    private static string Tokens(long input, long cached, long output, string timestamp) =>
        Line("event_msg", new { type = "token_count", info = new { total_token_usage = new { input_tokens = input, cached_input_tokens = cached, output_tokens = output, total_tokens = input + output } } }, timestamp);
    private static List<CodexLocalCostEstimator.CostDelta> Read(params string[] lines) => CodexLocalCostEstimator.ReadForTest(new StringReader(string.Join("\n", lines)), Utc)!;

    [Fact] public void CumulativeCountersBecomeDeltasPricedFromTheTurnModel()
    {
        var deltas = Read(Line("turn_context", new { model = "gpt-5.6-terra" }),
            Tokens(1_000_000, 0, 0, "2026-11-06T10:00:00Z"), Tokens(2_000_000, 1_000_000, 1_000_000, "2026-11-06T11:00:00Z"));
        Assert.Equal(2, deltas.Count); Assert.All(deltas, d => Assert.True(d.Priced));
        // 1M uncached input = 2.50; then 1M cached input (0.25) + 1M output (15) = 15.25
        Assert.Equal(2.5m, deltas[0].Usd); Assert.Equal(15.25m, deltas[1].Usd);
        var (total, usd, priced) = CodexLocalCostEstimator.Summarize(deltas); Assert.Equal(3_000_000, total); Assert.Equal(17.75m, usd); Assert.Equal(total, priced);
    }
    [Fact] public void UnknownOrPreCatalogueModelsAreUnpricedButCounted()
    {
        var deltas = Read(Line("turn_context", new { model = "gpt-6.1-sol" }), Tokens(100, 0, 50, "2026-11-06T10:00:00Z"),
            Line("turn_context", new { model = "gpt-5.5" }), Tokens(200, 0, 100, "2026-07-01T10:00:00Z"));
        Assert.Equal(2, deltas.Count); Assert.All(deltas, d => Assert.False(d.Priced)); Assert.Equal(300, CodexLocalCostEstimator.Summarize(deltas).Total);
    }
    [Fact] public void ForkedSessionFirstCheckpointIsBaselineOnly()
    {
        var deltas = Read(Line("session_meta", new { forked_from_id = "abc" }), Line("turn_context", new { model = "gpt-5.4" }),
            Tokens(5_000_000, 0, 0, "2026-11-06T10:00:00Z"), Tokens(5_000_100, 0, 0, "2026-11-06T10:05:00Z"));
        Assert.Single(deltas); Assert.Equal(100, deltas[0].Total);
    }
    [Fact] public void CounterResetStartsANewEpoch()
    {
        var deltas = Read(Line("turn_context", new { model = "gpt-5.4" }), Tokens(1000, 0, 0, "2026-11-06T10:00:00Z"), Tokens(300, 0, 0, "2026-11-06T10:05:00Z"));
        Assert.Equal([1000L, 300L], deltas.Select(d => d.Total));
    }
    [Fact] public void ContentLinesAndMalformedLinesAreIgnored()
    {
        var deltas = Read("{not json", Line("response_item", new { type = "message", content = "secret prompt" }), Line("turn_context", new { model = "gpt-5.4" }), Tokens(10, 0, 0, "2026-11-06T10:00:00Z"));
        Assert.Single(deltas);
    }
    [Fact] public void EstimatorAggregatesSevenLocalDaysAndLifetime()
    {
        var root = Path.Combine(Path.GetTempPath(), "AUV.Windows.Tests", Guid.NewGuid().ToString("N")); Directory.CreateDirectory(Path.Combine(root, "2026", "11"));
        try
        {
            File.WriteAllLines(Path.Combine(root, "2026", "11", "a.jsonl"), [Line("turn_context", new { model = "gpt-5.6-luna" }),
                Tokens(1_000_000, 0, 0, "2026-10-20T10:00:00Z"), Tokens(2_000_000, 0, 0, "2026-11-06T10:00:00Z")]);
            var estimate = new CodexLocalCostEstimator().Estimate([root, Path.Combine(root, "missing")], new DateTimeOffset(2026, 11, 7, 12, 0, 0, TimeSpan.Zero), Utc)!;
            Assert.Equal(1m, estimate.SevenDayUsd); Assert.Equal(2m, estimate.LifetimeUsd); Assert.Equal(1_000_000, estimate.SevenDayTokens); Assert.Equal(2_000_000, estimate.LifetimeTokens);
            Assert.Equal(1, estimate.PricedCoverage); Assert.Equal(1, estimate.FilesRead);
        }
        finally { Directory.Delete(root, true); }
    }
    [Fact] public void NoLogsMeansNoEstimate() => Assert.Null(new CodexLocalCostEstimator().Estimate([Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"))], DateTimeOffset.UtcNow, Utc));
    [Fact] public void PriceTableMatchesMacCatalogue()
    {
        Assert.Equal("2026-07-13-standard", CodexPriceTable.Version);
        var sol = CodexPriceTable.For("gpt-5.6-sol-2026", new DateTimeOffset(2026, 8, 1, 0, 0, 0, TimeSpan.Zero))!;
        Assert.Equal((5m, 0.5m, 30m), (sol.InputPerMillion, sol.CachedInputPerMillion, sol.OutputPerMillion));
        Assert.Null(CodexPriceTable.For("gpt-5.6-sol", new DateTimeOffset(2026, 7, 12, 0, 0, 0, TimeSpan.Zero)));
        Assert.Null(CodexPriceTable.For("gpt-6.1-sol", DateTimeOffset.UtcNow));
    }
}

public sealed class LanguageTests
{
    [Fact] public void ChineseOverrideIsScopedToTheCurrentFlow()
    {
        using (UiText.Override(UiLanguage.Chinese))
        {
            Assert.Equal("剩余 68%", UsageSnapshot.RemainingText(68)); Assert.Equal("未知", UsageSnapshot.RemainingText(null));
            Assert.Equal("7 天窗口", new QuotaWindow("x", 10080, 1, null).Label); Assert.Equal("超高", ThinkingLabels.Label("ultra"));
        }
        using (UiText.Override(UiLanguage.English)) { Assert.Equal("68% remaining", UsageSnapshot.RemainingText(68)); Assert.Equal("Ultra", ThinkingLabels.Label("ultra")); }
    }
    [Theory] [InlineData("zh", "en-US", UiLanguage.Chinese)] [InlineData("en", "zh-CN", UiLanguage.English)] [InlineData("System", "zh-CN", UiLanguage.Chinese)] [InlineData("System", "de-DE", UiLanguage.English)]
    public void LanguagePreferenceResolves(string preference, string culture, UiLanguage expected) =>
        Assert.Equal(expected, UiText.Resolve(preference, new System.Globalization.CultureInfo(culture)));
    [Fact] public void ResetTextIsBlankWhenUnknownOrPast()
    {
        var now = DateTimeOffset.UtcNow; Assert.Null(ResetText.Format(null, now)); Assert.Null(ResetText.Format(now.AddMinutes(-1), now));
        using (UiText.Override(UiLanguage.English)) Assert.StartsWith("Resets in 2 hr (", ResetText.Format(now.AddHours(2), now));
        using (UiText.Override(UiLanguage.Chinese)) Assert.StartsWith("2 小时后重置（", ResetText.Format(now.AddHours(2), now));
    }
    [Fact] public void ThreadOsDefaultsAndCatalogueMatchMac()
    {
        var vm = new AUV.Windows.App.MainViewModel(false, new());
        Assert.Equal(["leader:gpt-6.1-sol:high", "coderCluster:gpt-6-luna:medium", "reviewerCluster:gpt-6-luna:medium", "qa:gpt-6.1-sol:high"], vm.Roles.Select(r => $"{r.Key}:{r.Model}:{r.Effort}"));
        Assert.Equal("sol-luna-ultra-20261010.1", vm.Catalog.Revision);
    }
}
