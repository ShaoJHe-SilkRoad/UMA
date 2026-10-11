namespace AUV.Windows.Core;

public sealed class DesktopPreferences
{
    public bool Enabled { get; set; } = true;
    public bool WidgetVisible { get; set; }
    public bool AlwaysOnTop { get; set; } = true;
    public bool CloseToTray { get; set; } = true;
    public double? Left { get; set; }
    public double? Top { get; set; }
    public WizardDensity Density { get; set; } = WizardDensity.Automatic;
    public bool ShowStatus { get; set; } = true;
    public bool ShowFill { get; set; } = true;
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
