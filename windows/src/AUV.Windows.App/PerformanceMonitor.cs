using System.Runtime.InteropServices;
using AUV.Windows.Core;

namespace AUV.Windows.App;

/// <summary>Read-only, aggregate system counters. No process/session enumeration or benchmark workload.</summary>
public sealed class PerformanceMonitor
{
    private CpuTimes? previous;
    public void Reset() => previous = null;
    public PerformanceSnapshot Sample()
    {
        double? cpu = null;
        if (GetSystemTimes(out var idle, out var kernel, out var user))
        {
            var current = new CpuTimes(idle.Value, kernel.Value, user.Value);
            cpu = PerformanceMath.CpuPercent(previous, current); previous = current;
        }
        else previous = null;
        var memory = new MemoryStatus { Length = (uint)Marshal.SizeOf<MemoryStatus>() };
        var available = GlobalMemoryStatusEx(ref memory);
        return new(cpu, available ? memory.TotalPhysical : null, available ? memory.AvailablePhysical : null, DateTimeOffset.Now);
    }
    [StructLayout(LayoutKind.Sequential)] private struct FileTime
    { public uint Low; public uint High; public readonly ulong Value => ((ulong)High << 32) | Low; }
    [StructLayout(LayoutKind.Sequential)] private struct MemoryStatus
    {
        public uint Length, MemoryLoad;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile, TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetSystemTimes(out FileTime idle, out FileTime kernel, out FileTime user);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
}

public sealed class PerformanceViewModel : Observable
{
    public PerformanceSnapshot Snapshot { get; private set; } = PerformanceSnapshot.Unknown;
    public string CpuText => Snapshot.CpuPercent is double value ? $"{value:0}%" : "—";
    public string MemoryText => Snapshot.MemoryPercent is double value ? $"{value:0}%" : "—";
    public string MemoryDetail => Snapshot.MemoryPercent != null ? $"{(Snapshot.TotalMemory!.Value - Snapshot.AvailableMemory!.Value) / 1073741824d:0.0} / {Snapshot.TotalMemory.Value / 1073741824d:0.0} GiB" : "Memory unavailable";
    public double CpuValue => Snapshot.CpuPercent ?? 0;
    public double MemoryValue => Snapshot.MemoryPercent ?? 0;
    public bool HasCpu => Snapshot.CpuPercent != null;
    public bool HasMemory => Snapshot.MemoryPercent != null;
    public string Updated => Snapshot.SampledAt == DateTimeOffset.MinValue ? "Waiting for system counters" : $"Live system counters · {Snapshot.SampledAt:HH:mm:ss} · 2 s";
    public void Update(PerformanceSnapshot snapshot)
    {
        Snapshot = snapshot;
        foreach (var name in new[] { nameof(Snapshot), nameof(CpuText), nameof(MemoryText), nameof(MemoryDetail), nameof(CpuValue), nameof(MemoryValue), nameof(HasCpu), nameof(HasMemory), nameof(Updated) }) Changed(name);
    }
}
