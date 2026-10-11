using System.Text.Json;
using AUV.Windows.Core;

namespace AUV.Windows.Tests;

public sealed class ProviderDataTests
{
    private static readonly DateTimeOffset Now = new(2026, 10, 10, 15, 0, 0, TimeSpan.Zero);
    private static JsonElement Json(string value) { using var document = JsonDocument.Parse(value); return document.RootElement.Clone(); }
    private static readonly JsonElement Account = Json("""{"account":{"type":"chatgpt","planType":"pro","email":"must-not-be-projected@example.test"}}""");
    [Fact] public void CodexSelectsItsBucketAndWeeklyWindowByDuration()
    {
        var value = CodexUsageDecoder.Decode(Account, Json("""{"rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":100,"windowDurationMins":10080}},"codex":{"limitId":"codex","primary":{"usedPercent":21,"windowDurationMins":300},"secondary":{"usedPercent":68,"windowDurationMins":10080}}}}"""), default, Now);
        Assert.Equal("32%", value.Card.Value); Assert.StartsWith("7-day window", value.Card.Window); Assert.Equal("79% remaining", value.SecondaryValue);
        Assert.DoesNotContain("example.test", value.Card.Description); Assert.Null(value.Usage.AccountWeek); Assert.Empty(value.Usage.Days);
    }
    [Fact] public void CodexDoesNotBorrowNonCodexQuotaOrInventUnlimited()
    {
        var value = CodexUsageDecoder.Decode(Account, Json("""{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300}},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":2,"windowDurationMins":10080}}}}"""), default, Now);
        Assert.Equal(AllowanceKind.Unavailable, value.Card.Kind); Assert.Equal(ConnectionState.Connected, value.Card.Connection);
    }
    [Theory] [InlineData(-1)] [InlineData(101)]
    public void CodexInvalidUsageIsUnknown(double used)
    {
        var value = CodexUsageDecoder.Decode(Account, Json($"{{\"rateLimits\":{{\"primary\":{{\"usedPercent\":{used},\"windowDurationMins\":300}}}}}}"), default, Now);
        Assert.Equal("—", value.Card.Value);
    }
    [Fact] public void CodexShortOnlyResponseHasTruthfulPrimaryAndNoWeeklyAlias()
    {
        var value = CodexUsageDecoder.Decode(Account, Json("""{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":300}}}"""), default, Now);
        Assert.Equal("100%", value.Card.Value); Assert.Equal("5-hour window", value.Card.Window); Assert.Null(value.Usage.WeeklyRemaining); Assert.Equal("Unknown", value.SecondaryValue);
    }
    [Fact] public void CodexAccountTokensAreNotLabeledLocalOrCosted()
    {
        var days = Enumerable.Range(0, 7).Select(i => new { startDate = new DateOnly(2026, 10, 4).AddDays(i).ToString("yyyy-MM-dd"), tokens = i });
        var value = CodexUsageDecoder.Decode(Account, Json("{}"), Json(JsonSerializer.Serialize(new { summary = new { lifetimeTokens = 2000 }, dailyUsageBuckets = days })), Now);
        Assert.Equal(21, value.Usage.AccountWeek); Assert.Equal(2000, value.Usage.AccountLifetime); Assert.Equal(7, value.Usage.Days.Count); Assert.Contains("account tokens", value.TokenSource); Assert.Null(value.Usage.LocalEstimate);
    }
    [Fact] public void CodexMissingAccountDoesNotProjectQuota()
    {
        var value = CodexUsageDecoder.Decode(Json("{\"account\":null}"), Json("""{"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":300}}}"""), default, Now);
        Assert.Equal(ConnectionState.Disconnected, value.Card.Connection); Assert.Equal("—", value.Card.Value);
    }
    private static string Pool(string used = "12.25", string total = "1000", string id = "base", string status = "active", string? expires = null) =>
        $$"""{"stablePageID":"{{id}}","kind":"subscriptionBase","used":"{{used}}","total":"{{total}}","displayedRemaining":null,"effectiveAtMilliseconds":null,"expiresAtMilliseconds":{{expires ?? "null"}},"pageStatus":"{{status}}"}""";
    private static JsonElement Credits(string rows, string balances = "[]") => Json($$"""{"extractorVersion":3,"discoveredSections":["subscription","addOn","benefitGift"],"subscriptionPools":[{{rows}}],"addOnPools":[],"benefitGiftPools":[],"authoritativePageBalances":{{balances}},"sectionSummaries":[{"section":"addOn","count":0,"remaining":"0"},{"section":"benefitGift","count":0,"remaining":"0"}]}""");
    [Fact] public void WorkBuddyTruncatedCurrentPoolListCannotBeAdmitted()
    {
        var incomplete = Credits(Pool()).GetRawText().Replace("\"count\":0", "\"count\":2");
        Assert.Throws<InvalidDataException>(() => WorkBuddyCreditsDecoder.Decode(Json(incomplete), Now));
    }
    [Fact] public void WorkBuddyUsesExactNativeCreditsWithoutPercentDenominator()
    {
        var value = WorkBuddyCreditsDecoder.Decode(Credits(Pool(), "[\"987.75\"]"), Now);
        Assert.Equal(987.75m, value.Card.Credits); Assert.Equal("987.75 Credits", value.Card.Value); Assert.Null(value.Card.FillFraction); Assert.Equal(ConnectionState.Connected, value.Card.Connection);
    }
    [Theory] [InlineData("-1")] [InlineData("1e2")] [InlineData("1,000")] [InlineData("01")] [InlineData("0.001")] [InlineData("1001")]
    public void WorkBuddyRejectsMalformedOrOverdrawnPools(string used) => Assert.Throws<InvalidDataException>(() => WorkBuddyCreditsDecoder.Decode(Credits(Pool(used)), Now));
    [Fact] public void WorkBuddyRejectsDuplicatesAndReconciliationFailure()
    {
        Assert.Throws<InvalidDataException>(() => WorkBuddyCreditsDecoder.Decode(Credits(Pool() + "," + Pool()), Now));
        Assert.Throws<InvalidDataException>(() => WorkBuddyCreditsDecoder.Decode(Credits(Pool(), "[\"2000\"]"), Now));
        Assert.Throws<InvalidDataException>(() => WorkBuddyCreditsDecoder.Decode(Credits(Pool(), "[\"987.75\",\"987.75\"]"), Now));
    }
    [Fact] public void WorkBuddyExcludesExpiredAndUnavailablePools()
    {
        var expired = Pool("0", "1000", "expired", expires: Now.AddMinutes(-1).ToUnixTimeMilliseconds().ToString());
        var unavailable = Pool("0", "1000", "disabled", "unavailable");
        var value = WorkBuddyCreditsDecoder.Decode(Credits(Pool() + "," + expired + "," + unavailable), Now); Assert.Equal(987.75m, value.Card.Credits);
    }
    [Theory] [InlineData("1795000000000.0")] [InlineData("1.795e12")]
    public void WorkBuddyAcceptsExactWebViewNumericDateNotation(string epoch)
    {
        var value = WorkBuddyCreditsDecoder.Decode(Credits(Pool(expires: epoch)), Now);
        Assert.Equal(987.75m, value.Card.Credits);
    }
    [Theory] [InlineData("1795000000000.5")] [InlineData("-1")] [InlineData("253402300800000")]
    public void WorkBuddyRejectsFractionalOrOutOfRangeDates(string epoch) =>
        Assert.Throws<InvalidDataException>(() => WorkBuddyCreditsDecoder.Decode(Credits(Pool(expires: epoch)), Now));
    [Theory]
    [InlineData("http://www.workbuddy.cn/profile/plans-usage")]
    [InlineData("https://www.workbuddy.cn.evil.test/profile/plans-usage")]
    [InlineData("https://www.workbuddy.cn/profile/plans-usage?x=1")]
    [InlineData("https://www.workbuddy.cn/profile/plans-usage#x")]
    [InlineData("https://www.workbuddy.cn:444/profile/plans-usage")]
    [InlineData("https://user@www.workbuddy.cn/profile/plans-usage")]
    public void WorkBuddyOnlyExtractsExactOfficialPage(string uri) => Assert.False(WorkBuddyCreditsDecoder.IsUsagePage(new(uri)));
    [Fact] public void WorkBuddyOfficialPageAllowed() => Assert.True(WorkBuddyCreditsDecoder.IsUsagePage(new("https://www.workbuddy.cn/profile/plans-usage")));
    [Theory] [InlineData(132000, "132k")] [InlineData(467116200, "467.1M")] [InlineData(1473789200, "1.47B")] [InlineData(0, "0")]
    public void TokenChartUnitsRemainReadable(double tokens, string text) => Assert.Equal(text, AUV.Windows.App.MainViewModel.CompactTokens(tokens));
    [Fact] public void SharedAdmissionUpdatesSelectedProviderBindings()
    {
        var vm = new AUV.Windows.App.MainViewModel(false, new());
        var current = vm.Shell.Agents[0]; var replacement = CodexUsageDecoder.Decode(Account, Json("""{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080}}}"""), default, Now);
        vm.Shell.ReplaceAdmittedPresentation(vm.Shell.Agents.Select(a => a.Id == "codex" ? replacement : a).ToArray());
        Assert.Same(replacement.Card, vm.SelectedCard); Assert.Equal("80%", vm.PrimaryValue); Assert.Empty(vm.Mode); Assert.NotSame(current, vm.Shell.SelectedAgent);
        Assert.True(vm.HasQuotaAgents); Assert.Same(replacement, Assert.Single(vm.QuotaAgents));
    }
}
