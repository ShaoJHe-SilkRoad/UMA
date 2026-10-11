using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
namespace AUV.Windows.App;

/// <summary>Opt-in, task-local render and lifecycle evidence. Native tray clicks are verified separately.</summary>
internal static class DesktopVerification
{
    internal static async Task Run(App app, MainWindow main, string directory)
    {
        Directory.CreateDirectory(directory);
        var originalVisible = app.Desktop.WidgetVisible; var originalTopmost = app.Desktop.AlwaysOnTop;
        var results = new List<object>();
        try
        {
            app.Desktop.SetWidgetVisible(true);
            await Task.Delay(2400);
            results.Add(new { Stage = "widget-shown", State = app.Desktop.Evidence });
            app.Desktop.HideMain();
            results.Add(new { Stage = "main-hidden-widget-independent", MainVisible = main.IsVisible, State = app.Desktop.Evidence });
            app.Desktop.OpenMain();
            app.Desktop.AlwaysOnTop = false;
            results.Add(new { Stage = "unpin-widget", State = app.Desktop.Evidence });
            app.Desktop.AlwaysOnTop = true;
            app.Desktop.ToggleFlyout();
            await main.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ContextIdle);
            foreach (var surface in app.Windows.Cast<Window>().Where(w => w is DesktopWidget or UsageFlyout).ToArray())
            {
                surface.UpdateLayout();
                foreach (var scale in new[] { 1d, 1.25d, 1.5d })
                {
                    var visual = (FrameworkElement)surface.Content;
                    var bitmap = new RenderTargetBitmap((int)Math.Ceiling(visual.ActualWidth * scale), (int)Math.Ceiling(visual.ActualHeight * scale), 96 * scale, 96 * scale, PixelFormats.Pbgra32);
                    bitmap.Render(visual); var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using var stream = File.Create(Path.Combine(directory, $"{surface.GetType().Name}-{scale * 100:0}pct.png")); encoder.Save(stream);
                }
                results.Add(new { Stage = "surface-rendered", Surface = surface.Title, surface.ActualWidth, surface.ActualHeight, Dpi = VisualTreeHelper.GetDpi(surface).PixelsPerInchX });
            }
            app.Desktop.ToggleFlyout(); app.Desktop.SetWidgetVisible(false);
            results.Add(new { Stage = "all-panels-hidden-sampling-stopped", State = app.Desktop.Evidence });
            main.Model.Status = "Desktop render and lifecycle checks captured. Native tray interaction is checked separately.";
        }
        catch (Exception e) { File.WriteAllText(Path.Combine(directory, "desktop-error.txt"), e.ToString()); main.Model.Status = "Desktop verification failed; see local evidence."; }
        finally
        {
            app.Desktop.AlwaysOnTop = originalTopmost; app.Desktop.SetWidgetVisible(originalVisible);
            File.WriteAllText(Path.Combine(directory, "desktop-results.json"), JsonSerializer.Serialize(results, new JsonSerializerOptions { WriteIndented = true }));
        }
    }
}
