namespace AUV.Windows.Core;

public sealed class DesktopPreferences
{
    public bool Enabled { get; set; } = true;
    public bool WidgetVisible { get; set; }
    public bool AlwaysOnTop { get; set; } = true;
    public bool CloseToTray { get; set; } = true;
    public bool HideTrayIcon { get; set; }
    public double? Left { get; set; }
    public double? Top { get; set; }
    public WizardDensity Density { get; set; } = WizardDensity.Automatic;
    public bool ShowStatus { get; set; } = true;
    public bool ShowFill { get; set; } = true;
    /// <summary>0.18.7: set once the "AUV is still running in the tray" notice has been shown. Absent in older files: false.</summary>
    public bool TrayHintShown { get; set; }
    /// <summary>The Wizard is on screen only when it is both enabled and asked for.</summary>
    [System.Text.Json.Serialization.JsonIgnore] public bool WidgetRequested => Enabled && WidgetVisible;
    /// <summary>
    /// 0.18.7: every "Show Desktop Wizard" control goes through here. Asking to show it also turns the feature on, so a
    /// Wizard that was disabled earlier (Settings or its own menu) no longer ignores the button. Hiding leaves Enabled alone.
    /// </summary>
    public void RequestWidget(bool visible) { if (visible) Enabled = true; WidgetVisible = visible; }
    /// <summary>True the first time only: the caller then shows the tray notice.</summary>
    public bool TakeTrayHint() { if (TrayHintShown) return false; TrayHintShown = true; return true; }
    public void Normalize()
    {
        if (!Enum.IsDefined(Density)) Density = WizardDensity.Automatic;
        if (Left is double x && !double.IsFinite(x)) Left = null;
        if (Top is double y && !double.IsFinite(y)) Top = null;
    }
}

public readonly record struct CpuTimes(ulong Idle, ulong Kernel, ulong User);
public sealed record PerformanceSnapshot(double? CpuPercent, ulong? TotalMemory, ulong? AvailableMemory, DateTimeOffset SampledAt)
{
    public double? MemoryPercent => TotalMemory is > 0 && AvailableMemory <= TotalMemory
        ? 100d * (TotalMemory.Value - AvailableMemory!.Value) / TotalMemory.Value : null;
    public static PerformanceSnapshot Unknown { get; } = new(null, null, null, DateTimeOffset.MinValue);
}

public static class PerformanceMath
{
    // GetSystemTimes kernel time includes idle. A baseline alone is not a measurement.
    public static double? CpuPercent(CpuTimes? previous, CpuTimes current)
    {
        if (previous is not CpuTimes before || current.Idle < before.Idle || current.Kernel < before.Kernel || current.User < before.User) return null;
        var kernel = current.Kernel - before.Kernel;
        var user = current.User - before.User;
        if (ulong.MaxValue - kernel < user) return null;
        var total = kernel + user;
        var idle = current.Idle - before.Idle;
        return total == 0 || idle > total ? null : 100d * (total - idle) / total;
    }
}

public readonly record struct DesktopArea(double Left, double Top, double Width, double Height);
public readonly record struct DesktopPoint(double X, double Y);
public static class DesktopPlacement
{
    public static DesktopPoint Clamp(DesktopPoint point, DesktopArea work, double width, double height) => new(
        Math.Clamp(point.X, work.Left, Math.Max(work.Left, work.Left + work.Width - width)),
        Math.Clamp(point.Y, work.Top, Math.Max(work.Top, work.Top + work.Height - height)));
    public static DesktopPoint BottomRight(DesktopArea work, double width, double height, double margin = 12) =>
        Clamp(new(work.Left + work.Width - width - margin, work.Top + work.Height - height - margin), work, width, height);
}

public enum TrayPanelAction { None, Show, Hide }
/// <summary>
/// 0.18.7: decides what a click on the tray icon (or the panel button) does to the Usage panel.
/// The panel hides itself when it loses focus, and pressing the mouse on the tray icon takes its focus away before the
/// click is reported. Without this, the click meant to close the panel opened it again, and a double click made it flash.
/// </summary>
public sealed class TrayPanelGate(TimeSpan repeat, TimeSpan reopen)
{
    private DateTimeOffset? lastClick, dismissed;
    /// <summary>The panel was open and hid because it lost focus.</summary>
    public void Dismissed(DateTimeOffset now) => dismissed = now;
    private bool JustDismissed(DateTimeOffset now) => dismissed is { } at && now >= at && now - at < reopen;
    /// <summary>A left click or keyboard selection on the tray icon.</summary>
    public TrayPanelAction TrayClick(DateTimeOffset now, bool panelVisible)
    {
        var second = lastClick is { } previous && now >= previous && now - previous < repeat;
        lastClick = now;
        // The second half of a double click (or the duplicate keyboard notification) leaves the panel open.
        if (second) { dismissed = null; return panelVisible ? TrayPanelAction.None : TrayPanelAction.Show; }
        return Toggle(now, panelVisible);
    }
    /// <summary>The main window's panel button, its shortcut or the tray menu.</summary>
    public TrayPanelAction Toggle(DateTimeOffset now, bool panelVisible)
    {
        if (panelVisible) return TrayPanelAction.Hide;
        // This same click already closed the panel by taking its focus: it stays closed.
        if (JustDismissed(now)) { dismissed = null; return TrayPanelAction.None; }
        return TrayPanelAction.Show;
    }
}
/// <summary>0.18.7: what to store and restore for a main window that is minimized.</summary>
public static class WindowStatePolicy
{
    /// <summary>A window minimized from maximized is still saved as maximized, so the next start (and Open AUV) brings it back that way.</summary>
    public static bool SaveAsMaximized(bool maximized, bool minimized, bool maximizedBeforeMinimize) => maximized || minimized && maximizedBeforeMinimize;
}
