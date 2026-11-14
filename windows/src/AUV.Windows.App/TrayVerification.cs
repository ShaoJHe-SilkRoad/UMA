using System.IO;
using System.Windows;
using System.Windows.Threading;
using AUV.Windows.Core;

namespace AUV.Windows.App;

/// <summary>
/// Opt-in 0.18.7 checks (--tray-check-dir, with --demo --offline and an isolated --settings-path) for the three reports
/// fixed in 0.18.7: the Desktop Wizard that would not open once disabled, the tray Usage panel that reopened or flashed
/// on a click, and the main window's minimize, hide and restore. Tray clicks are delivered as the Shell's own callback
/// message; a real mouse click on the taskbar is outside what this process can produce.
/// </summary>
internal static class TrayVerification
{
    private static async Task Settle(Window window, int milliseconds = 150) { await window.Dispatcher.InvokeAsync(() => window.UpdateLayout(), DispatcherPriority.ContextIdle); await Task.Delay(milliseconds); }
    internal static async Task Run(App app, MainWindow main, string directory)
    {
        Directory.CreateDirectory(directory);
        if (!app.Demo) { File.WriteAllText(Path.Combine(directory, "NOT_RUN.txt"), "Requires --demo and isolated preferences."); return; }
        var checks = new List<string>();
        void Require(bool valid, string message) { if (!valid) throw new InvalidOperationException(message); checks.Add(message); }
        var desktop = app.Desktop; var settings = app.Settings.Desktop;
        UsageFlyout? Panel() => app.Windows.OfType<UsageFlyout>().FirstOrDefault();
        bool PanelOpen() => Panel()?.IsVisible == true;
        DesktopWidget? Wizard() => app.Windows.OfType<DesktopWidget>().FirstOrDefault();
        try
        {
            // ---- Desktop Wizard: every Show control works when the Wizard was disabled ----
            desktop.SetWidgetVisible(false); desktop.Enabled = false; await Settle(main);
            Require(!settings.Enabled && !desktop.WidgetVisible, "Wizard starts disabled and hidden");
            desktop.ToggleWidgetCommand.Execute(null); await Settle(main, 400);
            Require(settings.Enabled && settings.WidgetVisible && desktop.WidgetVisible, "Show Desktop Wizard turns a disabled Wizard on and shows it");
            Require(Wizard() is { IsVisible: true, ActualWidth: > 0, ActualHeight: > 0 } shown && shown.CardCount > 0, "Wizard window is on screen with its cards");
            ProductVerification.Capture((FrameworkElement)Wizard()!.Content, Path.Combine(directory, "wizard.png"));
            desktop.ToggleWidgetCommand.Execute(null); await Settle(main);
            Require(!desktop.WidgetVisible && settings.Enabled && !settings.WidgetVisible, "The same control hides it again and leaves it enabled");
            // The state found in the reported settings file: disabled, but marked visible.
            settings.Enabled = false; settings.WidgetVisible = true; desktop.RefreshWizard(); await Settle(main);
            Require(!desktop.WidgetVisible, "Disabled-but-marked-visible stays hidden until asked");
            desktop.ToggleWidgetCommand.Execute(null); await Settle(main, 400);
            Require(desktop.WidgetVisible && settings.Enabled, "One press shows it from the disabled-but-marked-visible state");
            desktop.Enabled = false; await Settle(main);
            Require(!desktop.WidgetVisible, "Turning Enable off still hides the Wizard");
            desktop.Enabled = true; desktop.SetWidgetVisible(false); await Settle(main);

            // ---- Tray Usage panel ----
            Require(desktop.TrayAvailable, "Tray icon is registered");
            await Task.Delay(700); // outside the double-click time of anything earlier
            desktop.SimulateTrayClick(); await Settle(main, 400);
            Require(PanelOpen(), "A tray click opens the Usage panel");
            Require(Panel()!.ActualHeight > 100 && app.Windows.OfType<UsageFlyout>().Count() == 1, "The panel has content and there is one panel");
            ProductVerification.Capture((FrameworkElement)Panel()!.Content, Path.Combine(directory, "tray-panel.png"));
            await Task.Delay(700);
            // A real second click: pressing the mouse on the taskbar takes the panel's focus (it hides), then the click arrives.
            var focusPath = Panel()!.IsActive;
            if (focusPath) { main.Activate(); await Settle(main, 60); } else { Panel()!.Hide(); desktop.FlyoutDismissed(); }
            Require(!PanelOpen(), "The panel hides when it loses focus");
            desktop.SimulateTrayClick(); await Settle(main, 300);
            Require(!PanelOpen(), "The click that took the panel's focus leaves it closed (it used to reopen)" + (focusPath ? "" : " [focus loss simulated: this process was not in the foreground]"));
            await Task.Delay(700);
            desktop.SimulateTrayClick(); await Settle(main, 400);
            Require(PanelOpen(), "The next click opens it again");
            await Task.Delay(700);
            // Double click: the second click arrives within the double-click time, after the panel lost focus to the taskbar.
            desktop.ToggleFlyout(); await Settle(main); Require(!PanelOpen(), "Panel closed before the double click");
            desktop.SimulateTrayClick(); await Settle(main, 80);
            if (Panel()!.IsActive) { main.Activate(); await Settle(main, 40); } else { Panel()!.Hide(); desktop.FlyoutDismissed(); }
            desktop.SimulateTrayClick(); await Settle(main, 400);
            Require(PanelOpen(), "A double click leaves the panel open (it used to flash and vanish)");
            await Task.Delay(700);
            desktop.ToggleFlyout(); await Settle(main);
            // The main window's panel button while the panel is open: same focus order as the tray icon.
            desktop.ToggleFlyoutFromInput(); await Settle(main, 400); Require(PanelOpen(), "The panel button opens the panel");
            if (Panel()!.IsActive) { main.Activate(); await Settle(main, 60); } else { Panel()!.Hide(); desktop.FlyoutDismissed(); }
            desktop.ToggleFlyoutFromInput(); await Settle(main, 300);
            Require(!PanelOpen(), "Pressing the panel button while the panel is open closes it");

            // ---- Main window: minimize, hide, restore; AUV keeps running ----
            main.WindowState = WindowState.Maximized; await Settle(main, 400);
            main.WindowState = WindowState.Minimized; await Settle(main, 600);
            Require(main.IsVisible && NativeDesktop.IsMinimized(main) && !app.Dispatcher.HasShutdownStarted, "Minimize keeps AUV running with its taskbar button");
            Require(main.Persist() && app.Settings.Geometry.Maximized, "Saving while minimized keeps the maximized state");
            desktop.SimulateTrayClick(); await Settle(main, 400);
            Require(PanelOpen(), "The tray panel opens while the main window is minimized");
            desktop.OpenCommand.Execute(null); await Settle(main, 600);
            Require(main.WindowState == WindowState.Maximized && !PanelOpen(), "Open AUV restores a minimized window to maximized (it used to come back small)");
            main.WindowState = WindowState.Normal; await Settle(main, 300);
            main.WindowState = WindowState.Minimized; await Settle(main, 400);
            Require(main.Persist() && !app.Settings.Geometry.Maximized, "A normal window minimized is saved as normal");
            desktop.OpenMain(); await Settle(main, 400);
            Require(main.WindowState == WindowState.Normal, "Open AUV restores a minimized normal window to normal");
            desktop.HideMain(); await Settle(main, 300);
            Require(!main.IsVisible && !app.Dispatcher.HasShutdownStarted && desktop.TrayAvailable, "Hide to tray keeps AUV running with its tray icon");
            desktop.OpenMain(); await Settle(main, 300);
            Require(main.IsVisible && main.WindowState == WindowState.Normal, "Open AUV brings the hidden window back");
            File.WriteAllLines(Path.Combine(directory, "PASS.txt"), checks);
        }
        catch (Exception e) { File.WriteAllLines(Path.Combine(directory, "passed-before-error.txt"), checks); File.WriteAllText(Path.Combine(directory, "ERROR.txt"), e.ToString()); }
    }
}
