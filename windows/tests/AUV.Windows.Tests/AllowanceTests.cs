using AUV.Windows.Core;
namespace AUV.Windows.Tests;
public sealed class AllowanceTests
{
    private static AllowanceCard Card(AllowanceKind kind, double? percent = null, decimal? credits = null, string id = "codex", string? plan = "Pro") =>
        new(id, "Provider", "P", plan, kind, percent, credits, "7-day", "Fixture source", "Fixture freshness", ConnectionState.Connected);
    [Theory]
    [InlineData(0)] [InlineData(1)] [InlineData(9)] [InlineData(10)] [InlineData(19)] [InlineData(20)] [InlineData(50)] [InlineData(99)] [InlineData(100)] [InlineData(9.5)]
    public void RemainingFillHasNoMinimumSegment(double value)
    { var card = Card(AllowanceKind.Percentage, value); Assert.Equal(value / 100, card.FillFraction); Assert.Equal(AllowanceCard.FormatPercent(value), card.Value); }
    [Theory] [InlineData(-1)] [InlineData(101)] [InlineData(double.NaN)] [InlineData(double.PositiveInfinity)]
    public void InvalidInputIsProjectedBeforeRendering(double value)
    { var card = Card(AllowanceKind.Estimated, value); Assert.Equal(AllowanceKind.Unavailable, card.Kind); Assert.Equal("—", card.Value); Assert.Null(card.FillFraction); Assert.Equal(QuotaSeverity.Neutral, card.Severity); }
    [Theory]
    [InlineData("codex", "Pro", 9.9, QuotaSeverity.Low)] [InlineData("codex", "Pro", 10, QuotaSeverity.Normal)]
    [InlineData("codex", "Plus", 19.9, QuotaSeverity.Low)] [InlineData("codex", "Plus", 20, QuotaSeverity.Normal)]
    [InlineData("claude", "Max", 9.9, QuotaSeverity.Low)] [InlineData("claude", "Max", 10, QuotaSeverity.Normal)]
    [InlineData("claude", "Pro", 19.9, QuotaSeverity.Low)] [InlineData("claude", "Pro", 20, QuotaSeverity.Normal)]
    [InlineData("claude", "Unknown", 1, QuotaSeverity.Neutral)] [InlineData("other", "Pro", 1, QuotaSeverity.Neutral)]
    [InlineData("codex.account", " PRO ", 10, QuotaSeverity.Normal)]
    public void PolicyUsesExactAdmittedPlansAndStrictBoundaries(string provider, string plan, double value, QuotaSeverity expected)
    { var card = Card(AllowanceKind.Percentage, value, id: provider, plan: plan); Assert.Equal(expected, card.Severity); Assert.Equal(ConnectionState.Connected, card.Connection); }
    [Fact] public void NativeCreditsNeverGetAPercentDenominator()
    {
        var below = Card(AllowanceKind.Credits, 100, 499, "workbuddy"); var boundary = Card(AllowanceKind.Credits, 0, 500, "workbuddy");
        Assert.Equal(QuotaSeverity.Low, below.Severity); Assert.Equal(QuotaSeverity.Normal, boundary.Severity);
        Assert.Null(below.Percent); Assert.Null(boundary.FillFraction); Assert.Equal("500 Credits", boundary.Value);
        Assert.Equal(QuotaSeverity.Neutral, Card(AllowanceKind.Percentage, 1, id: "workbuddy").Severity);
    }
    [Fact] public void UnlimitedUnknownEstimatedAndStaleKeepTheirMeanings()
    {
        Assert.Null(Card(AllowanceKind.Unlimited, 100).FillFraction); Assert.Equal("∞", Card(AllowanceKind.Unlimited).Value);
        Assert.Equal("—", Card(AllowanceKind.Unavailable).Value);
        var estimated = Card(AllowanceKind.Estimated, 19.5) with { IsStale = true, Connection = ConnectionState.Stale };
        Assert.Equal("≈19.5%", estimated.Value); Assert.Equal(.195, estimated.FillFraction); Assert.Contains("retained stale", estimated.Description);
        Assert.Contains("Fixture source", estimated.Description); Assert.Contains("Fixture freshness", estimated.Description);
    }
    [Theory] [InlineData(WizardDensity.Automatic)] [InlineData(WizardDensity.Regular)] [InlineData(WizardDensity.Minimalist)]
    public void FiveForcesMinimalistWithoutChangingPreference(WizardDensity preference)
    {
        var settings = new DesktopPreferences { Density = preference };
        foreach (var count in new[] { 0, 1, 2, 4, 5, 4 }) Assert.Equal(count >= 5 || preference == WizardDensity.Minimalist ? WizardDensity.Minimalist : WizardDensity.Regular, WizardPolicy.Resolve(settings.Density, count));
        Assert.Equal(preference, settings.Density);
    }
    [Fact] public void RegularStackHasNoHostMargin()
    { Assert.Equal(0, WizardPolicy.StackHeight(0, 48)); Assert.Equal(48, WizardPolicy.StackHeight(1, 48)); Assert.Equal(99.2, WizardPolicy.StackHeight(2, 48)); Assert.Equal(201.6, WizardPolicy.StackHeight(4, 48)); }
    [Fact] public void InputThresholdDistinguishesAClickFromDragging()
    { Assert.False(WizardPolicy.IsDrag(3, -3, 4, 4)); Assert.True(WizardPolicy.IsDrag(4, 0, 4, 4)); Assert.True(WizardPolicy.IsDrag(0, -4, 4, 4)); }
    [Fact] public void MainAndAuxiliarySurfacesReceiveTheSameImmutableCard()
    {
        var vm = new AUV.Windows.App.MainViewModel(true, new()); var card = vm.Shell.SelectedAgent.Card;
        Assert.Same(card, vm.SelectedCard); Assert.Equal(card.Value, vm.PrimaryValue); Assert.Equal(card.Source, vm.Source); Assert.Equal(card.Freshness, vm.Updated);
        vm.Shell.Section = "ThreadOS"; vm.Shell.Section = "Sectorium"; vm.Shell.Section = "AUV"; Assert.Same(card, vm.SelectedCard);
        Assert.Equal(card, vm.Shell.Agents.Single(a => a.Id == card.Id).Card);
    }
    [Fact] public void NewPreferencesPreserveIndependentVisibilityAndEnabledState()
    {
        var path = Path.Combine(Path.GetTempPath(), "auv-product-" + Guid.NewGuid() + ".json");
        try
        {
            var store = new SettingsStore(path); Assert.True(store.Save(new() { Theme = "System", Desktop = new() { Enabled = false, WidgetVisible = true, Density = WizardDensity.Minimalist, ShowFill = false, ShowStatus = false, AlwaysOnTop = false } }));
            var settings = store.Load(new()); Assert.Equal("System", settings.Theme); Assert.False(settings.Desktop.Enabled); Assert.True(settings.Desktop.WidgetVisible); Assert.Equal(WizardDensity.Minimalist, settings.Desktop.Density); Assert.False(settings.Desktop.ShowFill); Assert.False(settings.Desktop.ShowStatus);
        }
        finally { File.Delete(path); }
    }
    [Fact] public void SectoriumFixtureSurvivesNavigationAndCannotEnableMutation()
    {
        var vm = new AUV.Windows.App.MainViewModel(true, new()); vm.Storage.FixtureError = true;
        vm.Shell.Section = "Sectorium"; vm.Shell.Section = "AUV"; vm.Shell.Section = "Sectorium";
        Assert.True(vm.Storage.FixtureError); Assert.Contains("DEMO error", vm.Storage.Feedback); Assert.False(SectoriumPreview.CanMutate);
        var normal = new SectoriumState(false); normal.FixtureError = true; Assert.False(normal.FixtureError); Assert.DoesNotContain("DEMO", normal.PhysicalDrive);
    }
}
