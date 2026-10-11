using AUV.Windows.App;
using AUV.Windows.Core;
namespace AUV.Windows.Tests;
public sealed class ViewModelTests
{
    [Fact] public void CopyRequiresGenerationAndDraftChangesInvalidateIt()
    {
        var vm = new MainViewModel(false, new()); string? copied = null; vm.CopyText = s => copied = s;
        Assert.False(vm.CopyCommand.CanExecute(null)); vm.GenerateCommand.Execute(null);
        Assert.True(vm.CopyCommand.CanExecute(null)); vm.CopyCommand.Execute(null); Assert.Equal(vm.Generated, copied);
        vm.Roles[0].Effort = "ultra"; Assert.Empty(vm.Generated); Assert.False(vm.CopyCommand.CanExecute(null));
    }
    [Fact] public void ReturningToAuvPreservesDetailAndNotifiesMetricBindings()
    {
        var vm = new MainViewModel(true, new()); var changes = new List<string?>(); vm.PropertyChanged += (_, e) => changes.Add(e.PropertyName);
        vm.Shell.SelectedAgent = vm.Shell.Agents[1]; var quota = vm.WeeklyRemaining;
        vm.Shell.Section = "ThreadOS"; vm.Shell.Section = "AUV";
        Assert.Equal("Claude", vm.Shell.SelectedAgent.Name); Assert.Equal("43% remaining", quota); Assert.Contains(nameof(vm.WeekTokens), changes);
    }
    [Fact] public void UnavailableAgentClearsOtherProvidersMetrics()
    {
        var vm = new MainViewModel(true, new()); Assert.True(vm.HasChart); vm.Shell.SelectedAgent = vm.Shell.Agents[2];
        Assert.False(vm.HasChart); Assert.Equal("—", vm.WeekTokens); Assert.Equal("—", vm.LocalCost); Assert.Equal("Unknown", vm.WeeklyRemaining);
    }
    [Fact] public void RestoredThreadOsDraftUsesCatalogSpecificOptions()
    {
        var vm = new MainViewModel(false, new() { Roles = new() { ["leader"] = new("gpt-6.1-sol", "ultra") }, ActiveSection = "ThreadOS", SelectedAgent = "antigravity" });
        Assert.Equal("ultra", vm.Roles[0].Effort); Assert.Equal("ThreadOS", vm.Shell.Section); Assert.Equal("antigravity", vm.Shell.SelectedAgent.Id);
        vm.Roles[0].Model = "gpt-6-luna"; Assert.Equal("medium", vm.Roles[0].Effort); Assert.DoesNotContain("ultra", vm.Roles[0].Efforts);
    }
    [Fact] public void InstructionCannotCarryProjectPathsOrDispatchFromApp()
    {
        var vm = new MainViewModel(false, new()); vm.GenerateCommand.Execute(null);
        Assert.Contains("\"scope\":\"receiving_leader_bound_root\"", vm.Generated);
        Assert.DoesNotContain("Y:", vm.Generated); Assert.DoesNotContain("project", vm.Generated);
    }
    [Fact] public void NullAndInvalidPersistedRoleValuesAreDiscarded()
    {
        var settings = new PreviewSettings { Roles = new() { ["leader"] = new(null!, "high"), ["qa"] = new("bad", "ultra"), ["unknown"] = new("gpt-6-sol", "high") } };
        settings.Normalize(new()); Assert.Empty(settings.Roles);
    }
}
