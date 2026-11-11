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
    /// <summary>Where AUV 0.18.5 copied the companion (D6, superseded 2026-11-11): beside settings.v1.json. Only read to offer its removal.</summary>
    public static string LegacyInstallRoot(string settingsPath) => Path.Combine(Path.GetDirectoryName(Path.GetFullPath(settingsPath))!, "browser-companion");
    /// <summary>Decision 2026-11-11: the companion lives inside this AUV install folder and is used where it is.</summary>
    /// <summary>Decision 2026-11-11: the companion lives inside this AUV install folder and is used where it is.</summary>
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
    private readonly CompanionReloadThrottle? reloads;
    private readonly CancellationTokenSource lifetime = new();
    private readonly object gate = new();
    private Connection? active;
    private Task? acceptLoop;
    private NamedPipeServerStream? listening;
    public CompanionLinkState State { get; private set; } = CompanionLinkState.NoBrowser;
    public HostHello? Host => active?.Hello;
    public string? RejectionReason { get; private set; }
    /// <summary>The last host refused for an earlier build: its browser is the one whose extension needs a reload.</summary>
    public HostHello? RejectedHost { get; private set; }
    public event Action<CompanionMessage>? Received;
    public event Action? StateChanged;

    /// <param name="reloads">0.18.6: when given, a host refused for another build is followed by one request for its extension to reload itself.</param>
    public ClaudeBrowserPipeServer(string pipeName, ClaudeCompanionManifest expected, Func<int, bool> trustedClient, Func<string> selectedBrowser, CompanionReloadThrottle? reloads = null)
    { this.pipeName = pipeName; this.expected = expected; this.trustedClient = trustedClient; this.selectedBrowser = selectedBrowser; this.reloads = reloads; }

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
            NamedPipeServerStream? stream = null;
            try
            {
                stream = new NamedPipeServerStream(pipeName, PipeDirection.InOut, 4, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
                lock (gate) { if (cancellationToken.IsCancellationRequested) { stream.Dispose(); return; } listening = stream; }
                await stream.WaitForConnectionAsync(cancellationToken);
            }
            // A cancelled wait leaves the pipe instance listening: a host could connect to it and wait for a welcome that
            // never comes. Close it, so a restarted server (after Update or a browser change) is the only one listening.
            catch (OperationCanceledException) { stream?.Dispose(); return; }
            catch (IOException) { stream?.Dispose(); if (cancellationToken.IsCancellationRequested) return; try { await Task.Delay(1000, cancellationToken); } catch (OperationCanceledException) { return; } continue; }
            catch (ObjectDisposedException) { stream?.Dispose(); return; }
            lock (gate) listening = null;
            if (cancellationToken.IsCancellationRequested) { stream.Dispose(); return; }
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
                // A browser still running an extension from an earlier build is refused. That changes the overall state only
                // while no browser is connected: found live, an outdated Edge retrying every 30 seconds hid a working Chrome.
                if (reason == "generationMismatch")
                {
                    bool idle; lock (gate) idle = active == null;
                    RejectedHost = hello;
                    if (idle) SetState(CompanionLinkState.Rejected, reason);
                    // The host keeps its connection to the extension from before an update. The extension loads from the
                    // folder AUV installs into, so asking it to reload brings in the installed build (hosts from 0.18.6 on relay this).
                    if (reloads?.TryRequest(hello.BrowserProduct) == true)
                        await CompanionFraming.WriteAsync(stream, CompanionMessageCodec.Encode(new CompanionCommand(ClaudeBrowserContract.ReloadCommand, ClaudeBrowserContract.NewRequestId())),
                            ClaudeBrowserContract.MaximumPipeFrameBytes, cancellationToken);
                }
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
                if (message is HostHello) continue;
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
        // Close the waiting pipe instance now, not when the cancelled wait gets round to it: a server started right
        // after this one (Update, a browser change) must be the only instance a host can reach.
        lock (gate) { listening?.Dispose(); listening = null; active?.Stream.Dispose(); active = null; }
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
    /// <summary>
    /// The trust rule (2026-11-11): the client is exactly &lt;packageRoot&gt;\host\AUV.BrowserHost.exe, the host inside the running
    /// AUV's own BrowserCompanion folder. A host from another AUV install, or from the 0.18.5 copy, is not accepted.
    /// </summary>
    public static Func<int, bool> InstalledHostOnly(string packageRoot) => pid => IsOwnHost(ImagePath(pid), packageRoot);
    public static bool IsOwnHost(string? imagePath, string packageRoot)
    {
        if (imagePath == null) return false;
        try { return string.Equals(Path.GetFullPath(imagePath), Path.GetFullPath(Path.Combine(packageRoot, "host", "AUV.BrowserHost.exe")), StringComparison.OrdinalIgnoreCase); }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException) { return false; }
    }
}
