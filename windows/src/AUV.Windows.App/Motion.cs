using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace AUV.Windows.App;

/// <summary>
/// 0.18.6 motion. Every transition animates only Opacity and RenderTransform (translate, scale, rotate), eases out with a
/// cubic curve and runs 90–220 ms. When Windows "Show animations" is off, in high contrast, or with --no-animations,
/// nothing animates: each call jumps straight to its end state.
/// </summary>
public static class Motion
{
    public static bool ForcedOff { get; set; }
    public static bool Enabled => !ForcedOff && SystemParameters.ClientAreaAnimation && !SystemParameters.HighContrast;
    private static readonly IEasingFunction EaseOut = Freeze(new CubicEase { EasingMode = EasingMode.EaseOut });
    private static IEasingFunction Freeze(CubicEase ease) { ease.Freeze(); return ease; }

    private static (ScaleTransform Scale, TranslateTransform Translate) Transforms(UIElement element)
    {
        if (element.RenderTransform is TransformGroup { Children: [ScaleTransform scale, TranslateTransform translate] } && !element.RenderTransform.IsFrozen)
            return (scale, translate);
        var group = new TransformGroup(); var s = new ScaleTransform(); var t = new TranslateTransform();
        group.Children.Add(s); group.Children.Add(t);
        element.RenderTransform = group; element.RenderTransformOrigin = new Point(.5, .5);
        return (s, t);
    }

    private static DoubleAnimation Animation(double from, double to, int milliseconds) =>
        new(from, to, TimeSpan.FromMilliseconds(milliseconds)) { EasingFunction = EaseOut, FillBehavior = FillBehavior.Stop };

    /// <summary>Fade in, moving up from <paramref name="offsetY"/> and growing from <paramref name="fromScale"/>.</summary>
    public static void Enter(UIElement element, double offsetY, double fromScale, int milliseconds, double fromOpacity = 0)
    {
        var (scale, translate) = Transforms(element);
        // The end state is the base value; the animation only plays on top of it and is then removed.
        element.Opacity = 1; translate.Y = 0; scale.ScaleX = scale.ScaleY = 1;
        if (!Enabled) { element.BeginAnimation(UIElement.OpacityProperty, null); translate.BeginAnimation(TranslateTransform.YProperty, null); scale.BeginAnimation(ScaleTransform.ScaleXProperty, null); scale.BeginAnimation(ScaleTransform.ScaleYProperty, null); return; }
        element.BeginAnimation(UIElement.OpacityProperty, Animation(fromOpacity, 1, milliseconds));
        translate.BeginAnimation(TranslateTransform.YProperty, offsetY == 0 ? null : Animation(offsetY, 0, milliseconds));
        var grow = fromScale == 1 ? null : Animation(fromScale, 1, milliseconds);
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, grow); scale.BeginAnimation(ScaleTransform.ScaleYProperty, grow);
    }

    /// <summary>One soft opacity pulse, used when a card's figures change.</summary>
    public static void Pulse(UIElement element, double from = .6, int milliseconds = 150)
    {
        element.Opacity = 1;
        element.BeginAnimation(UIElement.OpacityProperty, Enabled ? Animation(from, 1, milliseconds) : null);
    }

    /// <summary>Fade out, then run <paramref name="done"/> (at once when motion is off).</summary>
    public static void FadeOut(UIElement element, int milliseconds, Action done)
    {
        if (!Enabled || element.Opacity == 0) { element.BeginAnimation(UIElement.OpacityProperty, null); done(); return; }
        var fade = new DoubleAnimation(element.Opacity, 0, TimeSpan.FromMilliseconds(milliseconds)) { EasingFunction = EaseOut, FillBehavior = FillBehavior.HoldEnd };
        fade.Completed += (_, _) => done();
        element.BeginAnimation(UIElement.OpacityProperty, fade);
    }

    /// <summary>Move an element's TranslateTransform to <paramref name="y"/>; slides when motion is on and <paramref name="slide"/> is true.</summary>
    public static void SlideTo(TranslateTransform translate, double y, bool slide, int milliseconds = 160)
    {
        var current = translate.Y;
        translate.Y = y;
        translate.BeginAnimation(TranslateTransform.YProperty, Enabled && slide && Math.Abs(current - y) > .5 ? Animation(current, y, milliseconds) : null);
    }

    // ---- Spinning refresh glyph: one turn per 900 ms while busy; when it stops, the current turn finishes and comes to rest upright ----

    private const double TurnMilliseconds = 900;
    public static void Spin(RotateTransform rotate, bool spinning)
    {
        var angle = rotate.Angle % 360;
        if (spinning && Enabled)
        {
            if (Equals(rotate.GetValue(SpinningProperty), true)) return;
            rotate.SetValue(SpinningProperty, true);
            rotate.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(angle, angle + 360, TimeSpan.FromMilliseconds(TurnMilliseconds)) { RepeatBehavior = RepeatBehavior.Forever });
            return;
        }
        rotate.SetValue(SpinningProperty, false);
        if (!Enabled || angle < .5) { rotate.BeginAnimation(RotateTransform.AngleProperty, null); rotate.Angle = 0; return; }
        var rest = new DoubleAnimation(angle, 360, TimeSpan.FromMilliseconds(TurnMilliseconds * (360 - angle) / 360)) { EasingFunction = EaseOut, FillBehavior = FillBehavior.Stop };
        rotate.Angle = 0;
        rotate.BeginAnimation(RotateTransform.AngleProperty, rest);
    }
    private static readonly DependencyProperty SpinningProperty = DependencyProperty.RegisterAttached("Spinning", typeof(bool), typeof(Motion));

    // ---- Attached behaviours for XAML ----

    /// <summary>Plays an entrance when the element loads: fade, rising by EnterOffset, growing from EnterScale, over EnterDuration ms.</summary>
    public static readonly DependencyProperty EnterOnLoadProperty = DependencyProperty.RegisterAttached("EnterOnLoad", typeof(bool), typeof(Motion), new PropertyMetadata(false, (d, e) =>
    {
        if (d is not FrameworkElement element) return;
        element.Loaded -= PlayEnter;
        if ((bool)e.NewValue) element.Loaded += PlayEnter;
    }));
    public static bool GetEnterOnLoad(DependencyObject d) => (bool)d.GetValue(EnterOnLoadProperty);
    public static void SetEnterOnLoad(DependencyObject d, bool value) => d.SetValue(EnterOnLoadProperty, value);
    public static readonly DependencyProperty EnterOffsetProperty = DependencyProperty.RegisterAttached("EnterOffset", typeof(double), typeof(Motion), new PropertyMetadata(0d));
    public static double GetEnterOffset(DependencyObject d) => (double)d.GetValue(EnterOffsetProperty);
    public static void SetEnterOffset(DependencyObject d, double value) => d.SetValue(EnterOffsetProperty, value);
    public static readonly DependencyProperty EnterScaleProperty = DependencyProperty.RegisterAttached("EnterScale", typeof(double), typeof(Motion), new PropertyMetadata(1d));
    public static double GetEnterScale(DependencyObject d) => (double)d.GetValue(EnterScaleProperty);
    public static void SetEnterScale(DependencyObject d, double value) => d.SetValue(EnterScaleProperty, value);
    public static readonly DependencyProperty EnterDurationProperty = DependencyProperty.RegisterAttached("EnterDuration", typeof(int), typeof(Motion), new PropertyMetadata(160));
    public static int GetEnterDuration(DependencyObject d) => (int)d.GetValue(EnterDurationProperty);
    public static void SetEnterDuration(DependencyObject d, int value) => d.SetValue(EnterDurationProperty, value);
    private static void PlayEnter(object sender, RoutedEventArgs e)
    {
        var element = (FrameworkElement)sender;
        element.Loaded -= PlayEnter; // once per element
        Enter(element, GetEnterOffset(element), GetEnterScale(element), GetEnterDuration(element));
    }

    /// <summary>Plays the entrance again each time the element becomes visible (settings panes, the tray panel).</summary>
    public static readonly DependencyProperty EnterOnShowProperty = DependencyProperty.RegisterAttached("EnterOnShow", typeof(bool), typeof(Motion), new PropertyMetadata(false, (d, e) =>
    {
        if (d is not UIElement element) return;
        element.IsVisibleChanged -= ShowChanged;
        if ((bool)e.NewValue) element.IsVisibleChanged += ShowChanged;
    }));
    public static bool GetEnterOnShow(DependencyObject d) => (bool)d.GetValue(EnterOnShowProperty);
    public static void SetEnterOnShow(DependencyObject d, bool value) => d.SetValue(EnterOnShowProperty, value);
    private static void ShowChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (sender is FrameworkElement element && e.NewValue is true) Enter(element, GetEnterOffset(element), GetEnterScale(element), GetEnterDuration(element));
    }

    /// <summary>A list item shows a 3px accent bar at its left while selected (settings sections).</summary>
    public static readonly DependencyProperty ItemIndicatorProperty = DependencyProperty.RegisterAttached("ItemIndicator", typeof(bool), typeof(Motion), new PropertyMetadata(false));
    public static bool GetItemIndicator(DependencyObject d) => (bool)d.GetValue(ItemIndicatorProperty);
    public static void SetItemIndicator(DependencyObject d, bool value) => d.SetValue(ItemIndicatorProperty, value);

    /// <summary>Hover and press feedback for a control whose template has a part named "HoverLayer": the layer fades in on hover (100 ms) and the control scales to 0.98 while pressed.</summary>
    public static readonly DependencyProperty FeedbackProperty = DependencyProperty.RegisterAttached("Feedback", typeof(bool), typeof(Motion), new PropertyMetadata(false, (d, e) =>
    {
        if (d is not Control control) return;
        control.MouseEnter -= HoverIn; control.MouseLeave -= HoverOut; control.PreviewMouseLeftButtonDown -= PressIn; control.PreviewMouseLeftButtonUp -= PressOut; control.LostMouseCapture -= PressOut;
        if (!(bool)e.NewValue) return;
        control.MouseEnter += HoverIn; control.MouseLeave += HoverOut; control.PreviewMouseLeftButtonDown += PressIn; control.PreviewMouseLeftButtonUp += PressOut; control.LostMouseCapture += PressOut;
    }));
    public static bool GetFeedback(DependencyObject d) => (bool)d.GetValue(FeedbackProperty);
    public static void SetFeedback(DependencyObject d, bool value) => d.SetValue(FeedbackProperty, value);
    private const double HoverOpacity = 1;
    private static UIElement? Layer(Control control) => control.Template?.FindName("HoverLayer", control) as UIElement;
    private static void Hover(Control control, bool over)
    {
        if (Layer(control) is not { } layer) return;
        var to = over && control.IsEnabled ? HoverOpacity : 0;
        var from = layer.Opacity; layer.Opacity = to;
        layer.BeginAnimation(UIElement.OpacityProperty, Enabled ? Animation(from, to, over ? 100 : 90) : null);
    }
    private static void HoverIn(object sender, MouseEventArgs e) => Hover((Control)sender, true);
    private static void HoverOut(object sender, MouseEventArgs e) { Hover((Control)sender, false); Press((Control)sender, false); }
    private static void PressIn(object sender, MouseButtonEventArgs e) => Press((Control)sender, true);
    private static void PressOut(object sender, EventArgs e) => Press((Control)sender, false);
    private static void Press(Control control, bool down)
    {
        var (scale, _) = Transforms(control);
        var to = down && Enabled ? .98 : 1; var from = scale.ScaleX;
        if (Math.Abs(from - to) < .001) return;
        scale.ScaleX = scale.ScaleY = to;
        var animation = Enabled ? Animation(from, to, 100) : null;
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, animation); scale.BeginAnimation(ScaleTransform.ScaleYProperty, animation);
    }
}
