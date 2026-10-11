using System.Globalization;
using AUV.Windows.App;
using AUV.Windows.Core;

namespace AUV.Windows.Tests;

public sealed class VisibilityRefinementTests
{
    private static AllowanceCard Quota(decimal balance = 9600) => new("workbuddy", "WorkBuddy", "W", null,
        AllowanceKind.Credits, null, balance, "Credits", "Fixture", "Now", ConnectionState.Connected);

    [Theory]
    [InlineData(ConnectionState.Connected, true)] [InlineData(ConnectionState.Unavailable, false)]
    [InlineData(ConnectionState.Disconnected, false)] [InlineData(ConnectionState.Reconnecting, false)]
    [InlineData(ConnectionState.Failed, false)] [InlineData(ConnectionState.Stale, false)]
    public void VisibilityRequiresConnectedData(ConnectionState state, bool visible) => Assert.Equal(visible, (Quota() with { Connection = state }).HasDisplayableQuota);

    [Fact] public void StaleFlagAndUnavailableKindHideQuotasButZeroRemainsValid()
    {
        Assert.False((Quota() with { IsStale = true }).HasDisplayableQuota);
        Assert.False(new AllowanceCard("codex", "Codex", "C", null, AllowanceKind.Unavailable, null, null, "", "", "", ConnectionState.Connected).HasDisplayableQuota);
        Assert.True(Quota(0).HasDisplayableQuota);
        Assert.True(new AllowanceCard("codex", "Codex", "C", null, AllowanceKind.Percentage, 0, null, "", "", "", ConnectionState.Connected).HasDisplayableQuota);
    }

    [Theory]
    [InlineData("0", "0")] [InlineData("0.01", "<0.1")] [InlineData("0.19", "0.1")]
    [InlineData("999", "999")] [InlineData("999.99", "999")]
    [InlineData("1000", "1k")] [InlineData("1500", "1.5k")] [InlineData("9600", "9.6k")]
    [InlineData("9900", "9.9k")] [InlineData("9999", "9.9k")]
    [InlineData("10000", "10k")] [InlineData("14000", "14k")] [InlineData("99000", "99k")]
    [InlineData("999999", "999k")] [InlineData("1000000", "1M")] [InlineData("1300000", "1.3M")]
    [InlineData("999999999999.99", "999B")] [InlineData("79228162514264337593543950335", "7e28")]
    public void CompactCreditsFitRequestedExamplesAndLength(string amount, string expected)
    {
        var value = decimal.Parse(amount, CultureInfo.InvariantCulture);
        Assert.Equal(expected, CompactCredits.Format(value)); Assert.InRange(expected.Length, 1, 4);
    }

    [Fact] public void CompactLabelsDoNotOverstateOrChangeExactBalances()
    {
        foreach (var value in new[] { 999.99m, 1499.99m, 9999.99m, 14999.99m, 999999.99m, 1399999.99m })
        {
            var label = CompactCredits.Format(value); var suffix = label[^1];
            var multiplier = suffix switch { 'k' => 1000m, 'M' => 1000000m, _ => 1m };
            var represented = decimal.Parse(multiplier == 1 ? label : label[..^1], CultureInfo.InvariantCulture) * multiplier;
            Assert.True(represented <= value);
        }
        var card = Quota(9600); Assert.Equal("9.6k", card.MinimalistValue); Assert.Equal("9,600 Credits", card.Value);
        Assert.Contains("9,600 Credits", card.Description); Assert.Equal(9600m, card.Credits); Assert.Null(card.FillFraction);
        Assert.Throws<ArgumentOutOfRangeException>(() => CompactCredits.Format(-1));
    }

    [Fact] public void AdmissionAndWithdrawalNotifyQuotaListsWithoutRemovingConnectionRoutes()
    {
        var model = new MainViewModel(false, new()); var changes = new List<string?>();
        model.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        void Admit(AllowanceCard card) => model.Shell.ReplaceAdmittedPresentation(model.Shell.Agents.Select(a => a.Id == card.Id ?
            new AgentPresentation(a.Id, a.Name, a.Monogram, UsageSnapshot.Unknown, false, card) : a).ToArray());
        Assert.Empty(model.QuotaAgents); Assert.Equal(4, model.Shell.Agents.Length); Assert.False(model.HasData);
        Admit(Quota(0)); Assert.Equal("workbuddy", Assert.Single(model.QuotaAgents).Id);
        Assert.Contains(nameof(model.QuotaAgents), changes); Assert.Contains(nameof(model.HasQuotaAgents), changes);
        Admit(Quota(0) with { IsStale = true }); Assert.Empty(model.QuotaAgents); Assert.Equal(4, model.Shell.Agents.Length);
    }

    [Fact] public void MetricsAreIndependentlyAvailableAndDoNotShowUnknownSecondaryOrChart()
    {
        var model = new MainViewModel(false, new());
        var card = Quota(); var tokensOnly = new AgentPresentation("workbuddy", "WorkBuddy", "W",
            new(null, null, 0, 42, null, []), false, card with { Connection = ConnectionState.Disconnected }, "Secondary", "Unavailable");
        model.Shell.ReplaceAdmittedPresentation([tokensOnly]);
        Assert.False(model.HasUsage); Assert.False(model.HasPercentBar); Assert.False(model.HasSecondary);
        Assert.True(model.HasWeekTokens); Assert.True(model.HasLifetimeTokens); Assert.True(model.HasData);
        Assert.False(model.HasChart); Assert.False(model.HasLocalCost);
    }
}
