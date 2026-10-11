using System.Globalization;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Xml;
using System.Xml.Linq;

namespace AUV.Windows.App;

/// <summary>Native vector identity; no tile background, raster resampling or runtime downloads.</summary>
internal static class AppBrandIcon
{
    private static readonly Dictionary<bool, DrawingImage> cache = new();
    private static readonly ConditionalWeakTable<Window, TaskbarImage> taskbarImages = new();
    public static void Apply(Window window, bool darkWindow)
    {
        // Title-bar ink follows this window; the larger taskbar icon follows the Shell.
        // Windows permits independent app and system color modes.
        window.Icon = Create(!darkWindow);
        var handle = new WindowInteropHelper(window).Handle;
        if (handle != 0) taskbarImages.GetValue(window, w => new TaskbarImage(w)).Update(handle);
    }
    public static DrawingImage Create(bool lightShell)
    {
        if (!SystemParameters.HighContrast && cache.TryGetValue(lightShell, out var cached)) return cached;
        var ink = SystemParameters.HighContrast ? SystemColors.WindowTextBrush : new SolidColorBrush(lightShell ? Color.FromRgb(35, 39, 46) : Color.FromRgb(242, 244, 248));
        using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/AppMark.svg"))!.Stream;
        using var reader = XmlReader.Create(stream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
        var root = XDocument.Load(reader).Root!; var group = new DrawingGroup();
        // Transparent bounds keep title, taskbar and tray geometry aligned at every native size.
        group.Children.Add(new GeometryDrawing(Brushes.Transparent, null, new RectangleGeometry(new Rect(0, 0, 16, 16))));
        foreach (var element in root.Elements())
        {
            double Number(string name) => double.Parse(element.Attribute(name)!.Value, CultureInfo.InvariantCulture);
            Geometry geometry = element.Name.LocalName == "circle"
                ? new EllipseGeometry(new Point(Number("cx"), Number("cy")), Number("r"), Number("r"))
                : Geometry.Parse(element.Attribute("d")!.Value);
            var fill = element.Attribute("fill")?.Value == "none" ? null : ink;
            var pen = element.Attribute("stroke") == null ? null : new Pen(ink, Number("stroke-width")) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
            group.Children.Add(new GeometryDrawing(fill, pen, geometry));
        }
        var image = new DrawingImage(group); image.Freeze();
        if (!SystemParameters.HighContrast) cache[lightShell] = image;
        return image;
    }
    public static byte[] TrayPng(bool lightShell, int pixels = 32)
    {
        var visual = new DrawingVisual(); using (var drawing = visual.RenderOpen()) drawing.DrawImage(Create(lightShell), new Rect(0, 0, pixels, pixels));
        var bitmap = new RenderTargetBitmap(pixels, pixels, 96, 96, PixelFormats.Pbgra32); bitmap.Render(visual);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream(); encoder.Save(stream); return stream.ToArray();
    }
    private sealed class TaskbarImage
    {
        private nint owned;
        public TaskbarImage(Window window) => window.Closed += (_, _) => { if (owned != 0) { _ = DestroyIcon(owned); owned = 0; } };
        public void Update(nint window)
        {
            var bytes = TrayPng(WindowsAppearance.ShellLight);
            var icon = CreateIconFromResourceEx(bytes, (uint)bytes.Length, true, 0x00030000, 32, 32, 0);
            if (icon == 0) return;
            _ = SendMessage(window, 0x0080, 1, icon); // WM_SETICON / ICON_BIG. WPF retains its own small icon.
            var previous = owned; owned = icon; if (previous != 0) _ = DestroyIcon(previous);
        }
    }
    [DllImport("user32.dll")] private static extern nint CreateIconFromResourceEx(byte[] bits, uint size, [MarshalAs(UnmanagedType.Bool)] bool icon, uint version, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern nint SendMessage(nint window, int message, nint wParam, nint lParam);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool DestroyIcon(nint icon);
}
