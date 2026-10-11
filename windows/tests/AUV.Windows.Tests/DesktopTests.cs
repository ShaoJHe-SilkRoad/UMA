using AUV.Windows.App;
using AUV.Windows.Core;
namespace AUV.Windows.Tests;
public sealed class DesktopTests
{
    [Fact] public void CpuFirstSampleAndNoElapsedTimeAreUnknown()
    { Assert.Null(PerformanceMath.CpuPercent(null, new(10, 20, 10))); Assert.Null(PerformanceMath.CpuPercent(new(10, 20, 10), new(10, 20, 10))); }
    [Fact] public void CpuSubtractsIdleAlreadyIncludedInKernel()
    { Assert.Equal(60d, PerformanceMath.CpuPercent(new(100, 200, 100), new(140, 260, 140))); }
    [Fact] public void CpuInvalidOrResetCountersAreUnknown()
    { Assert.Null(PerformanceMath.CpuPercent(new(100, 200, 100), new(99, 200, 100))); Assert.Null(PerformanceMath.CpuPercent(new(0, 0, 0), new(300, 100, 100))); Assert.Null(PerformanceMath.CpuPercent(new(0, 0, 0), new(0, ulong.MaxValue, 1))); }
    [Fact] public void MemoryUnknownIsNeverZeroAndAvailableCannotExceedTotal()
    { Assert.Null(PerformanceSnapshot.Unknown.MemoryPercent); Assert.Null(new PerformanceSnapshot(null, 100, null, default).MemoryPercent); Assert.Null(new PerformanceSnapshot(null, 100, 101, default).MemoryPercent); Assert.Equal(25d, new PerformanceSnapshot(null, 100, 75, default).MemoryPercent); }
    [Fact] public void PlacementKeepsNegativeMonitorCoordinatesAndAvoidsTaskbar()
    {
        var area = new DesktopArea(-1920, 0, 1920, 1040);
        Assert.Equal(new DesktopPoint(-512, 900), DesktopPlacement.BottomRight(area, 500, 128));
        Assert.Equal(new DesktopPoint(-1920, 912), DesktopPlacement.Clamp(new(-5000, 2000), area, 500, 128));
        Assert.Equal(new DesktopPoint(-1920, 0), DesktopPlacement.Clamp(new(1000, 2000), area, 4000, 2000));
    }
    [Fact] public void DesktopPreferenceRoundTripIsIndependentOfMainWindowGeometry()
    {
        var path = Path.Combine(Path.GetTempPath(), "auv-desktop-" + Guid.NewGuid() + ".json");
        try
        {
            var store = new SettingsStore(path); Assert.True(store.Save(new() { Desktop = new() { WidgetVisible = true, AlwaysOnTop = false, CloseToTray = false, Left = -600, Top = 200 } }));
            var restored = store.Load(new()); Assert.True(restored.Desktop.WidgetVisible); Assert.False(restored.Desktop.AlwaysOnTop); Assert.False(restored.Desktop.CloseToTray); Assert.Equal(-600, restored.Desktop.Left); Assert.Equal(1040, restored.Geometry.Width);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
    [Fact] public void OldSettingsWithoutDesktopPreferencesRemainValid()
    { var settings = new PreviewSettings { Desktop = null! }; settings.Normalize(new()); Assert.NotNull(settings.Desktop); Assert.True(settings.Desktop.AlwaysOnTop); Assert.False(settings.Desktop.WidgetVisible); }
    [Fact] public void LiveSystemCountersAreSaneAndDoNotPopulateAccountUsage()
    {
        var monitor = new PerformanceMonitor(); var sample = monitor.Sample(); Assert.Null(sample.CpuPercent); Assert.True(sample.TotalMemory > 0); Assert.True(sample.AvailableMemory <= sample.TotalMemory); Assert.InRange(sample.MemoryPercent!.Value, 0, 100);
        var vm = new MainViewModel(false, new()); Assert.Equal("Unknown", vm.WeeklyRemaining); Assert.False(vm.HasUsage);
    }
}
