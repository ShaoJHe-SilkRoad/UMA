using System.Text.Json;

namespace AUV.Windows.Core;

public sealed class WindowGeometry
{
    public double Width { get; set; } = 1040;
    public double Height { get; set; } = 762;
    public double? Left { get; set; }
    public double? Top { get; set; }
    public bool Maximized { get; set; }
    public void Normalize()
    {
        if (!double.IsFinite(Width) || Width < 760 || Width > 10000) Width = 1040;
        if (!double.IsFinite(Height) || Height < 500 || Height > 10000) Height = 762;
        if (Left is double x && !double.IsFinite(x)) Left = null;
        if (Top is double y && !double.IsFinite(y)) Top = null;
    }
}
public sealed class PreviewSettings
{
    public int Version { get; set; } = 1;
    public string Theme { get; set; } = "Dark";
    public bool LargerText { get; set; }
    public string SelectedAgent { get; set; } = "codex";
    public string ActiveSection { get; set; } = "AUV";
    public string CatalogRevision { get; set; } = "sol-luna-ultra-20261010.1";
    public WindowGeometry Geometry { get; set; } = new();
    public DesktopPreferences Desktop { get; set; } = new();
    public ProviderPreferences Providers { get; set; } = new();
    public Dictionary<string, RoleSelection> Roles { get; set; } = [];
    public void Normalize(ModelCatalog catalog)
    {
        if (Theme is not ("Dark" or "Light" or "System")) Theme = "Dark";
        if (ActiveSection is not ("AUV" or "ThreadOS" or "Sectorium")) ActiveSection = "AUV";
        if (!new[] { "codex", "claude", "workbuddy", "antigravity" }.Contains(SelectedAgent)) SelectedAgent = "codex";
        Geometry ??= new(); Geometry.Normalize(); Roles ??= [];
        Desktop ??= new(); Desktop.Normalize();
        Providers ??= new();
        if (CatalogRevision != catalog.Revision) Roles.Clear();
        Roles = Roles.Where(r => LeaderInstruction.Roles.Contains(r.Key) && r.Value != null && catalog.Allows(r.Value.Model, r.Value.Effort))
            .ToDictionary(r => r.Key, r => r.Value);
        CatalogRevision = catalog.Revision;
    }
}
public sealed class SettingsStore(string path)
{
    public static string DefaultPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AUV.Windows.UI.Preview", "settings.v1.json");
    public string PathName => path;
    public string? LastError { get; private set; }
    public PreviewSettings Load(ModelCatalog catalog)
    {
        LastError = null;
        try
        {
            if (!File.Exists(path)) return new();
            if (new FileInfo(path).Length > 1024 * 1024) throw new InvalidDataException("Settings file is too large.");
            var settings = JsonSerializer.Deserialize<PreviewSettings>(File.ReadAllText(path)) ?? throw new InvalidDataException("Empty settings.");
            if (settings.Version != 1) throw new InvalidDataException("Unsupported settings version.");
            settings.Normalize(catalog); return settings;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
        { LastError = "Settings could not be loaded. Defaults are in use. " + e.Message; return new(); }
    }
    public bool Save(PreviewSettings settings)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
            var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try { File.WriteAllText(temp, JsonSerializer.Serialize(settings, new JsonSerializerOptions { WriteIndented = true })); File.Move(temp, path, true); }
            finally { if (File.Exists(temp)) File.Delete(temp); }
            LastError = null; return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        { LastError = "Settings could not be saved. " + e.Message; return false; }
    }
}
