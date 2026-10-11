using System.Globalization;
using System.Windows;
using System.Windows.Media;
using System.Xml;
using System.Xml.Linq;

namespace AUV.Windows.App;

/// <summary>Exact locally bundled vendor paths. Known asset subset, not a network SVG loader.</summary>
public static class AgentBrandIcons
{
    private sealed record Mark(Rect Viewport, Geometry[] Paths, Geometry? Clip);
    private static readonly Dictionary<string, Mark> marks = new();
    private static Mark? Load(string id)
    {
        if (id is not ("codex" or "workbuddy")) return null;
        if (marks.TryGetValue(id, out var cached)) return cached;
        using var stream = Application.GetResourceStream(new Uri($"pack://application:,,,/Assets/AgentLogos/{id}.svg"))!.Stream;
        using var reader = XmlReader.Create(stream, new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null });
        var svg = XDocument.Load(reader).Root!;
        var box = svg.Attribute("viewBox")!.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries).Select(v => double.Parse(v, CultureInfo.InvariantCulture)).ToArray();
        var paths = svg.Descendants().Where(e => e.Name.LocalName == "path").Select(e => Geometry.Parse("F1 " + e.Attribute("d")!.Value)).ToList();
        if (id == "workbuddy")
        {
            foreach (var rect in svg.Descendants().Where(e => e.Name.LocalName == "rect" && e.Attribute("transform") != null))
            {
                double Number(string name) => double.Parse(rect.Attribute(name)!.Value, CultureInfo.InvariantCulture);
                var x = Number("x"); var y = Number("y"); var geometry = new RectangleGeometry(new Rect(x, y, Number("width"), Number("height")), Number("rx"), Number("rx"));
                geometry.Transform = new RotateTransform(-30, x, y); paths.Add(geometry);
            }
        }
        foreach (var path in paths) path.Freeze();
        var mark = new Mark(new Rect(box[0], box[1], box[2], box[3]), paths.ToArray(), id == "workbuddy" ? new EllipseGeometry(new Rect(0, 0, 40, 40)) : null);
        marks.Add(id, mark); return mark;
    }
    public static bool Draw(DrawingContext drawing, string provider, Rect target, Brush brush)
    {
        var mark = Load(provider.Split('.')[0]); if (mark == null) return false;
        drawing.PushTransform(new TranslateTransform(target.X, target.Y));
        drawing.PushTransform(new ScaleTransform(target.Width / mark.Viewport.Width, target.Height / mark.Viewport.Height));
        drawing.PushTransform(new TranslateTransform(-mark.Viewport.X, -mark.Viewport.Y));
        if (mark.Clip != null) drawing.PushClip(mark.Clip);
        foreach (var geometry in mark.Paths) drawing.DrawGeometry(brush, null, geometry);
        if (mark.Clip != null) drawing.Pop(); drawing.Pop(); drawing.Pop(); drawing.Pop(); return true;
    }
}
