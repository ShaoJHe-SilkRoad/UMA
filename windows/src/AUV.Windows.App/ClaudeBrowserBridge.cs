using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using AUV.Windows.Core;

namespace AUV.Windows.App;

public static class ClaudeBrowserPaths
{
    /// <summary>The same per-profile key PreviewInstance uses, so each preference profile has its own pipe.</summary>
    public static string Key(string settingsPath) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(settingsPath).ToUpperInvariant())))[..24];
    public static string PipeName(string settingsPath) => $"AUV.Windows.Preview.{Key(settingsPath)}.ClaudeBrowser";
    /// <summary>D6: %LOCALAPPDATA%\AUV.Windows.UI.Preview\browser-companion, beside settings.v1.json.</summary>
    public static string InstallRoot(string settingsPath) => Path.Combine(Path.GetDirectoryName(Path.GetFullPath(settingsPath))!, "browser-companion");
    public static string PackageRoot => Path.Combine(AppContext.BaseDirectory, "BrowserCompanion");
    public static ClaudeCompanionManifest? LoadManifest(string root)
    {
        try
        {
            var path = Path.Combine(root, "companion.json");
            return File.Exists(path) && new FileInfo(path).Length <= 4096 ? ClaudeCompanionManifest.Parse(File.ReadAllBytes(path)) : null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidDataException or System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException) { return null; }
    }
}

/// <summary>
/// AUV's end of the companion link: a named pipe only the current Windows user can open. A host is accepted when its
/// process is the installed AUV.BrowserHost.exe, it speaks for the expected extension origin and build, and no other
/// browser is already connected. Everything it sends is decoded against the allowlist before AUV sees it.
/// </summary>
public sealed class ClaudeBrowserPipeServer : IClaudeCompanionLink, IDisposable
{
    private readonly string pipeName;
    private readonly ClaudeCompanionManifest expected;
    private readonly Func<int, bool> trustedClient;
    private readonly Func<string> selectedBrowser;
    private readonly CancellationTokenSource lifetime = new();
    private readonly object gate = new();
    private Connection? active;
    private Task? acceptLoop;
    public CompanionLinkState State { get; private set; } = CompanionLinkState.NoBrowser;
    public HostHello? Host => active?.Hello;
    public string? RejectionReason { get; private set; }
    public event Action<CompanionMessage>? Received;
    public event Action? StateChanged;

    public ClaudeBrowserPipeServer(string pipeName, ClaudeCompanionManifest expected, Func<int, bool> trustedClient, Func<string> selectedBrowser)
    { this.pipeName = pipeName; this.expected = expected; this.trustedClient = trustedClient; this.selectedBrowser = selectedBrowser; }

    public void Start() { lock (gate) acceptLoop ??= Task.Run(() => AcceptAsync(lifetime.Token)); }

    private sealed class Connection(NamedPipeServerStream stream, HostHello hello)
    {
        public NamedPipeServerStream Stream { get; } = stream;
        public HostHello Hello { get; } = hello;
        public SemaphoreSlim WriteGate { get; } = new(1, 1);
    }

    private async Task AcceptAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            NamedPipeServerStream stream;
            try
            {
                stream = new NamedPipeServerStream(pipeName, PipeDirection.InOut, 4, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                await stream.WaitForConnectionAsync(cancellationToken);
            }
            catch (OperationCanceledException) { return; }
            catch (IOException) { try { await Task.Delay(1000, cancellationToken); } catch (OperationCanceledException) { return; } continue; }
            _ = Task.Run(() => ServeAsync(stream, cancellationToken), cancellationToken);
        }
    }

    private async Task ServeAsync(NamedPipeServerStream stream, CancellationToken cancellationToken)
    {
        Connection? connection = null;
        try
        {
            if (!ClientProcessId(stream, out var pid) || !trustedClient(pid)) return;
            var helloFrame = await CompanionFraming.ReadAsync(stream, ClaudeBrowserContract.MaximumPipeFrameBytes, cancellationToken).WaitAsync(TimeSpan.FromSeconds(5), cancellationToken);
            if (helloFrame == null || CompanionMessageCodec.DecodeFromHost(helloFrame) is not HostHello hello) return;
            var selected = selectedBrowser();
            var reason = hello.ExtensionOrigin != expected.ExtensionOrigin ? "originRejected"
                : hello.RuntimeGenerationId != expected.RuntimeGenerationId ? "generationMismatch"
                : selected is "chrome" or "edge" && hello.BrowserProduct != selected ? "browserNotSelected" : "accepted";
            lock (gate) if (reason == "accepted" && active != null) reason = "busy";
            await CompanionFraming.WriteAsync(stream, CompanionMessageCodec.Encode(new HostWelcome(reason == "accepted", reason)), ClaudeBrowserContract.MaximumPipeFrameBytes, cancellationToken);
            if (reason != "accepted")
            {
                if (reason == "generationMismatch") SetState(CompanionLinkState.Rejected, reason);
                return;
            }
            connection = new(stream, hello);
            lock (gate) active = connection;
            SetState(CompanionLinkState.Connected, null);
            while (!cancellationToken.IsCancellationRequested)
            {
                var frame = await CompanionFraming.ReadAsync(stream, ClaudeBrowserContract.MaximumPipeFrameBytes, cancellationToken);
                if (frame == null) break;
                CompanionMessage message;
                try { message = CompanionMessageCodec.DecodeFromHost(frame); }
                catch (CompanionProtocolException) { continue; }
                if (message is CompanionTrace or HostHello) continue;
                Received?.Invoke(message);
            }
        }
        catch (Exception e) when (e is IOException or TimeoutException or OperationCanceledException or CompanionProtocolException or ObjectDisposedException) { }
        finally
        {
            var wasActive = false;
            lock (gate) if (connection != null && active == connection) { active = null; wasActive = true; }
            stream.Dispose();
            if (wasActive) SetState(CompanionLinkState.NoBrowser, null);
        }
    }

    private void SetState(CompanionLinkState state, string? reason)
    {
        if (State == state && RejectionReason == reason) return;
        State = state; RejectionReason = reason; StateChanged?.Invoke();
    }

    public async Task<bool> SendAsync(CompanionMessage message, CancellationToken cancellationToken)
    {
        Connection? connection; lock (gate) connection = active;
        if (connection == null) return false;
        var bytes = CompanionMessageCodec.Encode(message);
        await connection.WriteGate.WaitAsync(cancellationToken);
        try { await CompanionFraming.WriteAsync(connection.Stream, bytes, ClaudeBrowserContract.MaximumPipeFrameBytes, cancellationToken); return true; }
        catch (Exception e) when (e is IOException or ObjectDisposedException) { return false; }
        finally { connection.WriteGate.Release(); }
    }

    public void Dispose()
    {
        lifetime.Cancel();
        lock (gate) { active?.Stream.Dispose(); active = null; }
    }

    [DllImport("kernel32.dll", SetLastError = true)] private static extern bool GetNamedPipeClientProcessId(nint pipe, out uint clientProcessId);
    private static bool ClientProcessId(NamedPipeServerStream stream, out int pid)
    {
        pid = 0;
        if (!GetNamedPipeClientProcessId(stream.SafePipeHandle.DangerousGetHandle(), out var id)) return false;
        pid = (int)id; return true;
    }

    [DllImport("kernel32.dll", SetLastError = true)] private static extern nint OpenProcess(uint access, bool inherit, int processId);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] private static extern bool QueryFullProcessImageName(nint process, int flags, StringBuilder name, ref int size);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(nint handle);
    /// <summary>The full image path of a process, or null. Uses only PROCESS_QUERY_LIMITED_INFORMATION.</summary>
    public static string? ImagePath(int pid)
    {
        var handle = OpenProcess(0x1000, false, pid);
        if (handle == 0) return null;
        try
        {
            var size = 1024; var name = new StringBuilder(size);
            return QueryFullProcessImageName(handle, 0, name, ref size) ? name.ToString() : null;
        }
        finally { CloseHandle(handle); }
    }
    /// <summary>The default trust rule: the client is AUV.BrowserHost.exe inside the installed companion's host folder.</summary>
    public static Func<int, bool> InstalledHostOnly(string installRoot) => pid =>
    {
        var path = ImagePath(pid);
        if (path == null) return false;
        var hostRoot = Path.GetFullPath(Path.Combine(installRoot, "host")) + Path.DirectorySeparatorChar;
        return Path.GetFullPath(path).StartsWith(hostRoot, StringComparison.OrdinalIgnoreCase) &&
               string.Equals(Path.GetFileName(path), "AUV.BrowserHost.exe", StringComparison.OrdinalIgnoreCase);
    };
}
