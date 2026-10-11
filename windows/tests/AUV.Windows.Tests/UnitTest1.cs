using System.Text.Json;
using AUV.Windows.Core;
namespace AUV.Windows.Tests;
public sealed class PresentationTests
{
    private readonly ModelCatalog catalog = new();
    [Fact] public void CatalogIsExactVersionAndLunaDoesNotOfferUltra()
    { Assert.Equal("sol-luna-ultra-20261010.1", catalog.Revision); Assert.Equal(6, catalog.Models.Count); Assert.False(catalog.Allows("gpt-6-luna", "ultra")); Assert.True(catalog.Allows("gpt-6.1-sol", "ultra")); }
    [Fact] public void SwitchingPagesKeepsSelectedAgent()
    { var shell = new ShellState(false); shell.SelectedAgent = shell.Agents[1]; shell.Section = "ThreadOS"; shell.Section = "Sectorium"; shell.Section = "AUV"; Assert.Equal("claude", shell.SelectedAgent.Id); shell.Section = "invalid"; Assert.Equal("AUV", shell.Section); }
    [Fact] public void UnsupportedSavedAgentAndSectionHaveSafeFallbacks()
    { var shell = new ShellState(false, "unknown", "bad"); Assert.Equal("codex", shell.SelectedAgent.Id); Assert.Equal("AUV", shell.Section); }
    [Fact] public void NormalModeContainsNoFabricatedAccountData()
    { foreach (var agent in AgentPresentation.Create(false)) { Assert.False(agent.IsDemo); Assert.False(agent.HasUsage); Assert.Null(agent.Usage.AccountWeek); Assert.Empty(agent.Usage.Days); Assert.Equal("Unknown", agent.Remaining); } }
    [Theory] [InlineData(-1d)] [InlineData(101d)] [InlineData(double.NaN)] [InlineData(double.PositiveInfinity)]
    public void InvalidRemainingIsUnknown(double value) => Assert.Equal("Unknown", UsageSnapshot.RemainingText(value));
    [Fact] public void RemainingDoesNotMeanConsumed()
    { Assert.Equal("68% remaining", UsageSnapshot.RemainingText(68)); Assert.Equal("0% remaining", UsageSnapshot.RemainingText(0)); Assert.Equal("Unknown", UsageSnapshot.RemainingText(null)); Assert.Equal("—", UsageSnapshot.TokensText(-1)); }
    [Fact] public void DemoFixtureIsExplicitAndSeparateByProvider()
    { var agents = AgentPresentation.Create(true); Assert.True(agents[0].IsDemo); Assert.True(agents[1].IsDemo); Assert.NotEqual(agents[0].Usage.AccountWeek, agents[1].Usage.AccountWeek); Assert.Equal(7, agents[0].Usage.Days.Count); Assert.False(agents[2].IsDemo); }
    [Fact] public void ModelChangeRemovesUnsupportedUltra()
    { var role = new RoleDraft(catalog, "leader", "Leader", "", "gpt-6.1-sol", "ultra"); role.Model = "gpt-6-luna"; Assert.DoesNotContain("ultra", role.Efforts); Assert.Equal("medium", role.Effort); role.Effort = "ultra"; Assert.Equal("medium", role.Effort); }
    [Fact] public void GoldenInstructionMatchesMacBytesExactly()
    {
        var text = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "uma015-current-command-baseline.json")).Trim();
        using var json = JsonDocument.Parse(text);
        var roles = json.RootElement.GetProperty("roles").EnumerateObject().ToDictionary(r => r.Name, r => new RoleSelection(r.Value.GetProperty("model").GetString()!, r.Value.GetProperty("thinking").GetString()!));
        Assert.Equal(text, LeaderInstruction.Generate(catalog, roles));
    }
    [Fact] public void GenerationRejectsMissingRolesAndUnsupportedCombinations()
    {
        Assert.Throws<ArgumentException>(() => LeaderInstruction.Generate(catalog, new Dictionary<string, RoleSelection>()));
        var roles = LeaderInstruction.Roles.ToDictionary(r => r, _ => new RoleSelection("gpt-6-luna", "ultra"));
        Assert.Throws<ArgumentException>(() => LeaderInstruction.Generate(catalog, roles));
    }
    [Fact] public void SectoriumHasNoEnabledMutationPolicy() { Assert.False(SectoriumPreview.CanMutate); Assert.Equal(5, SectoriumPreview.UnavailableActions.Length); }
    [Fact] public void SettingsRoundTripRetainsAgentSectionAndDraft()
    {
        WithSettingsPath(path => { var store = new SettingsStore(path); var settings = new PreviewSettings { SelectedAgent = "claude", ActiveSection = "ThreadOS", Theme = "Light", Roles = new() { ["leader"] = new("gpt-6.1-sol", "ultra") }, Geometry = new() { Width = 820, Height = 650, Left = 20, Top = 30 } }; Assert.True(store.Save(settings)); var restored = store.Load(catalog); Assert.Equal("claude", restored.SelectedAgent); Assert.Equal("ThreadOS", restored.ActiveSection); Assert.Equal("Light", restored.Theme); Assert.Equal("ultra", restored.Roles["leader"].Effort); Assert.Equal(820, restored.Geometry.Width); });
    }
    [Fact] public void CorruptSettingsHaveVisibleErrorAndDefaults()
    { WithSettingsPath(path => { File.WriteAllText(path, "{broken"); var store = new SettingsStore(path); Assert.Equal("Dark", store.Load(catalog).Theme); Assert.NotNull(store.LastError); }); }
    [Fact] public void InvalidAndStaleSettingsAreNormalized()
    { var settings = new PreviewSettings { Theme = "bad", ActiveSection = "bad", SelectedAgent = "bad", CatalogRevision = "old", Roles = new() { ["leader"] = new("gpt-6.1-sol", "ultra") }, Geometry = new() { Width = double.NaN, Height = -1 } }; settings.Normalize(catalog); Assert.Equal("Dark", settings.Theme); Assert.Equal("AUV", settings.ActiveSection); Assert.Equal("codex", settings.SelectedAgent); Assert.Empty(settings.Roles); Assert.Equal(1040, settings.Geometry.Width); Assert.Equal(762, settings.Geometry.Height); }
    [Fact] public void SaveFailureIsReportedInsteadOfFalseSuccess()
    { WithSettingsPath(path => { Directory.CreateDirectory(path); var store = new SettingsStore(path); Assert.False(store.Save(new())); Assert.NotNull(store.LastError); }); }
    private static void WithSettingsPath(Action<string> run)
    { var directory = Path.Combine(Path.GetTempPath(), "AUV.Windows.Tests", Guid.NewGuid().ToString("N")); Directory.CreateDirectory(directory); try { run(Path.Combine(directory, "settings.json")); } finally { Directory.Delete(directory, true); } }
}
