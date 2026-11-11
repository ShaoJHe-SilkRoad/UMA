using System.Diagnostics;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text.Json;
using AUV.Windows.Core;

namespace AUV.Windows.BrowserHost;

/// <summary>
/// Chrome or Edge starts this program when AUV's companion extension calls connectNative. It checks that the caller is
/// the configured extension, then relays allowlisted messages: extension (stdin/stdout) ⇄ AUV (named pipe).
/// It never writes a file and logs only fixed codes to stderr, which the browser shows only with --enable-logging.
/// </summary>
internal static class Program
{
    internal static readonly TimeSpan ReconnectDelay = TimeSpan.FromSeconds(5);
    internal static readonly TimeSpan RejectedDelay = TimeSpan.FromSeconds(30);

    private static async Task<int> Main(string[] args)
    {
        ClaudeHostConfig config;
        try { config = HostConfig.Load(Path.Combine(AppContext.BaseDirectory, "host-config.json")); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidDataException or KeyNotFoundException)
        { Log("config-unavailable"); return 3; }
        // The browser passes the caller's origin first; on Windows it also passes --parent-window.
        var origin = args.FirstOrDefault(a => a.StartsWith("chrome-extension://", StringComparison.Ordinal));
        if (origin != config.AllowedOrigin) { Log("origin-rejected"); return 2; }
        var relay = new Relay(config, BrowserProduct.Detect());
        return await relay.RunAsync();
    }

    internal static void Log(string code)
    {
        try { Console.Error.WriteLine("AUV.BrowserHost: " + code); } catch (IOException) { }
    }
}

internal static class HostConfig
{
    public static ClaudeHostConfig Load(string path)
    {
        var info = new FileInfo(path);
        if (!info.Exists || info.Length is 0 or > 4096) throw new InvalidDataException();
        return ClaudeHostConfig.Parse(File.ReadAllBytes(path));
    }
}

internal sealed class Relay(ClaudeHostConfig config, string browserProduct)
{
    private readonly Stream stdin = Console.OpenStandardInput();
    private readonly Stream stdout = Console.OpenStandardOutput();
    private readonly SemaphoreSlim stdoutGate = new(1, 1);
    private readonly SemaphoreSlim pipeGate = new(1, 1);
    private readonly CancellationTokenSource lifetime = new();
    private volatile NamedPipeClientStream? pipe;

    public async Task<int> RunAsync()
    {
        var link = Task.Run(() => MaintainPipeAsync(lifetime.Token));
        try { await ReadExtensionAsync(); }
        finally { lifetime.Cancel(); pipe?.Dispose(); }
        try { await link; } catch (OperationCanceledException) { }
        return 0;
    }

    private async Task ToExtensionAsync(CompanionMessage message)
    {
        var bytes = CompanionMessageCodec.Encode(message);
        await stdoutGate.WaitAsync();
        try { await CompanionFraming.WriteAsync(stdout, bytes, ClaudeBrowserContract.MaximumMessageBytes, CancellationToken.None); }
        finally { stdoutGate.Release(); }
    }

    /// <summary>Extension → AUV. The browser closes stdin when the extension's port goes away; then this host exits.</summary>
    private async Task ReadExtensionAsync()
    {
        while (true)
        {
            byte[]? frame;
            try { frame = await CompanionFraming.ReadAsync(stdin, ClaudeBrowserContract.MaximumMessageBytes, CancellationToken.None); }
            catch (CompanionProtocolException e) { Program.Log(e.Code); return; }
            catch (IOException) { return; }
            if (frame == null) return;
            CompanionMessage message;
            try { message = CompanionMessageCodec.DecodeFromExtension(frame); }
            catch (CompanionProtocolException e) { Program.Log("extension-" + e.Code); continue; }
            // The extension's own liveness check is answered here: it proves this host is alive and says whether AUV is.
            if (message is CompanionPing) { await ToExtensionAsync(new HostStatus(pipe != null)); continue; }
            var current = pipe;
            if (current == null) continue;
            await pipeGate.WaitAsync();
            try { await CompanionFraming.WriteAsync(current, frame, ClaudeBrowserContract.MaximumPipeFrameBytes, lifetime.Token); }
            catch (Exception e) when (e is IOException or ObjectDisposedException or OperationCanceledException) { Program.Log("pipe-write-failed"); }
            finally { pipeGate.Release(); }
        }
    }

    private async Task RelayReloadRequestAsync(NamedPipeClientStream client, CancellationToken cancellationToken)
    {
        try
        {
            var frame = await CompanionFraming.ReadAsync(client, ClaudeBrowserContract.MaximumPipeFrameBytes, cancellationToken).WaitAsync(TimeSpan.FromSeconds(2), cancellationToken);
            if (frame != null && CompanionMessageCodec.DecodeFromApp(frame) is CompanionCommand { Command: ClaudeBrowserContract.ReloadCommand } reload)
            { Program.Log("reload-requested"); await ToExtensionAsync(reload); }
        }
        catch (Exception e) when (e is IOException or TimeoutException or CompanionProtocolException or ObjectDisposedException) { }
    }

    /// <summary>Connects to AUV's pipe and keeps reconnecting while the browser keeps this host running.</summary>
    private async Task MaintainPipeAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            var delay = Program.ReconnectDelay;
            var client = new NamedPipeClientStream(".", config.PipeName, PipeDirection.InOut, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
            try
            {
                await client.ConnectAsync(2000, cancellationToken);
                var hello = CompanionMessageCodec.Encode(new HostHello(config.HostVersion, config.HostBuild, config.AllowedOrigin, browserProduct, config.RuntimeGenerationId));
                await CompanionFraming.WriteAsync(client, hello, ClaudeBrowserContract.MaximumPipeFrameBytes, cancellationToken);
                var welcomeFrame = await CompanionFraming.ReadAsync(client, ClaudeBrowserContract.MaximumPipeFrameBytes, cancellationToken)
                    .WaitAsync(TimeSpan.FromSeconds(5), cancellationToken);
                if (welcomeFrame == null || CompanionMessageCodec.DecodeFromApp(welcomeFrame) is not HostWelcome welcome) throw new IOException();
                if (!welcome.Accepted)
                {
                    Program.Log("welcome-" + welcome.Reason); delay = Program.RejectedDelay;
                    // 0.18.6: AUV refuses a host from another build, and may follow the refusal with one request for the
                    // extension to reload itself from its folder (which then holds the build AUV installed). Nothing else is relayed.
                    if (welcome.Reason == "generationMismatch") await RelayReloadRequestAsync(client, cancellationToken);
                }
                else pipe = client;
                if (pipe == client) await ToExtensionAsync(new HostStatus(true));
                while (pipe == client && !cancellationToken.IsCancellationRequested)
                {
                    var frame = await CompanionFraming.ReadAsync(client, ClaudeBrowserContract.MaximumPipeFrameBytes, cancellationToken);
                    if (frame == null) break;
                    CompanionMessage message;
                    try { message = CompanionMessageCodec.DecodeFromApp(frame); }
                    catch (CompanionProtocolException e) { Program.Log("app-" + e.Code); continue; }
                    if (message is CompanionCommand or CompanionPing) await ToExtensionAsync(message);
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { return; }
            catch (Exception e) when (e is IOException or TimeoutException or OperationCanceledException or CompanionProtocolException or UnauthorizedAccessException) { }
            finally
            {
                var wasConnected = pipe == client;
                pipe = null; client.Dispose();
                if (wasConnected && !cancellationToken.IsCancellationRequested)
                    try { await ToExtensionAsync(new HostStatus(false)); } catch (IOException) { }
            }
            try { await Task.Delay(delay, cancellationToken); } catch (OperationCanceledException) { return; }
        }
    }
}

/// <summary>Which browser started this host, from the parent process image name. Nothing else about the browser is read.</summary>
internal static class BrowserProduct
{
    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessBasicInformation { public nint Reserved1; public nint PebBaseAddress; public nint Reserved2a; public nint Reserved2b; public nint UniqueProcessId; public nint InheritedFromUniqueProcessId; }
    [DllImport("ntdll.dll")] private static extern int NtQueryInformationProcess(nint process, int informationClass, ref ProcessBasicInformation information, int length, out int returned);
    public static string Detect()
    {
        // Chrome and Edge start native hosts through "cmd.exe /d /s /c", so the browser is the parent of that cmd.exe.
        try
        {
            using var self = Process.GetCurrentProcess();
            var current = self.Id;
            for (var level = 0; level < 2; level++)
            {
                var parentId = ParentOf(current);
                if (parentId is not int id) return "unknown";
                using var parent = Process.GetProcessById(id);
                switch (parent.ProcessName.ToLowerInvariant())
                {
                    case "chrome": return "chrome";
                    case "msedge": return "edge";
                    case "cmd": current = id; continue;
                    default: return "unknown";
                }
            }
            return "unknown";
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception) { return "unknown"; }
    }
    private static int? ParentOf(int processId)
    {
        using var process = Process.GetProcessById(processId);
        var info = new ProcessBasicInformation();
        return NtQueryInformationProcess(process.Handle, 0, ref info, Marshal.SizeOf<ProcessBasicInformation>(), out _) == 0 ? (int)info.InheritedFromUniqueProcessId : null;
    }
}
