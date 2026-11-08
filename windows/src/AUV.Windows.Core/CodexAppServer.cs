using System.Diagnostics;
using System.Text.Json;

namespace AUV.Windows.Core;

public sealed class CodexRpcException(int code) : Exception("Codex local interface returned an error.") { public int Code { get; } = code; }

/// <summary>Owned read-only stdio session. Never starts threads, inference, tools or a login flow.</summary>
public sealed class CodexAppServer : IDisposable
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private Process? process;
    private int nextId;
    private string? activeExecutable;
    private readonly HashSet<string> methods = [];
    public IReadOnlySet<string> Methods => methods;
    public int? OwnedProcessId => process is { HasExited: false } ? process.Id : null;
    public string? Executable { get; private set; }
    public static string? ResolveExecutable(string? configured = null)
    {
        if (!string.IsNullOrWhiteSpace(configured)) return Path.IsPathFullyQualified(configured) && configured.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && File.Exists(configured) ? configured : null;
        var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "OpenAI", "Codex", "bin");
        try
        {
            var bundled = Directory.Exists(root) ? Directory.EnumerateDirectories(root).Select(d => new FileInfo(Path.Combine(d, "codex.exe"))).Where(f => f.Exists).OrderByDescending(f => f.LastWriteTimeUtc).FirstOrDefault()?.FullName : null;
            if (bundled != null) return bundled;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        return (Environment.GetEnvironmentVariable("PATH") ?? "").Split(Path.PathSeparator).Select(d => Path.Combine(d.Trim('"'), "codex.exe")).FirstOrDefault(File.Exists);
    }
    public static readonly TimeSpan OptionalUsageTimeout = TimeSpan.FromSeconds(5);
    private bool optionalUsageUnavailable;
    public Task<AgentPresentation> ReadAsync(string? configured, CancellationToken cancellationToken) => ReadAsync(configured, null, cancellationToken);
    public async Task<AgentPresentation> ReadAsync(string? configured, QuotaSelection? previous, CancellationToken cancellationToken)
    {
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken); timeout.CancelAfter(TimeSpan.FromSeconds(45));
        try
        {
            Executable = ResolveExecutable(configured);
            if (Executable == null) { Stop(); return ProviderData.Unavailable("codex", UiText.T("Codex executable not found. Choose the installed codex.exe in Codex settings.", "找不到 Codex 程序。请在 Codex 设置中选择已安装的 codex.exe。")); }
            if (process == null || process.HasExited || activeExecutable != Executable)
            {
                Stop(); var start = new ProcessStartInfo(Executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true };
                // 0.17.2: stdio is the documented default transport; avoid version-specific listen aliases.
                start.ArgumentList.Add("app-server");
                process = Process.Start(start) ?? throw new IOException("Could not start Codex local interface."); activeExecutable = Executable;
                optionalUsageUnavailable = false;
                _ = DiscardErrorOutput(process);
                await Request("initialize", new { clientInfo = new { name = "auv_windows", title = "AUV Windows", version = ProductInfo.Version }, capabilities = new { experimentalApi = true } }, timeout.Token).ConfigureAwait(false);
                await process.StandardInput.WriteLineAsync("{\"method\":\"initialized\"}".AsMemory(), timeout.Token).ConfigureAwait(false);
                await process.StandardInput.FlushAsync(timeout.Token).ConfigureAwait(false);
            }
            var account = await Request("account/read", new { refreshToken = false }, timeout.Token).ConfigureAwait(false);
            if (ProviderData.Text(ProviderData.Get(ProviderData.Get(account, "account"), "type")) != "chatgpt")
                return ProviderData.Unavailable("codex", UiText.T("Open Codex and sign in with ChatGPT, then refresh here.", "请打开 Codex 并用 ChatGPT 登录，然后在这里刷新。"), ConnectionState.Disconnected);
            var limits = await Request("account/rateLimits/read", null, timeout.Token).ConfigureAwait(false);
            JsonElement usage = default;
            if (!optionalUsageUnavailable)
            {
                // Optional aggregate endpoint: its failure never hides the independently verified quota.
                using var optional = CancellationTokenSource.CreateLinkedTokenSource(timeout.Token); optional.CancelAfter(OptionalUsageTimeout);
                try { usage = await Request("account/usage/read", null, optional.Token).ConfigureAwait(false); }
                catch (CodexRpcException) { optionalUsageUnavailable = true; }
                catch (Exception e) when (e is JsonException or InvalidDataException) { optionalUsageUnavailable = true; }
                catch (OperationCanceledException) when (!timeout.IsCancellationRequested)
                {
                    // A partially read response cannot be resumed safely; restart the owned session next time.
                    var limitsOnly = CodexUsageDecoder.Decode(account, limits, default, DateTimeOffset.UtcNow, previous);
                    Stop(); return limitsOnly;
                }
            }
            return CodexUsageDecoder.Decode(account, limits, usage, DateTimeOffset.UtcNow, previous);
        }
        catch { Stop(); throw; }
        finally { gate.Release(); }
    }
    private async Task<JsonElement> Request(string method, object? parameters, CancellationToken token)
    {
        methods.Add(method);
        var child = process ?? throw new IOException("Codex local interface stopped."); var id = ++nextId;
        var line = JsonSerializer.Serialize(new { id, method, @params = parameters });
        await child.StandardInput.WriteLineAsync(line.AsMemory(), token).ConfigureAwait(false); await child.StandardInput.FlushAsync(token).ConfigureAwait(false);
        while (true)
        {
            var response = await child.StandardOutput.ReadLineAsync(token).ConfigureAwait(false) ?? throw new IOException("Codex local interface exited.");
            if (response.Length > 2 * 1024 * 1024) throw new InvalidDataException("Codex response exceeded the read limit.");
            using var document = JsonDocument.Parse(response); var root = document.RootElement;
            var responseId = ProviderData.Get(root, "id"); if (responseId.ValueKind != JsonValueKind.Number || !responseId.TryGetInt32(out var value) || value != id) continue;
            var error = ProviderData.Get(root, "error");
            if (ProviderData.Object(error)) throw new CodexRpcException(ProviderData.Get(error, "code").TryGetInt32(out var code) ? code : 0);
            var result = ProviderData.Get(root, "result"); if (!ProviderData.Object(result)) throw new InvalidDataException("Invalid Codex response."); return result.Clone();
        }
    }
    private static async Task DiscardErrorOutput(Process child)
    {
        try { var buffer = new char[2048]; while (await child.StandardError.ReadAsync(buffer.AsMemory()).ConfigureAwait(false) > 0) { } }
        catch (Exception e) when (e is IOException or ObjectDisposedException or InvalidOperationException) { }
    }
    private void Stop()
    {
        var child = Interlocked.Exchange(ref process, null); activeExecutable = null; if (child == null) return;
        try { if (!child.HasExited) child.Kill(entireProcessTree: true); } catch (Exception e) when (e is InvalidOperationException or System.ComponentModel.Win32Exception) { }
        child.Dispose();
    }
    public void Dispose() => Stop();
}
