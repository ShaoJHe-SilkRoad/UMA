using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using System.Windows.Media;
using AUV.Windows.Core;
namespace AUV.Windows.App;

public readonly record struct WizardMeasure(double Width, double Height, double ValueWidth);
public static class WizardTypography
{
    public static readonly FontFamily Family = new("Segoe UI, Microsoft YaHei UI");
    public static FormattedText Text(string text, double size, Brush brush, double dpi = 1, FontWeight? weight = null) => new(text,
        CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, new Typeface(Family, FontStyles.Normal, weight ?? FontWeights.Medium, FontStretches.Normal), size, brush, dpi);
    public static WizardMeasure Measure(IEnumerable<string> actualValues, double scale = 1, double dpi = 1)
    {
        var candidates = Enumerable.Range(0, 1001).Select(i => AllowanceCard.FormatPercent(i / 10d)).ToArray();
        var width = candidates.Concat(candidates.Select(v => "≈" + v)).Concat(["∞", "—"]).Concat(actualValues)
            .Max(v => Text(v, 20 * scale, Brushes.Black, dpi, FontWeights.SemiBold).WidthIncludingTrailingWhitespace);
        var line = Text("≈100% 中文 ∞ —", 20 * scale, Brushes.Black, dpi).Height;
        width = Math.Ceiling(width) + 2;
        return new((10 + 18 * scale + 3 + width) * WizardPolicy.WidthRatio,
            Math.Max(30, Math.Ceiling(line) + 10) * WizardPolicy.HeightRatio, width * WizardPolicy.WidthRatio);
    }
}

/// <summary>Shared clipped row background. No input, transport, or polling logic.</summary>
public sealed class AllowanceRow : Control
{
    public static readonly DependencyProperty CardProperty = DependencyProperty.Register(nameof(Card), typeof(AllowanceCard), typeof(AllowanceRow),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender, (o, _) => ((AllowanceRow)o).UpdateDescription()));
    public AllowanceCard? Card { get => (AllowanceCard?)GetValue(CardProperty); set => SetValue(CardProperty, value); }
    public WizardDensity Density { get; set; } = WizardDensity.Regular;
    public static readonly DependencyProperty ShowStatusProperty = DependencyProperty.Register(nameof(ShowStatus), typeof(bool), typeof(AllowanceRow), new FrameworkPropertyMetadata(true, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty ShowFillProperty = DependencyProperty.Register(nameof(ShowFill), typeof(bool), typeof(AllowanceRow), new FrameworkPropertyMetadata(true, FrameworkPropertyMetadataOptions.AffectsRender));
    public bool ShowStatus { get => (bool)GetValue(ShowStatusProperty); set => SetValue(ShowStatusProperty, value); }
    public bool ShowFill { get => (bool)GetValue(ShowFillProperty); set => SetValue(ShowFillProperty, value); }
    public double TextScale { get; set; } = 1;
    public bool Capsule { get; set; }
    public bool CompactDesktop { get; set; }
    public AllowanceRow() { Focusable = false; SnapsToDevicePixels = true; }
    private Brush Resource(string name) => (Brush)(TryFindResource(name) ?? Brushes.Gray);
    private void UpdateDescription()
    {
        var description = Card is { HasDisplayableQuota: true } card ? card.Description : Card?.Name ?? "Provider";
        ToolTip = description; AutomationProperties.SetName(this, description); InvalidateVisual();
    }
    protected override AutomationPeer OnCreateAutomationPeer() => new FrameworkElementAutomationPeer(this);
    public static Brush SeverityBrush(QuotaSeverity severity, FrameworkElement owner) => (Brush)(owner.TryFindResource(severity switch
        { QuotaSeverity.Low => "QuotaLowBrush", QuotaSeverity.Normal => "QuotaNormalBrush", _ => "QuotaNeutralBrush" }) ?? Brushes.Gray);
    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc); if (Card is not { } card) return;
        var size = new Rect(0, 0, ActualWidth, ActualHeight);
        var radius = Capsule ? ActualHeight / 2 : 7;
        var shape = new RectangleGeometry(size, radius, radius);
        dc.PushClip(shape); dc.DrawRectangle(Resource("SurfaceBrush"), null, size);
        if (ShowFill && card.HasDisplayableQuota && card.FillFraction is double fraction && fraction > 0)
        {
            dc.PushOpacity(SystemParameters.HighContrast ? .18 : .42);
            dc.DrawRectangle(SeverityBrush(card.Severity, this), null, new Rect(0, 0, ActualWidth * fraction, ActualHeight)); dc.Pop();
        }
        dc.Pop(); dc.DrawGeometry(null, new Pen(Resource("BorderBrush"), 1), shape);
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var small = Density == WizardDensity.Minimalist;
        var markSize = (CompactDesktop ? small ? 12 : 14 : small ? 18 : 24) * TextScale;
        var markX = CompactDesktop ? 4 * TextScale : small ? 5 : 9;
        if (!AgentBrandIcons.Draw(dc, card.Id, new Rect(markX, (ActualHeight - markSize) / 2, markSize, markSize), Resource("TextBrush")))
        {
            var mark = WizardTypography.Text(card.Mark, markSize * .78, Resource("TextBrush"), dpi, FontWeights.SemiBold);
            dc.DrawText(mark, new Point(markX + (markSize - mark.Width) / 2, (ActualHeight - mark.Height) / 2));
        }
        if (ShowStatus && card.HasDisplayableQuota)
        {
            var connectionBrush = card.Connection switch
            {
                ConnectionState.Connected => Resource("QuotaNormalBrush"), ConnectionState.Failed => Resource("QuotaLowBrush"),
                ConnectionState.Reconnecting or ConnectionState.Stale => Resource("WarningBrush"), _ => Resource("MutedBrush")
            };
            var indicatorScale = CompactDesktop ? .7 * TextScale : 1;
            var center = new Point(markX + markSize - 2 * indicatorScale, ActualHeight / 2 + markSize / 2 - 2 * indicatorScale);
            dc.DrawEllipse(Resource("SurfaceBrush"), null, center, 4 * indicatorScale, 4 * indicatorScale);
            dc.DrawEllipse(card.Connection is ConnectionState.Disconnected or ConnectionState.Unavailable ? Resource("SurfaceBrush") : connectionBrush,
                new Pen(connectionBrush, 1), center, 2.5 * indicatorScale, 2.5 * indicatorScale);
        }
        if (!card.HasDisplayableQuota)
        {
            // Keep a provider connection route in the rail without a placeholder quota.
            var name = WizardTypography.Text(card.Name, 12 * TextScale, Resource("MutedBrush"), dpi);
            name.MaxTextWidth = Math.Max(1, ActualWidth - markX - markSize - 16); name.MaxTextHeight = name.Height; name.Trimming = TextTrimming.CharacterEllipsis;
            dc.DrawText(name, new Point(markX + markSize + 8, (ActualHeight - name.Height) / 2)); return;
        }
        dc.PushOpacity(card.IsStale ? .78 : 1);
        if (CompactDesktop)
        {
            DrawCompact(dc, card, dpi, markX, markSize, small);
            dc.Pop(); return;
        }
        var value = WizardTypography.Text(card.Value, (small ? 20 : 18) * TextScale, Resource("TextBrush"), dpi, FontWeights.SemiBold);
        if (small) dc.DrawText(value, new Point(ActualWidth - 5 - value.WidthIncludingTrailingWhitespace, (ActualHeight - value.Height) / 2));
        else
        {
            var textX = markX + markSize + 8; var native = card.Kind == AllowanceKind.Credits;
            var name = WizardTypography.Text(card.Name, 13 * TextScale, Resource("TextBrush"), dpi, FontWeights.SemiBold);
            name.MaxTextWidth = Math.Max(20, ActualWidth - textX - (native ? 10 : value.Width + 16)); name.MaxTextHeight = name.Height; name.Trimming = TextTrimming.CharacterEllipsis;
            dc.DrawText(name, new Point(textX, 9 * TextScale));
            var detail = WizardTypography.Text(card.Detail, 11 * TextScale, Resource("MutedBrush"), dpi);
            detail.MaxTextWidth = Math.Max(20, ActualWidth - textX - 10); detail.MaxTextHeight = detail.Height; detail.Trimming = TextTrimming.CharacterEllipsis;
            if (!native) dc.DrawText(detail, new Point(textX, 31 * TextScale));
            dc.DrawText(value, new Point(ActualWidth - 10 - value.WidthIncludingTrailingWhitespace, native ? 30 * TextScale : 8 * TextScale));
        }
        dc.Pop();
    }
    private void DrawCompact(DrawingContext dc, AllowanceCard card, double dpi, double markX, double markSize, bool minimalist)
    {
        var inset = 5 * TextScale; var textX = markX + markSize + 5 * TextScale;
        var available = ActualWidth - inset - textX;
        var font = (minimalist ? 10.5 : 12) * TextScale;
        var displayValue = minimalist ? card.MinimalistValue : card.Value;
        var value = WizardTypography.Text(displayValue, font, Resource("TextBrush"), dpi, FontWeights.Medium);
        while (value.WidthIncludingTrailingWhitespace > available && font > 8.5 * TextScale)
        {
            font = Math.Max(8.5 * TextScale, font - .25 * TextScale);
            value = WizardTypography.Text(displayValue, font, Resource("TextBrush"), dpi, FontWeights.Medium);
        }
        value.MaxTextWidth = Math.Max(1, available); value.MaxTextHeight = value.Height;
        value.Trimming = TextTrimming.CharacterEllipsis;
        var valueWidth = Math.Min(available, value.WidthIncludingTrailingWhitespace);
        if (minimalist)
        {
            dc.DrawText(value, new Point(ActualWidth - inset - valueWidth, (ActualHeight - value.Height) / 2)); return;
        }
        var native = card.Kind == AllowanceKind.Credits;
        var nameWidth = ActualWidth - textX - inset - (native ? 0 : valueWidth + 4 * TextScale);
        var name = WizardTypography.Text(card.Name, 9.5 * TextScale, Resource("TextBrush"), dpi, FontWeights.SemiBold);
        name.MaxTextWidth = Math.Max(1, nameWidth); name.MaxTextHeight = name.Height; name.Trimming = TextTrimming.CharacterEllipsis;
        dc.DrawText(name, new Point(textX, 8 * TextScale));
        if (!native)
        {
            var detail = WizardTypography.Text(card.Detail, 8.5 * TextScale, Resource("MutedBrush"), dpi);
            detail.MaxTextWidth = Math.Max(1, ActualWidth - textX - inset); detail.MaxTextHeight = detail.Height; detail.Trimming = TextTrimming.CharacterEllipsis;
            dc.DrawText(detail, new Point(textX, 27 * TextScale));
        }
        dc.DrawText(value, new Point(ActualWidth - inset - valueWidth, (native ? 27 : 7) * TextScale));
    }
}
public sealed class DetailQuotaBar : FrameworkElement
{
    public static readonly DependencyProperty CardProperty = DependencyProperty.Register(nameof(Card), typeof(AllowanceCard), typeof(DetailQuotaBar), new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));
    public AllowanceCard? Card { get => (AllowanceCard?)GetValue(CardProperty); set => SetValue(CardProperty, value); }
    public DetailQuotaBar() { Height = 14; IsHitTestVisible = false; }
    protected override void OnRender(DrawingContext dc)
    {
        var r = new Rect(0, 0, ActualWidth, ActualHeight); var clip = new RectangleGeometry(r, ActualHeight / 2, ActualHeight / 2);
        dc.PushClip(clip); dc.DrawRectangle((Brush)FindResource("RaisedBrush"), null, r);
        if (Card?.HasDisplayableQuota == true && Card.FillFraction is double f && f > 0) dc.DrawRectangle(AllowanceRow.SeverityBrush(Card.Severity, this), null, new Rect(0, 0, ActualWidth * f, ActualHeight));
        dc.Pop();
        if (Card?.FillFraction == null) dc.DrawGeometry(null, new Pen((Brush)FindResource("MutedBrush"), 1) { DashStyle = DashStyles.Dash }, clip);
    }
}
