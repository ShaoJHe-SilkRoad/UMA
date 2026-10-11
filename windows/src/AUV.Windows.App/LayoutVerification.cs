using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
namespace AUV.Windows.App;

/// <summary>Opt-in local evidence harness. Captures the actual WPF visual tree; never touches OS display settings.</summary>
internal static class LayoutVerification
{
    private static IEnumerable<DependencyObject> Descendants(DependencyObject parent)
    {
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(parent); i++)
        { var child = VisualTreeHelper.GetChild(parent, i); yield return child; foreach (var nested in Descendants(child)) yield return nested; }
    }
    internal static async Task Run(MainWindow window, string directory)
    {
        Directory.CreateDirectory(directory);
        var results = new List<object>();
        var previousSection = window.Model.Shell.Section;
        var previousState = window.WindowState;
        var previousWidth = window.Width; var previousHeight = window.Height;
        try
        {
            window.WindowState = WindowState.Normal;
            var chromeWidth = window.ActualWidth - ((FrameworkElement)window.Content).ActualWidth;
            var chromeHeight = window.ActualHeight - ((FrameworkElement)window.Content).ActualHeight;
            var work = SystemParameters.WorkArea;
            foreach (var size in new[] { (1040d + chromeWidth, 760d + chromeHeight, false), (820d, 650d, false), (760d, 500d, false), (work.Width, work.Height, true) })
            {
                window.WindowState = WindowState.Normal;
                window.Width = size.Item1; window.Height = size.Item2;
                if (size.Item3) window.WindowState = WindowState.Maximized;
                foreach (var section in new[] { "AUV", "ThreadOS", "Sectorium" })
                {
                    window.Model.Shell.Section = section;
                    if (section == "ThreadOS") window.Model.GenerateCommand.Execute(null);
                    await window.Dispatcher.InvokeAsync(() => window.UpdateLayout(), DispatcherPriority.ContextIdle);
                    var combos = Descendants(window).OfType<ComboBox>().Where(c => c.IsVisible && c.IsEnabled).ToArray();
                    var storage = Descendants(window).OfType<Button>().Where(b => AutomationProperties.GetAutomationId(b).StartsWith("sectorium.")).ToArray();
                    foreach (var scale in new[] { 1d, 1.25d, 1.5d, 2d })
                    {
                        var visual = (FrameworkElement)window.Content;
                        var bitmap = new RenderTargetBitmap((int)Math.Ceiling(visual.ActualWidth * scale), (int)Math.Ceiling(visual.ActualHeight * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
                        bitmap.Render(visual);
                        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                        var name = $"{section.ToLowerInvariant()}-{size.Item1:0}x{size.Item2:0}-{scale * 100:0}pct.png";
                        using var stream = File.Create(Path.Combine(directory, name)); encoder.Save(stream);
                    }
                    results.Add(new { Section = section, Width = size.Item1, Height = size.Item2,
                        NativeWindowState = window.WindowState.ToString(), OuterWidth = window.ActualWidth, OuterHeight = window.ActualHeight,
                        ClientWidth = ((FrameworkElement)window.Content).ActualWidth, ClientHeight = ((FrameworkElement)window.Content).ActualHeight,
                        NativeDpi = VisualTreeHelper.GetDpi(window).PixelsPerInchX,
                        ModelControlCount = combos.Length, MinimumComboWidth = combos.Length > 0 ? combos.Min(c => c.ActualWidth) : 0,
                        StorageActionCount = storage.Length, StorageActionsAllDisabled = storage.All(b => !b.IsEnabled),
                        Note = "100/125/150/200% are WPF render-density checks; OS display scaling is reported separately." });
                }
            }
            File.WriteAllText(Path.Combine(directory, "layout-results.json"), JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
            window.Model.Status = "Local layout evidence captured. OS scaling requires separate verification.";
        }
        catch (Exception e) { File.WriteAllText(Path.Combine(directory, "layout-error.txt"), e.ToString()); window.Model.Status = "Layout check failed; see local evidence."; }
        finally { window.Width = previousWidth; window.Height = previousHeight; window.WindowState = previousState; window.Model.Shell.Section = previousSection; }
    }
}
