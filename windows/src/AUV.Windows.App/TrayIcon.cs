using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Windows;
using System.Windows.Interop;

namespace AUV.Windows.App;

/// <summary>Documented Shell notification icon. Does not inject into or alter Explorer.</summary>
internal sealed class TrayIcon : IDisposable
{
    private const uint Callback = 0x8000 + 71;
    private readonly HwndSource source;
    private readonly uint taskbarCreated = RegisterWindowMessage("TaskbarCreated");
    private NotifyIconData data;
    private nint ownedIcon;
    private bool disposed, visible;
    public bool IsAdded { get; private set; }
    public event Action<bool>? Activated;
    public event Action? AvailabilityChanged;
    internal TrayIcon(Window window, string settingsPath, bool visible = true)
    {
        this.visible = visible;
        var handle = new WindowInteropHelper(window).Handle;
        source = HwndSource.FromHwnd(handle)!;
        var icon = SendMessage(handle, 0x007F, 0, 0); // WM_GETICON / ICON_SMALL, owned by WPF.
        if (icon == 0) icon = SendMessage(handle, 0x007F, 1, 0);
        if (icon == 0) icon = LoadIcon(0, (nint)32512); // Shared fallback, never destroyed here.
        data = new() { Size = (uint)Marshal.SizeOf<NotifyIconData>(), Window = handle, Id = 1,
            Flags = 1 | 2 | 4 | 0x20 | 0x80, CallbackMessage = Callback, Icon = icon, Tip = "AUV · usage unknown", Info = "", InfoTitle = "",
            Guid = Identity(settingsPath) };
        UpdateAppearance(); source.AddHook(Hook); Add();
    }
    private static Guid Identity(string settingsPath)
    {
        // Unsigned Shell icon GUIDs are bound to the executable path. Keep restarts stable
        // while isolating side-by-side portable builds and separate preference profiles.
        var path = System.IO.Path.GetFullPath(Environment.ProcessPath!).ToUpperInvariant();
        var profile = System.IO.Path.GetFullPath(settingsPath).ToUpperInvariant();
        return new Guid(SHA256.HashData(Encoding.UTF8.GetBytes("AUV.Windows.Tray.v1\n" + path + "\n" + profile)).AsSpan(0, 16));
    }
    private void Add()
    {
        if (disposed || !visible) return;
        IsAdded = Shell_NotifyIcon(0, ref data);
        if (IsAdded) { data.Version = 4; _ = Shell_NotifyIcon(4, ref data); }
        AvailabilityChanged?.Invoke();
    }
    public void SetVisible(bool value)
    {
        if (disposed || visible == value) return;
        visible = value;
        if (value) Add();
        else
        {
            if (IsAdded) _ = Shell_NotifyIcon(2, ref data);
            IsAdded = false; AvailabilityChanged?.Invoke();
        }
    }
    public void SetTooltip(string value)
    { data.Tip = value.Length <= 127 ? value : value[..127]; if (IsAdded) _ = Shell_NotifyIcon(1, ref data); }
    public void UpdateAppearance()
    {
        if (disposed) return;
        var png = AppBrandIcon.TrayPng(WindowsAppearance.ShellLight);
        var replacement = CreateIconFromResourceEx(png, (uint)png.Length, true, 0x00030000, 32, 32, 0);
        if (replacement == 0) return;
        var previous = ownedIcon; ownedIcon = replacement; data.Icon = replacement;
        if (IsAdded) _ = Shell_NotifyIcon(1, ref data);
        if (previous != 0) _ = DestroyIcon(previous);
    }
    private nint Hook(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (disposed) return 0;
        if ((uint)message == taskbarCreated) Add();
        if ((uint)message == Callback)
        {
            var code = (int)((long)lParam & 0xffff);
            if (code is 0x400 or 0x401) Activated?.Invoke(false); // NIN_SELECT / NIN_KEYSELECT
            else if (code == 0x7B) Activated?.Invoke(true); // WM_CONTEXTMENU
            handled = true;
        }
        return 0;
    }
    public NativeDesktop.Rect? GetRectangle()
    {
        if (!IsAdded) return null;
        var id = new IconIdentifier { Size = (uint)Marshal.SizeOf<IconIdentifier>(), Window = data.Window, Id = data.Id, Guid = data.Guid };
        return Shell_NotifyIconGetRect(ref id, out var rect) == 0 ? rect : null;
    }
    public void Dispose()
    { if (disposed) return; disposed = true; if (IsAdded) _ = Shell_NotifyIcon(2, ref data); IsAdded = false; source.RemoveHook(Hook); if (ownedIcon != 0) { _ = DestroyIcon(ownedIcon); ownedIcon = 0; } }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] private struct NotifyIconData
    {
        public uint Size; public nint Window; public uint Id, Flags, CallbackMessage; public nint Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public uint Version;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string InfoTitle;
        public uint InfoFlags; public Guid Guid; public nint BalloonIcon;
    }
    [StructLayout(LayoutKind.Sequential)] private struct IconIdentifier
    { public uint Size; public nint Window; public uint Id; public Guid Guid; }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Shell_NotifyIcon(uint message, ref NotifyIconData data);
    [DllImport("shell32.dll")] private static extern int Shell_NotifyIconGetRect(ref IconIdentifier id, out NativeDesktop.Rect rect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern nint SendMessage(nint hwnd, uint message, nint wParam, nint lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern nint LoadIcon(nint instance, nint name);
    [DllImport("user32.dll")] private static extern nint CreateIconFromResourceEx(byte[] bits, uint size, [MarshalAs(UnmanagedType.Bool)] bool icon, uint version, int width, int height, uint flags);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DestroyIcon(nint icon);
}
