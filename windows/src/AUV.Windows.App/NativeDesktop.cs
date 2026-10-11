using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using AUV.Windows.Core;

namespace AUV.Windows.App;

internal static class NativeDesktop
{
    private delegate bool MonitorCallback(nint monitor, nint hdc, ref Rect bounds, nint data);
    [DllImport("user32.dll")] private static extern bool EnumDisplayMonitors(nint hdc, nint clip, MonitorCallback callback, nint data);
    public static IReadOnlyList<DesktopArea> MonitorWorkAreas()
    {
        var areas = new List<DesktopArea>();
        EnumDisplayMonitors(0, 0, (nint monitor, nint hdc, ref Rect bounds, nint data) => { areas.Add(WorkArea(monitor)); return true; }, 0);
        return areas;
    }
    public static System.Windows.Point Pointer() { GetCursorPos(out var p); return new(p.X, p.Y); }
    public static Rect Rectangle(Window window) { GetWindowRect(new WindowInteropHelper(window).Handle, out var r); return r; }
    public static void Move(Window window, int x, int y) => SetWindowPos(new WindowInteropHelper(window).Handle, 0, x, y, 0, 0, 0x0001 | 0x0004 | 0x0010);
    public static DesktopArea WorkDips(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == 0) { var r = SystemParameters.WorkArea; return new(r.Left, r.Top, r.Width, r.Height); }
        var area = WorkArea(MonitorFromWindow(handle, 2)); var dpi = GetDpiForWindow(handle) / 96d;
        return new(area.Left / dpi, area.Top / dpi, area.Width / dpi, area.Height / dpi);
    }
    public static void MakeNonActivating(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        _ = SetWindowLongPtr(handle, -20, GetWindowLongPtr(handle, -20) | (window.ShowInTaskbar ? 0x08000000 : 0x08000080));
    }
    public static bool IsNonActivating(Window window) => (GetWindowLongPtr(new WindowInteropHelper(window).Handle, -20).ToInt64() & 0x08000000) != 0;
    public static nint Foreground => GetForegroundWindow();
    public static uint ForegroundProcess { get { _ = GetWindowThreadProcessId(Foreground, out var pid); return pid; } }
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint process);
    [DllImport("user32.dll")] private static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern nint SetWindowLongPtr(nint hwnd, int index, nint value);
    [StructLayout(LayoutKind.Sequential)] internal struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public uint Size; public Rect Monitor, Work; public uint Flags; }
    private static DesktopArea WorkArea(nint monitor)
    {
        var info = new MonitorInfo { Size = (uint)Marshal.SizeOf<MonitorInfo>() };
        if (GetMonitorInfo(monitor, ref info)) return new(info.Work.Left, info.Work.Top, info.Work.Right - info.Work.Left, info.Work.Bottom - info.Work.Top);
        var work = SystemParameters.WorkArea; return new(work.Left, work.Top, work.Width, work.Height);
    }
    public static void Place(Window window, Rect? anchor = null, bool bottomRight = true)
    {
        var handle = new WindowInteropHelper(window).Handle;
        var monitor = anchor is Rect rect ? MonitorFromPoint(new() { X = rect.Left, Y = rect.Top }, 2) : MonitorFromWindow(handle, 2);
        var area = WorkArea(monitor);
        // Move to the target monitor first, so WPF receives the real per-monitor DPI change.
        _ = SetWindowPos(handle, 0, (int)area.Left, (int)area.Top, 0, 0, 0x0001 | 0x0004 | 0x0010);
        window.UpdateLayout();
        var dpi = GetDpiForWindow(handle) / 96d;
        var width = Math.Ceiling(window.ActualWidth * dpi); var height = Math.Ceiling(window.ActualHeight * dpi);
        var point = anchor is Rect a
            ? DesktopPlacement.Clamp(new(a.Right - width, a.Top - height - 8 * dpi), area, width, height)
            : bottomRight ? DesktopPlacement.BottomRight(area, width, height, 12 * dpi)
            : DesktopPlacement.Clamp(new(window.Left * dpi, window.Top * dpi), area, width, height);
        _ = SetWindowPos(handle, 0, (int)point.X, (int)point.Y, 0, 0, 0x0001 | 0x0004 | 0x0010);
    }
    public static void ClampToMonitor(Window window)
    {
        var handle = new WindowInteropHelper(window).Handle;
        var area = WorkArea(MonitorFromWindow(handle, 2));
        if (!GetWindowRect(handle, out var rect)) return;
        var point = DesktopPlacement.Clamp(new(rect.Left, rect.Top), area, rect.Right - rect.Left, rect.Bottom - rect.Top);
        _ = SetWindowPos(handle, 0, (int)point.X, (int)point.Y, 0, 0, 0x0001 | 0x0004 | 0x0010);
    }
    public static bool IsTopmost(Window window) => (GetWindowLongPtr(new WindowInteropHelper(window).Handle, -20).ToInt64() & 8) != 0;
    [DllImport("user32.dll")] private static extern nint MonitorFromWindow(nint window, uint flags);
    [DllImport("user32.dll")] private static extern nint MonitorFromPoint(Point point, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(nint window);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetWindowPos(nint hwnd, nint after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetWindowRect(nint hwnd, out Rect rect);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern nint GetWindowLongPtr(nint hwnd, int index);
}
