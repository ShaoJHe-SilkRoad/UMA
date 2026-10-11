using System.Windows;
using System.Windows.Controls;
namespace AUV.Windows.App;
public sealed class AdaptiveWorkbench : Panel
{
    private bool narrow;
    protected override Size MeasureOverride(Size available)
    {
        narrow = available.Width < 900;
        var width = double.IsInfinity(available.Width) ? 1040 : available.Width;
        foreach (UIElement child in InternalChildren) child.Measure(new(narrow ? width : (width - 24) / 2, double.PositiveInfinity));
        return new(width, narrow ? InternalChildren.Cast<UIElement>().Sum(c => c.DesiredSize.Height) + 24 : InternalChildren.Cast<UIElement>().Max(c => c.DesiredSize.Height));
    }
    protected override Size ArrangeOverride(Size final)
    {
        double offset = 0;
        foreach (UIElement child in InternalChildren)
        {
            child.Arrange(narrow ? new Rect(0, offset, final.Width, child.DesiredSize.Height) : new Rect(offset, 0, (final.Width - 24) / 2, child.DesiredSize.Height));
            offset += narrow ? child.DesiredSize.Height + 24 : (final.Width - 24) / 2 + 24;
        }
        return final;
    }
}
