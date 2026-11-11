using System.IO;
using System.Text.Json;
using AUV.Windows.Core;
using Microsoft.Win32;

namespace AUV.Windows.App;

public enum CompanionInstallState { NotPackaged, NotInstalled, Installed, RegistrationMissing }
/// <param name="Installed">The companion set up in this AUV's folder for this preference profile (its host-config.json names this profile's pipe), or null.</param>
/// <param name="ForeignRegistrations">Browsers whose registration belongs to another program; replaced only after asking.</param>
/// <param name="AuvRegistrationsElsewhere">Browsers whose registration is AUV's own companion in another folder (another AUV install,
/// or the 0.18.5 copy under %LOCALAPPDATA%); Set Up replaces these without asking.</param>
public sealed record CompanionStatus(CompanionInstallState State, ClaudeCompanionManifest? Packaged, ClaudeCompanionManifest? Installed,
    IReadOnlyList<string> RegisteredBrowsers, IReadOnlyList<string> ForeignRegistrations, IReadOnlyList<string> AuvRegistrationsElsewhere)
{
    public bool Registered => RegisteredBrowsers.Count > 0;
}

/// <summary>
/// The companion lives inside the AUV install folder (decision 2026-11-11, replacing D6): the browser loads
/// &lt;AUV folder&gt;\BrowserCompanion\extension and runs &lt;AUV folder&gt;\BrowserCompanion\host\AUV.BrowserHost.exe. Nothing is copied.
/// Set Up writes only host-config.json and the native-host manifest beside the host, and points the per-user (HKCU)
/// Chrome and Edge keys at that manifest. A registry value pointing to another program is reported instead of replaced;
/// one pointing to AUV's own companion in another folder is replaced, since it is the same companion. Other AUV
/// folders are never modified.
/// </summary>
public sealed class ClaudeBrowserSetup(string packageRoot, string pipeName, RegistryKey? hive = null, string registryBase = "Software")
{
    public const string HostExecutable = "AUV.BrowserHost.exe";
    private readonly RegistryKey hive = hive ?? Registry.CurrentUser;
    public string PackageRoot => packageRoot;
    public string ExtensionFolder => Path.Combine(packageRoot, "extension");
    public string HostFolder => Path.Combine(packageRoot, "host");
    public string HostManifestPath => Path.Combine(HostFolder, ClaudeBrowserContract.NativeHostName + ".json");
    private string HostConfigPath => Path.Combine(HostFolder, ClaudeHostConfig.FileName);
    public static readonly (string Browser, string Path)[] Browsers =
        [("chrome", @"Google\Chrome\NativeMessagingHosts\" + ClaudeBrowserContract.NativeHostName), ("edge", @"Microsoft\Edge\NativeMessagingHosts\" + ClaudeBrowserContract.NativeHostName)];
    private string KeyPath(string relative) => registryBase + @"\" + relative;
    private static bool Same(string a, string b) => string.Equals(Path.GetFullPath(a), Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);
    private bool Ours(string? value)
    {
        try { return value != null && Path.IsPathFullyQualified(value) && Path.GetFullPath(value).StartsWith(Path.GetFullPath(packageRoot) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase); }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException) { return false; }
    }
    private string? RegisteredValue(string relative) { using var key = hive.OpenSubKey(KeyPath(relative)); return key?.GetValue(null) as string; }

    /// <summary>The host-config.json in this folder, when it is well formed and written for this preference profile.</summary>
    private ClaudeHostConfig? OwnConfig()
    {
        try
        {
            var info = new FileInfo(HostConfigPath);
            if (!info.Exists || info.Length is 0 or > 4096) return null;
            var config = ClaudeHostConfig.Parse(File.ReadAllBytes(info.FullName));
            return config.PipeName == pipeName ? config : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidDataException) { return null; }
    }

    public CompanionStatus Status()
    {
        var packaged = ClaudeBrowserPaths.LoadManifest(packageRoot);
        var installed = packaged != null && OwnConfig() is { } config && config.RuntimeGenerationId == packaged.RuntimeGenerationId && File.Exists(HostManifestPath) ? packaged : null;
        var registered = new List<string>(); var foreign = new List<string>(); var elsewhere = new List<string>();
        foreach (var (browser, path) in Browsers)
        {
            var value = RegisteredValue(path);
            if (value == null) continue;
            if (Ours(value)) { if (installed != null && Same(value, HostManifestPath)) registered.Add(browser); }
            else (IsAuvCompanion(value) ? elsewhere : foreign).Add(browser);
        }
        var state = packaged == null ? CompanionInstallState.NotPackaged
            : installed == null ? CompanionInstallState.NotInstalled
            : registered.Count == 0 ? CompanionInstallState.RegistrationMissing : CompanionInstallState.Installed;
        return new(state, packaged, installed, registered, foreign, elsewhere);
    }

    /// <summary>
    /// A registration is AUV's own companion when its host manifest is named com.silkrd.auv.claude_browser and its folder holds
    /// AUV.BrowserHost.exe and a well-formed host-config.json. Only small files are read; nothing is run.
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

    /// <summary>
    /// Start-up after an upgrade: the registration still points to another AUV install (or the 0.18.5 copy). Register this
    /// folder instead, without asking, since it is AUV's own. Returns true when it re-registered. Throws as <see cref="Install"/> does,
    /// including <see cref="ForeignRegistrationException"/> when another program holds a key.
    /// </summary>
    public bool ReRegisterIfMoved()
    {
        var status = Status();
        if (status.State == CompanionInstallState.NotPackaged || status.RegisteredBrowsers.Count == Browsers.Length) return false;
        Install(false);
        return true;
    }

    /// <summary>Fails when this AUV's folder cannot be written (for example under Program Files). Nothing is written elsewhere instead.</summary>
    public void EnsureWritable()
    {
        var probe = Path.Combine(HostFolder, ".auv-write-check-" + Guid.NewGuid().ToString("N"));
        try { using (File.Create(probe, 1, FileOptions.DeleteOnClose)) { } }
        catch (Exception e) when (e is UnauthorizedAccessException or IOException or System.Security.SecurityException) { throw new CompanionFolderNotWritableException(packageRoot, e); }
    }

    /// <summary>Registers this folder's host for Chrome and Edge. Returns the packaged manifest.</summary>
    public ClaudeCompanionManifest Install(bool replaceForeignRegistrations)
    {
        var packaged = ClaudeBrowserPaths.LoadManifest(packageRoot) ?? throw new InvalidOperationException("This copy of AUV has no browser companion package.");
        if (!File.Exists(Path.Combine(HostFolder, HostExecutable)) || !Directory.Exists(ExtensionFolder)) throw new InvalidOperationException("The browser companion package is incomplete.");
        var status = Status();
        if (status.ForeignRegistrations.Count > 0 && !replaceForeignRegistrations) throw new ForeignRegistrationException(status.ForeignRegistrations);
        EnsureWritable();
        try
        {
            WriteJson(HostConfigPath, w =>
            {
                w.WriteNumber("schemaVersion", 1); w.WriteString("pipeName", pipeName); w.WriteString("allowedOrigin", packaged.ExtensionOrigin);
                w.WriteString("runtimeGenerationID", packaged.RuntimeGenerationId); w.WriteString("hostVersion", packaged.CompanionVersion); w.WriteString("hostBuild", packaged.CompanionBuild);
            });
            WriteJson(HostManifestPath, w =>
            {
                w.WriteString("name", ClaudeBrowserContract.NativeHostName); w.WriteString("description", "AUV Browser Companion for Claude");
                w.WriteString("path", HostExecutable); w.WriteString("type", "stdio");
                w.WriteStartArray("allowed_origins"); w.WriteStringValue(packaged.ExtensionOrigin); w.WriteEndArray();
            });
        }
        catch (Exception e) when (e is UnauthorizedAccessException) { throw new CompanionFolderNotWritableException(packageRoot, e); }
        foreach (var (_, path) in Browsers)
        {
            using var key = hive.CreateSubKey(KeyPath(path), true);
            key.SetValue(null, HostManifestPath, RegistryValueKind.String);
        }
        return packaged;
    }

    /// <summary>Removes AUV's registry values that point into this folder, and the two files Set Up wrote here. The package itself stays.</summary>
    public void Remove()
    {
        foreach (var (_, path) in Browsers)
            if (Ours(RegisteredValue(path))) hive.DeleteSubKey(KeyPath(path), false);
        foreach (var file in new[] { HostConfigPath, HostManifestPath })
            try { if (File.Exists(file)) File.Delete(file); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    // ---- The 0.18.5 copy under %LOCALAPPDATA%\AUV.Windows.UI.Preview\browser-companion ----

    /// <summary>True when the folder exists and is the companion copy AUV 0.18.5 created (its companion.json, or a host build folder with AUV.BrowserHost.exe).</summary>
    public static bool IsLegacyCopy(string legacyRoot)
    {
        try
        {
            if (!Directory.Exists(legacyRoot)) return false;
            if (ClaudeBrowserPaths.LoadManifest(legacyRoot) != null) return true;
            var host = Path.Combine(legacyRoot, "host");
            return Directory.Exists(host) && Directory.EnumerateDirectories(host).Any(d => File.Exists(Path.Combine(d, HostExecutable)));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException) { return false; }
    }
    /// <summary>
    /// Deletes the 0.18.5 copy, only when it is one (see <see cref="IsLegacyCopy"/>). Called only after the person says yes.
    /// Whatever can be deleted is; a file in use (a browser still running the old helper locks its AUV.BrowserHost.exe) is
    /// left and counted. The files that make the folder recognisable as AUV's copy (companion.json and host\&lt;build&gt;\
    /// AUV.BrowserHost.exe) go last, so a later retry still recognises what is left and never deletes anything else.
    /// Folder links (junctions) inside are not followed.
    /// </summary>
    public static LegacyDeleteResult DeleteLegacyCopy(string legacyRoot)
    {
        if (!IsLegacyCopy(legacyRoot)) return new(LegacyDeleteOutcome.NotACopy, 0);
        try
        {
            var root = new DirectoryInfo(Path.GetFullPath(legacyRoot));
            var markers = new List<FileInfo>(); var folders = new List<DirectoryInfo>();
            var remaining = DeleteFiles(root, root, markers, folders);
            // With nothing else left, the markers go too; one that is in use then still marks the folder as AUV's copy.
            if (remaining == 0) foreach (var marker in markers) if (!TryDelete(marker)) remaining++;
            foreach (var folder in folders.Append(root)) // deepest first, root last; only empty ones go
                try { folder.Refresh(); if (folder.Exists && !folder.EnumerateFileSystemInfos().Any()) folder.Delete(false); }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            return remaining == 0 && !Directory.Exists(root.FullName) ? new(LegacyDeleteOutcome.Deleted, 0) : new(LegacyDeleteOutcome.Partial, Math.Max(remaining, 1));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException)
        { return new(LegacyDeleteOutcome.Partial, 1); }
    }
    private static int DeleteFiles(DirectoryInfo root, DirectoryInfo folder, List<FileInfo> markers, List<DirectoryInfo> folders)
    {
        var remaining = 0;
        foreach (var entry in folder.EnumerateFileSystemInfos())
        {
            if (entry is DirectoryInfo sub)
            {
                if (sub.Attributes.HasFlag(FileAttributes.ReparsePoint)) { remaining++; continue; } // never follow a link out of the copy
                remaining += DeleteFiles(root, sub, markers, folders);
                folders.Add(sub);
            }
            else if (entry is FileInfo file)
            {
                if (IsMarker(root, file)) markers.Add(file);
                else if (!TryDelete(file)) remaining++;
            }
        }
        return remaining;
    }
    private static bool IsMarker(DirectoryInfo root, FileInfo file)
    {
        var relative = Path.GetRelativePath(root.FullName, file.FullName).Split(Path.DirectorySeparatorChar);
        return relative is [var name] && name.Equals("companion.json", StringComparison.OrdinalIgnoreCase)
            || relative is [var host, _, var exe] && host.Equals("host", StringComparison.OrdinalIgnoreCase) && exe.Equals(HostExecutable, StringComparison.OrdinalIgnoreCase);
    }
    private static bool TryDelete(FileInfo file)
    {
        try
        {
            if (file.Attributes.HasFlag(FileAttributes.ReadOnly)) file.Attributes &= ~FileAttributes.ReadOnly;
            file.Delete(); return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return false; }
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

/// <summary>Set Up writes into the AUV folder; when it cannot (Program Files, a read-only share), it stops and says so.</summary>
public sealed class CompanionFolderNotWritableException(string folder, Exception inner)
    : IOException(UiText.T($"AUV cannot write to its own folder ({folder}), so the browser companion cannot be set up there. Move the AUV folder to a place you can write to, such as Documents or another drive, start AUV from there and choose Connect again.",
        $"AUV 无法写入自己的文件夹（{folder}），因此无法在那里设置浏览器伴侣。请把 AUV 文件夹移到你有写入权限的位置（例如“文档”或其他磁盘），从那里启动 AUV 后再选择“连接”。"), inner)
{
    public string Folder { get; } = folder;
}

public enum LegacyDeleteOutcome { NotACopy, Deleted, Partial }
/// <param name="Remaining">Files (or folder links) left because they were in use; 0 unless <see cref="LegacyDeleteOutcome.Partial"/>.</param>
public readonly record struct LegacyDeleteResult(LegacyDeleteOutcome Outcome, int Remaining);

/// <summary><see cref="Pending"/>: part of the copy was in use and is deleted later (after the browser closes, or at the next start).</summary>
public enum LegacyCleanupResult { NotNeeded, AlreadyAsked, Declined, Deleted, Pending }

/// <summary>
/// The one-time offer to delete the copy AUV 0.18.5 made under %LOCALAPPDATA%. It is asked at most once per preference
/// profile (whatever the answer), only when that folder exists and is AUV's copy, and nothing is deleted without a yes.
/// After a yes, what was in use is remembered (<see cref="ClaudeBrowserPreferences.LegacyCleanupPending"/>) and retried
/// with <see cref="Retry"/>, which again touches only that folder and only while it is still AUV's copy.
/// </summary>
public static class LegacyCleanup
{
    public static LegacyCleanupResult Offer(ClaudeBrowserPreferences preferences, string legacyRoot, Func<bool> askDelete, Action persist)
    {
        if (preferences.LegacyCleanupAsked) return LegacyCleanupResult.AlreadyAsked;
        if (!ClaudeBrowserSetup.IsLegacyCopy(legacyRoot)) return LegacyCleanupResult.NotNeeded;
        preferences.LegacyCleanupAsked = true; persist();
        if (!askDelete()) return LegacyCleanupResult.Declined;
        return Delete(preferences, legacyRoot, persist);
    }

    /// <summary>Deletes after a yes given now (the offer, or Remove in Claude settings) and remembers whatever is left.</summary>
    public static LegacyCleanupResult Delete(ClaudeBrowserPreferences preferences, string legacyRoot, Action persist)
    {
        var result = ClaudeBrowserSetup.DeleteLegacyCopy(legacyRoot);
        var pending = result.Outcome == LegacyDeleteOutcome.Partial;
        if (preferences.LegacyCleanupPending != pending) { preferences.LegacyCleanupPending = pending; persist(); }
        return result.Outcome switch { LegacyDeleteOutcome.Deleted => LegacyCleanupResult.Deleted, LegacyDeleteOutcome.Partial => LegacyCleanupResult.Pending, _ => LegacyCleanupResult.NotNeeded };
    }

    /// <summary>
    /// Finishes a clean-up the person already said yes to. Nothing happens unless one is pending; a folder that is gone or
    /// is no longer recognisably AUV's copy is left alone and the pending clean-up is forgotten.
    /// </summary>
    public static LegacyCleanupResult Retry(ClaudeBrowserPreferences preferences, string legacyRoot, Action persist)
        => preferences.LegacyCleanupPending ? Delete(preferences, legacyRoot, persist) : LegacyCleanupResult.NotNeeded;

    /// <summary>True when <paramref name="imagePath"/> is a helper inside the 0.18.5 copy (host\&lt;build&gt;\AUV.BrowserHost.exe).</summary>
    public static bool IsLegacyHost(string? imagePath, string legacyRoot)
    {
        if (imagePath == null) return false;
        try
        {
            var relative = Path.GetRelativePath(Path.GetFullPath(legacyRoot), Path.GetFullPath(imagePath)).Split(Path.DirectorySeparatorChar);
            return relative is [var host, var build, var exe] && host.Equals("host", StringComparison.OrdinalIgnoreCase) && build != ".."
                && exe.Equals(ClaudeBrowserSetup.HostExecutable, StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException) { return false; }
    }
}

/// <summary>
/// Waits for the old helpers still running from the 0.18.5 copy (a browser keeps one running while it is open) and calls
/// back once all of them have exited, so a pending clean-up can be retried then. Only AUV.BrowserHost processes whose
/// image is inside that copy are watched; nothing is ever stopped.
/// </summary>
public sealed class LegacyHostWatcher(string legacyRoot, Action allExited) : IDisposable
{
    private readonly List<System.Diagnostics.Process> watched = [];
    private int left, fired, disposed;

    /// <summary>Starts watching; returns how many old helpers are running. With none, nothing is called back.</summary>
    public int Start()
    {
        foreach (var process in System.Diagnostics.Process.GetProcessesByName(Path.GetFileNameWithoutExtension(ClaudeBrowserSetup.HostExecutable)))
        {
            if (!LegacyCleanup.IsLegacyHost(ClaudeBrowserPipeServer.ImagePath(process.Id), legacyRoot)) { process.Dispose(); continue; }
            try { process.EnableRaisingEvents = true; }
            catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception or NotSupportedException) { process.Dispose(); continue; }
            watched.Add(process);
        }
        left = watched.Count;
        foreach (var process in watched)
        {
            var counted = 0;
            void Exited() { if (Interlocked.Exchange(ref counted, 1) == 0 && Interlocked.Decrement(ref left) == 0 && Volatile.Read(ref disposed) == 0 && Interlocked.Exchange(ref fired, 1) == 0) allExited(); }
            process.Exited += (_, _) => Exited();
            try { if (process.HasExited) Exited(); } catch (InvalidOperationException) { Exited(); }
        }
        return watched.Count;
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0) return;
        foreach (var process in watched) process.Dispose();
        watched.Clear();
    }
}
