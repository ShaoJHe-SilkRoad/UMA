using System.IO;
using System.Text.Json;
using AUV.Windows.Core;
using Microsoft.Win32;

namespace AUV.Windows.App;

public enum CompanionInstallState { NotPackaged, NotInstalled, Installed, UpdateAvailable, RegistrationMissing }
/// <param name="ForeignRegistrations">Browsers whose registration belongs to another program; replaced only after asking.</param>
/// <param name="AuvRegistrationsElsewhere">0.18.6: browsers whose registration is an AUV companion in another folder (an earlier copy or
/// another preference profile); Set Up replaces these without asking.</param>
public sealed record CompanionStatus(CompanionInstallState State, ClaudeCompanionManifest? Packaged, ClaudeCompanionManifest? Installed,
    IReadOnlyList<string> RegisteredBrowsers, IReadOnlyList<string> ForeignRegistrations, IReadOnlyList<string> AuvRegistrationsElsewhere)
{
    public bool Registered => RegisteredBrowsers.Count > 0;
}

/// <summary>
/// Installs, updates and removes the companion's files and its per-user native messaging registration (HKCU only).
/// Nothing is overwritten that AUV did not create: an older extension folder is kept as a backup, an older host build
/// keeps its own folder, and a registry value pointing to another program is reported instead of replaced. A value that
/// points to AUV's own companion in another folder (0.18.6) is replaced, since it is the same companion.
/// </summary>
public sealed class ClaudeBrowserSetup(string installRoot, string packageRoot, string pipeName, RegistryKey? hive = null, string registryBase = "Software")
{
    public const string HostExecutable = "AUV.BrowserHost.exe";
    private readonly RegistryKey hive = hive ?? Registry.CurrentUser;
    public string InstallRoot => installRoot;
    public string ExtensionFolder => Path.Combine(installRoot, "extension");
    public static readonly (string Browser, string Path)[] Browsers =
        [("chrome", @"Google\Chrome\NativeMessagingHosts\" + ClaudeBrowserContract.NativeHostName), ("edge", @"Microsoft\Edge\NativeMessagingHosts\" + ClaudeBrowserContract.NativeHostName)];
    private string KeyPath(string relative) => registryBase + @"\" + relative;
    private string HostFolder(ClaudeCompanionManifest manifest) => Path.Combine(installRoot, "host", manifest.CompanionBuild);
    public string HostManifestPath(ClaudeCompanionManifest manifest) => Path.Combine(HostFolder(manifest), ClaudeBrowserContract.NativeHostName + ".json");
    private bool Ours(string? value) => value != null && Path.GetFullPath(value).StartsWith(Path.GetFullPath(installRoot) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);
    private string? RegisteredValue(string relative) { using var key = hive.OpenSubKey(KeyPath(relative)); return key?.GetValue(null) as string; }

    public CompanionStatus Status()
    {
        var packaged = ClaudeBrowserPaths.LoadManifest(packageRoot);
        var installed = ClaudeBrowserPaths.LoadManifest(installRoot);
        var registered = new List<string>(); var foreign = new List<string>(); var elsewhere = new List<string>();
        foreach (var (browser, path) in Browsers)
        {
            var value = RegisteredValue(path);
            if (value == null) continue;
            if (Ours(value) && installed != null && Path.GetFullPath(value).Equals(Path.GetFullPath(HostManifestPath(installed)), StringComparison.OrdinalIgnoreCase) && File.Exists(value)) registered.Add(browser);
            else if (!Ours(value)) (IsAuvCompanion(value) ? elsewhere : foreign).Add(browser);
        }
        var state = packaged == null && installed == null ? CompanionInstallState.NotPackaged
            : installed == null ? CompanionInstallState.NotInstalled
            : packaged != null && packaged != installed ? CompanionInstallState.UpdateAvailable
            : registered.Count == 0 ? CompanionInstallState.RegistrationMissing : CompanionInstallState.Installed;
        return new(state, packaged, installed, registered, foreign, elsewhere);
    }

    /// <summary>
    /// 0.18.6: a registration is AUV's own companion when its host manifest is named com.silkrd.auv.claude_browser and its
    /// folder holds AUV.BrowserHost.exe and a well-formed host-config.json. Only small files are read; nothing is run.
    /// </summary>
    public static bool IsAuvCompanion(string? hostManifestPath)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(hostManifestPath) || !Path.IsPathFullyQualified(hostManifestPath)) return false;
            var manifest = new FileInfo(hostManifestPath);
            if (!manifest.Exists || manifest.Length is 0 or > 4096) return false;
            using (var document = JsonDocument.Parse(File.ReadAllBytes(manifest.FullName)))
                if (document.RootElement.ValueKind != JsonValueKind.Object || !document.RootElement.TryGetProperty("name", out var name) ||
                    name.ValueKind != JsonValueKind.String || name.GetString() != ClaudeBrowserContract.NativeHostName) return false;
            var folder = manifest.DirectoryName!;
            var config = new FileInfo(Path.Combine(folder, ClaudeHostConfig.FileName));
            if (!File.Exists(Path.Combine(folder, HostExecutable)) || !config.Exists || config.Length is 0 or > 4096) return false;
            ClaudeHostConfig.Parse(File.ReadAllBytes(config.FullName));
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException or ArgumentException or NotSupportedException or System.Security.SecurityException) { return false; }
    }

    /// <summary>True when the packaged companion's build number is higher than the installed one (both are decimal digits).</summary>
    public static bool IsNewer(ClaudeCompanionManifest packaged, ClaudeCompanionManifest installed)
    {
        static string Trim(string digits) => digits.TrimStart('0') is { Length: > 0 } t ? t : "0";
        var (a, b) = (Trim(packaged.CompanionBuild), Trim(installed.CompanionBuild));
        return a.Length != b.Length ? a.Length > b.Length : string.CompareOrdinal(a, b) > 0;
    }

    /// <summary>
    /// 0.18.6 start-up update: when a companion is installed and this AUV carries a newer build, install it (AUV's own files
    /// and registration only). Returns the new manifest, or null when there was nothing to do. Throws as <see cref="Install"/> does,
    /// including <see cref="ForeignRegistrationException"/> when another program now holds the registration.
    /// </summary>
    public ClaudeCompanionManifest? UpdateIfNewer()
    {
        var status = Status();
        if (status.Installed is not { } installed || status.Packaged is not { } packaged || !IsNewer(packaged, installed)) return null;
        return Install(false);
    }

    /// <summary>Copies the packaged companion and registers the host for Chrome and Edge. Returns the installed manifest.</summary>
    public ClaudeCompanionManifest Install(bool replaceForeignRegistrations)
    {
        var packaged = ClaudeBrowserPaths.LoadManifest(packageRoot) ?? throw new InvalidOperationException("This copy of AUV has no browser companion package.");
        var status = Status();
        if (status.ForeignRegistrations.Count > 0 && !replaceForeignRegistrations) throw new ForeignRegistrationException(status.ForeignRegistrations);
        Directory.CreateDirectory(installRoot);
        // Host: one folder per build. An existing folder for this build is left as it is unless it is incomplete.
        var hostFolder = HostFolder(packaged);
        if (!File.Exists(Path.Combine(hostFolder, HostExecutable)))
        {
            var staging = hostFolder + ".installing-" + Guid.NewGuid().ToString("N")[..8];
            CopyTree(Path.Combine(packageRoot, "host"), staging);
            if (Directory.Exists(hostFolder)) Directory.Move(hostFolder, hostFolder + ".incomplete-" + DateTime.Now.ToString("yyyyMMddHHmmss"));
            Directory.Move(staging, hostFolder);
        }
        WriteJson(Path.Combine(hostFolder, ClaudeHostConfig.FileName), w =>
        {
            w.WriteNumber("schemaVersion", 1); w.WriteString("pipeName", pipeName); w.WriteString("allowedOrigin", packaged.ExtensionOrigin);
            w.WriteString("runtimeGenerationID", packaged.RuntimeGenerationId); w.WriteString("hostVersion", packaged.CompanionVersion); w.WriteString("hostBuild", packaged.CompanionBuild);
        });
        WriteJson(HostManifestPath(packaged), w =>
        {
            w.WriteString("name", ClaudeBrowserContract.NativeHostName); w.WriteString("description", "AUV Browser Companion for Claude");
            w.WriteString("path", HostExecutable); w.WriteString("type", "stdio");
            w.WriteStartArray("allowed_origins"); w.WriteStringValue(packaged.ExtensionOrigin); w.WriteEndArray();
        });
        // Extension: a fixed folder, because the browser remembers the folder it loaded. The previous copy is kept as a backup.
        var extension = ExtensionFolder;
        var stagingExtension = extension + ".installing-" + Guid.NewGuid().ToString("N")[..8];
        CopyTree(Path.Combine(packageRoot, "extension"), stagingExtension);
        if (Directory.Exists(extension))
        {
            var previous = ClaudeBrowserPaths.LoadManifest(installRoot)?.CompanionBuild ?? "unknown";
            Directory.Move(extension, extension + ".backup-" + previous + "-" + DateTime.Now.ToString("yyyyMMddHHmmss"));
        }
        Directory.Move(stagingExtension, extension);
        File.WriteAllBytes(Path.Combine(installRoot, "companion.json"), packaged.ToJson());
        foreach (var (_, path) in Browsers)
        {
            using var key = hive.CreateSubKey(KeyPath(path), true);
            key.SetValue(null, HostManifestPath(packaged), RegistryValueKind.String);
        }
        return packaged;
    }

    /// <summary>Removes AUV's registry values (only those pointing into its own folder) and, if asked, the folder AUV created.</summary>
    public void Remove(bool deleteFiles)
    {
        foreach (var (_, path) in Browsers)
            if (Ours(RegisteredValue(path))) hive.DeleteSubKey(KeyPath(path), false);
        if (deleteFiles && Directory.Exists(installRoot)) Directory.Delete(installRoot, true);
    }

    private static void CopyTree(string source, string destination)
    {
        if (!Directory.Exists(source)) throw new DirectoryNotFoundException("The browser companion package is incomplete.");
        Directory.CreateDirectory(destination);
        foreach (var directory in Directory.GetDirectories(source, "*", SearchOption.AllDirectories))
            Directory.CreateDirectory(Path.Combine(destination, Path.GetRelativePath(source, directory)));
        foreach (var file in Directory.GetFiles(source, "*", SearchOption.AllDirectories))
            File.Copy(file, Path.Combine(destination, Path.GetRelativePath(source, file)), false);
    }
    private static void WriteJson(string path, Action<Utf8JsonWriter> body)
    {
        var temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        using (var stream = File.Create(temp))
        using (var writer = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true })) { writer.WriteStartObject(); body(writer); writer.WriteEndObject(); }
        File.Move(temp, path, true);
    }
}

public sealed class ForeignRegistrationException(IReadOnlyList<string> browsers) : Exception("Another program registered the same native messaging host name.")
{
    public IReadOnlyList<string> Browsers { get; } = browsers;
}
