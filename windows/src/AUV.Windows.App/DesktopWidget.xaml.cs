using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using AUV.Windows.Core;
namespace AUV.Windows.App;
public partial class DesktopWidget : Window
{
    private readonly Action<string> select;
    private readonly Action remember;
    private readonly Action hide;
    private readonly Func<ContextMenu> menu;
    private bool exiting, dragging;
    private Point? start;
    private NativeDesktop.Rect origin;
    private string? pressedId;
    private double stableValueWidth;
    private double previousTextScale;
    private IReadOnlyList<AllowanceCard> currentCards = [];
    private DesktopPreferences currentPreferences = new();
    public WizardDensity RenderedDensity { get; private set; }
    public int CardCount => Cards.Children.Count;
    public DesktopWidget(Action<string> select, Action remember, Action hide, Func<ContextMenu> menu, bool automation = false)
    {
        this.select = select; this.remember = remember; this.hide = hide; this.menu = menu;
        InitializeComponent();
        ShowInTaskbar = automation;
        SourceInitialized += (_, _) => { NativeDesktop.MakeNonActivating(this); HwndSource.FromHwnd(new WindowInteropHelper(this).Handle)?.AddHook(WindowMessage); };
        Closing += (_, e) => { if (!exiting) { e.Cancel = true; hide(); } };
        PreviewMouseRightButtonUp += (_, e) => { CancelGesture(); var context = menu(); context.PlacementTarget = this; context.IsOpen = true; e.Handled = true; };
        PreviewMouseLeftButtonDown += Begin; PreviewMouseMove += Move; PreviewMouseLeftButtonUp += End;
        LostMouseCapture += (_, _) => { if (start != null) CancelGesture(); };
    }
    public void Present(IReadOnlyList<AllowanceCard> cards, DesktopPreferences preferences, double textScale)
    {
        cards = cards.Where(c => c.HasDisplayableQuota).ToArray();
        currentCards = cards; currentPreferences = preferences;
        RenderedDensity = WizardPolicy.Resolve(preferences.Density, cards.Count);
        if (previousTextScale != textScale) { stableValueWidth = 0; previousTextScale = textScale; }
        var measure = WizardTypography.Measure(cards.Select(c => c.Value), textScale, Dpi());
        stableValueWidth = Math.Max(stableValueWidth, measure.ValueWidth);
        var nativeWidth = cards.Where(c => c.Kind == AllowanceKind.Credits).Select(c => WizardTypography.Text(c.Value, 18 * textScale, System.Windows.Media.Brushes.Black, Dpi(), FontWeights.SemiBold).WidthIncludingTrailingWhitespace + 55 * textScale).DefaultIfEmpty(0).Max();
        var width = RenderedDensity == WizardDensity.Regular ? Math.Max(WizardPolicy.RegularWidth * textScale, nativeWidth * WizardPolicy.WidthRatio * WizardPolicy.RegularWidthAdjustment)
            : ((10 + 18 * textScale + 3) * WizardPolicy.WidthRatio + stableValueWidth) * WizardPolicy.MinimalistWidthAdjustment;
        var height = RenderedDensity == WizardDensity.Regular ? WizardPolicy.RegularRowHeight * textScale : measure.Height;
        Cards.Children.Clear();
        foreach (var card in cards)
            Cards.Children.Add(new AllowanceRow { Card = card, Density = RenderedDensity, ShowStatus = preferences.ShowStatus, ShowFill = preferences.ShowFill,
                Capsule = true, CompactDesktop = true, TextScale = textScale, Width = width, Height = height, MinHeight = 0,
                Margin = new Thickness(0, Cards.Children.Count == 0 ? 0 : WizardPolicy.RowGap, 0, 0), Tag = card.Id });
        var work = NativeDesktop.WorkDips(this); var stack = WizardPolicy.StackHeight(cards.Count, height); var bounded = stack > work.Height;
        Overflow.VerticalScrollBarVisibility = bounded ? ScrollBarVisibility.Auto : ScrollBarVisibility.Disabled;
        Width = Math.Min(work.Width, width + (bounded ? SystemParameters.VerticalScrollBarWidth : 0)); Height = Math.Max(1, Math.Min(stack, work.Height)); Topmost = preferences.AlwaysOnTop;
        if (IsVisible) { UpdateLayout(); NativeDesktop.ClampToMonitor(this); }
    }
    private double Dpi() => System.Windows.Media.VisualTreeHelper.GetDpi(this).PixelsPerDip;
    private void Begin(object sender, MouseButtonEventArgs e)
    {
        var row = e.OriginalSource as DependencyObject;
        while (row != null && row is not AllowanceRow) row = System.Windows.Media.VisualTreeHelper.GetParent(row);
        if (row is not AllowanceRow card) return;
        start = NativeDesktop.Pointer(); origin = NativeDesktop.Rectangle(this); pressedId = card.Card?.Id; dragging = false; CaptureMouse(); e.Handled = true;
    }
    private void Move(object sender, MouseEventArgs e)
    {
        if (start is not Point initial || e.LeftButton != MouseButtonState.Pressed) return;
        var delta = NativeDesktop.Pointer() - initial;
        dragging |= WizardPolicy.IsDrag(delta.X / Dpi(), delta.Y / Dpi(), SystemParameters.MinimumHorizontalDragDistance, SystemParameters.MinimumVerticalDragDistance);
        if (dragging) NativeDesktop.Move(this, origin.Left + (int)delta.X, origin.Top + (int)delta.Y);
        e.Handled = true;
    }
    private void End(object sender, MouseButtonEventArgs e)
    {
        if (start == null) return;
        var wasDrag = dragging; var id = pressedId; CancelGesture(); if (wasDrag) remember(); else if (id != null) select(id); e.Handled = true;
    }
    private void CancelGesture() { start = null; pressedId = null; dragging = false; if (IsMouseCaptured) ReleaseMouseCapture(); }
    private nint WindowMessage(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == 0x21) { handled = true; return 3; }
        if (message is 0x007e or 0x02e0) Dispatcher.BeginInvoke(() => { Present(currentCards, currentPreferences, previousTextScale); NativeDesktop.ClampToMonitor(this); remember(); });
        return 0;
    }
    internal void CloseForExit() { exiting = true; Close(); }
}
