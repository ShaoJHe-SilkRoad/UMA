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
            var store = new SettingsStore(path); Assert.True(store.Save(new() { Desktop = new() { WidgetVisible = true, AlwaysOnTop = false, CloseToTray = false, HideTrayIcon = true, Left = -600, Top = 200 } }));
            var restored = store.Load(new()); Assert.True(restored.Desktop.WidgetVisible); Assert.False(restored.Desktop.AlwaysOnTop); Assert.False(restored.Desktop.CloseToTray); Assert.True(restored.Desktop.HideTrayIcon); Assert.Equal(-600, restored.Desktop.Left); Assert.Equal(1040, restored.Geometry.Width);
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
    [Fact] public void OldSettingsWithoutDesktopPreferencesRemainValid()
    { var settings = new PreviewSettings { Desktop = null! }; settings.Normalize(new()); Assert.NotNull(settings.Desktop); Assert.True(settings.Desktop.AlwaysOnTop); Assert.False(settings.Desktop.WidgetVisible); Assert.False(settings.Desktop.HideTrayIcon); }
    [Fact] public void LiveSystemCountersAreSaneAndDoNotPopulateAccountUsage()
    {
        var monitor = new PerformanceMonitor(); var sample = monitor.Sample(); Assert.Null(sample.CpuPercent); Assert.True(sample.TotalMemory > 0); Assert.True(sample.AvailableMemory <= sample.TotalMemory); Assert.InRange(sample.MemoryPercent!.Value, 0, 100);
        var vm = new MainViewModel(false, new()); Assert.Equal("Unknown", vm.WeeklyRemaining); Assert.False(vm.HasUsage);
    }
    // ---- 0.18.7: Desktop Wizard that would not open, tray panel clicks, minimized main window ----
    [Fact] public void ShowingTheWizardTurnsADisabledWizardOn()
    {
        // The reported settings: disabled (from Settings or the Wizard's own menu). Every Show control used to do nothing.
        var desktop = new DesktopPreferences { Enabled = false, WidgetVisible = false };
        Assert.False(desktop.WidgetRequested);
        desktop.RequestWidget(true); Assert.True(desktop.Enabled); Assert.True(desktop.WidgetVisible); Assert.True(desktop.WidgetRequested);
        desktop.RequestWidget(false); Assert.True(desktop.Enabled); Assert.False(desktop.WidgetRequested);
    }
    [Fact] public void DisabledButMarkedVisibleStaysHiddenUntilAskedThenOnePressShowsIt()
    {
        var desktop = new DesktopPreferences { Enabled = false, WidgetVisible = true };
        Assert.False(desktop.WidgetRequested); // start-up does not turn it on by itself
        desktop.RequestWidget(!desktop.WidgetRequested); // what the Show/Hide control does
        Assert.True(desktop.WidgetRequested);
    }
    [Fact] public void ReportedSettingsFileStillLoadsAndNewFieldHasADefault()
    {
        var path = Path.Combine(Path.GetTempPath(), "auv-desktop-" + Guid.NewGuid() + ".json");
        try
        {
            // Desktop block as written by 0.18.5/0.18.6 (no TrayHintShown).
            File.WriteAllText(path, """{"Version":1,"Geometry":{"Width":1097.1,"Height":500,"Left":480,"Top":222.8,"Maximized":true},"Desktop":{"Enabled":false,"WidgetVisible":true,"AlwaysOnTop":true,"CloseToTray":true,"HideTrayIcon":false,"Left":2055.4,"Top":492,"Density":1,"ShowStatus":true,"ShowFill":true}}""");
            var store = new SettingsStore(path); var settings = store.Load(new());
            Assert.Null(store.LastError); Assert.False(settings.Desktop.Enabled); Assert.True(settings.Desktop.WidgetVisible); Assert.False(settings.Desktop.WidgetRequested);
            Assert.False(settings.Desktop.TrayHintShown); Assert.True(settings.Geometry.Maximized); Assert.Equal(2055.4, settings.Desktop.Left);
            Assert.True(settings.Desktop.TakeTrayHint()); Assert.False(settings.Desktop.TakeTrayHint());
            Assert.True(store.Save(settings)); var again = store.Load(new());
            Assert.True(again.Desktop.TrayHintShown); Assert.DoesNotContain("WidgetRequested", File.ReadAllText(path));
        }
        finally { if (File.Exists(path)) File.Delete(path); }
    }
    private static readonly DateTimeOffset T0 = new(2026, 11, 14, 4, 0, 0, TimeSpan.Zero);
    private static DateTimeOffset At(int milliseconds) => T0.AddMilliseconds(milliseconds);
    private static TrayPanelGate Gate() => new(TimeSpan.FromMilliseconds(500), TimeSpan.FromMilliseconds(400));
    [Fact] public void TrayClickOpensThenTheClickThatTookFocusLeavesThePanelClosed()
    {
        var gate = Gate();
        Assert.Equal(TrayPanelAction.Show, gate.TrayClick(At(0), false));
        // Second click 3 s later: mouse-down on the taskbar hides the panel, then the click is reported.
        gate.Dismissed(At(3000));
        Assert.Equal(TrayPanelAction.None, gate.TrayClick(At(3090), false)); // used to reopen
        Assert.Equal(TrayPanelAction.Show, gate.TrayClick(At(6000), false));
    }
    [Fact] public void DoubleClickAndDuplicateKeyboardSelectLeaveThePanelOpen()
    {
        var gate = Gate();
        Assert.Equal(TrayPanelAction.Show, gate.TrayClick(At(0), false));
        gate.Dismissed(At(150)); // the second mouse-down took the panel's focus
        Assert.Equal(TrayPanelAction.Show, gate.TrayClick(At(220), false)); // used to end hidden
        var keys = Gate();
        Assert.Equal(TrayPanelAction.Show, keys.TrayClick(At(0), false));
        Assert.Equal(TrayPanelAction.None, keys.TrayClick(At(5), true)); // Enter is reported twice: used to open then close
    }
    [Fact] public void TrayClickHidesAPanelThatKeptFocusElsewhereAndDismissalExpires()
    {
        var gate = Gate();
        Assert.Equal(TrayPanelAction.Show, gate.TrayClick(At(0), false));
        Assert.Equal(TrayPanelAction.Hide, gate.TrayClick(At(2000), true)); // panel never had focus, so it is still open
        gate.Dismissed(At(5000));
        Assert.Equal(TrayPanelAction.Show, gate.TrayClick(At(5400), false)); // 400 ms later is a new request
        gate.Dismissed(At(9000));
        Assert.Equal(TrayPanelAction.Show, gate.TrayClick(At(8000), false)); // a clock that went backwards never blocks opening
    }
    [Fact] public void PanelButtonClosesAnOpenPanelInsteadOfReopeningIt()
    {
        var gate = Gate();
        Assert.Equal(TrayPanelAction.Show, gate.Toggle(At(0), false));
        gate.Dismissed(At(4000)); // pressing the button in the main window took the panel's focus
        Assert.Equal(TrayPanelAction.None, gate.Toggle(At(4080), false));
        Assert.Equal(TrayPanelAction.Show, gate.Toggle(At(4200), false)); // one dismissal blocks one press only
        Assert.Equal(TrayPanelAction.Hide, gate.Toggle(At(9000), true));
    }
    [Fact] public void MinimizedWindowIsSavedAsItWasBeforeMinimizing()
    {
        Assert.True(WindowStatePolicy.SaveAsMaximized(maximized: true, minimized: false, maximizedBeforeMinimize: false));
        Assert.True(WindowStatePolicy.SaveAsMaximized(false, true, true)); // used to be saved as not maximized
        Assert.False(WindowStatePolicy.SaveAsMaximized(false, true, false));
        Assert.False(WindowStatePolicy.SaveAsMaximized(false, false, true));
    }
}
