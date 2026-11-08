using System.Globalization;
using System.Text.Json;

namespace AUV.Windows.Core;

/// <summary>Claude browser sync settings. Missing in 0.18.4 files, so these initializers are the upgrade defaults (D15: off).</summary>
public sealed class ClaudeBrowserPreferences
{
    public static readonly string[] Browsers = ["auto", "chrome", "edge"];
    public static readonly string[] PlacementChoices = ["auto", "backgroundTab", "minimizedWindow"];
    public bool Enabled { get; set; }
    public string Browser { get; set; } = "auto";
    public string Placement { get; set; } = "auto";
    public bool AskToOpenBrowser { get; set; } = true;
    public string? InstalledBuild { get; set; }
    public void Normalize()
    {
        if (!Browsers.Contains(Browser)) Browser = "auto";
        if (!PlacementChoices.Contains(Placement)) Placement = "auto";
        if (InstalledBuild != null && (InstalledBuild.Length is 0 or > 32 || !InstalledBuild.All(char.IsAsciiDigit))) InstalledBuild = null;
    }
    /// <summary>The placement sent with a read; "auto" lets the extension choose from the browser's windows (D7).</summary>
    public string? CommandPlacement => Placement == "auto" ? null : Placement;
}

/// <summary>The packaged companion's identity (BrowserCompanion\companion.json). It holds no secret.</summary>
public sealed record ClaudeCompanionManifest(string ExtensionId, string RuntimeGenerationId, string CompanionVersion, string CompanionBuild)
{
    public string ExtensionOrigin => ClaudeBrowserContract.ExtensionOrigin(ExtensionId);
    public static ClaudeCompanionManifest Parse(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length is 0 or > 4096) throw new InvalidDataException("Companion manifest has an invalid size.");
        using var document = JsonDocument.Parse(bytes.ToArray());
        var root = document.RootElement;
        string[] keys = ["schemaVersion", "extensionId", "runtimeGenerationID", "companionVersion", "companionBuild"];
        if (root.ValueKind != JsonValueKind.Object || root.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal).SequenceEqual(keys.Order(StringComparer.Ordinal)) == false)
            throw new InvalidDataException("Companion manifest has unexpected fields.");
        string Text(string key) => root.GetProperty(key).ValueKind == JsonValueKind.String ? root.GetProperty(key).GetString()! : throw new InvalidDataException("Companion manifest field is not text.");
        if (root.GetProperty("schemaVersion").ValueKind != JsonValueKind.Number || root.GetProperty("schemaVersion").GetInt32() != 1) throw new InvalidDataException("Unsupported companion manifest.");
        var manifest = new ClaudeCompanionManifest(Text("extensionId"), Text("runtimeGenerationID").ToLowerInvariant(), Text("companionVersion"), Text("companionBuild"));
        if (!ClaudeBrowserContract.IsExtensionId(manifest.ExtensionId) || !ClaudeBrowserContract.IsUuid(manifest.RuntimeGenerationId) ||
            manifest.CompanionVersion.Length is 0 or > 32 || manifest.CompanionBuild.Length is 0 or > 32 || !manifest.CompanionBuild.All(char.IsAsciiDigit))
            throw new InvalidDataException("Companion manifest values are invalid.");
        return manifest;
    }
    public byte[] ToJson()
    {
        using var stream = new MemoryStream();
        using (var w = new Utf8JsonWriter(stream, new JsonWriterOptions { Indented = true }))
        {
            w.WriteStartObject(); w.WriteNumber("schemaVersion", 1); w.WriteString("extensionId", ExtensionId); w.WriteString("runtimeGenerationID", RuntimeGenerationId);
            w.WriteString("companionVersion", CompanionVersion); w.WriteString("companionBuild", CompanionBuild); w.WriteEndObject();
        }
        return stream.ToArray();
    }
}

public enum CompanionLinkState { NoBrowser, Connected, Rejected }

/// <summary>AUV's side of the connection to the native host (the named pipe in production, a fake in tests).</summary>
public interface IClaudeCompanionLink
{
    CompanionLinkState State { get; }
    HostHello? Host { get; }
    string? RejectionReason { get; }
    event Action<CompanionMessage>? Received;
    event Action? StateChanged;
    Task<bool> SendAsync(CompanionMessage message, CancellationToken cancellationToken);
}

public enum ClaudeSyncOutcome { Success, NotConnected, UpdateRequired, CompanionSilent, PermissionRequired, SignInRequired, PageUnreadable, LayoutUnsupported, PageTimedOut, TabLost, Busy }
public sealed record ClaudeSyncResult(ClaudeSyncOutcome Outcome, CompanionObservation? Observation = null, string? ProviderFailureReason = null, int Attempts = 0, string? BrowserProduct = null)
{
    public bool Retryable => Outcome is ClaudeSyncOutcome.PageTimedOut or ClaudeSyncOutcome.PageUnreadable or ClaudeSyncOutcome.TabLost or ClaudeSyncOutcome.Busy;
}

/// <summary>Mac 0.18.4 timings: handshake waits, a 35-second read, a retry 20 seconds after the sync started.</summary>
public sealed record CompanionTimings(TimeSpan Handshake, TimeSpan Read, TimeSpan RetryAfter, TimeSpan MaximumObservationAge, TimeSpan MaximumFutureSkew)
{
    public static CompanionTimings Default { get; } = new(TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(35), TimeSpan.FromSeconds(20), TimeSpan.FromMinutes(5), TimeSpan.FromSeconds(30));
}

/// <summary>
/// AUV coordinates every read, as the Mac Safari Bridge Host does: one sync at a time; wake, qualify, read, and close on timeout.
/// Only a terminal packet for a read AUV started, with an observation ID not seen before, is accepted.
/// </summary>
public sealed class ClaudeCompanionCoordinator : IDisposable
{
    private readonly IClaudeCompanionLink link;
    private readonly ClaudeCompanionManifest expected;
    private readonly CompanionTimings timings;
    private readonly Func<DateTimeOffset> now;
    private readonly object gate = new();
    private readonly List<(Func<CompanionMessage, bool> Match, TaskCompletionSource<CompanionMessage> Done)> waiters = [];
    private readonly LinkedList<string> seenObservations = new();
    private Task<ClaudeSyncResult>? inFlight;
    public DateTimeOffset? SilentSince { get; private set; }
    public int ConsecutiveSilent { get; private set; }
    public int AcceptedObservations { get; private set; }
    public event Action<CompanionSyncRequest>? SyncRequested;
    public ClaudeCompanionCoordinator(IClaudeCompanionLink link, ClaudeCompanionManifest expected, CompanionTimings? timings = null, Func<DateTimeOffset>? now = null)
    {
        this.link = link; this.expected = expected; this.timings = timings ?? CompanionTimings.Default; this.now = now ?? (() => DateTimeOffset.UtcNow);
        link.Received += OnReceived;
    }
    public ClaudeCompanionManifest Expected => expected;
    public void Dispose() { link.Received -= OnReceived; lock (gate) { foreach (var w in waiters) w.Done.TrySetCanceled(); waiters.Clear(); } }

    private void OnReceived(CompanionMessage message)
    {
        if (message is CompanionSyncRequest request) { SyncRequested?.Invoke(request); return; }
        lock (gate)
        {
            for (var i = waiters.Count - 1; i >= 0; i--)
                if (waiters[i].Match(message)) { waiters[i].Done.TrySetResult(message); waiters.RemoveAt(i); }
        }
    }

    public Task<ClaudeSyncResult> SyncAsync(string? placement, CancellationToken cancellationToken)
    {
        lock (gate)
        {
            if (inFlight is { IsCompleted: false }) return inFlight;
            return inFlight = RunAsync(placement, cancellationToken);
        }
    }

    private async Task<CompanionMessage?> ExchangeAsync(CompanionCommand command, Func<CompanionMessage, bool> match, TimeSpan timeout, CancellationToken cancellationToken)
    {
        var done = new TaskCompletionSource<CompanionMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (gate) waiters.Add((match, done));
        try
        {
            if (!await link.SendAsync(command, cancellationToken)) return null;
            var winner = await Task.WhenAny(done.Task, Task.Delay(timeout, cancellationToken));
            cancellationToken.ThrowIfCancellationRequested();
            return winner == done.Task ? await done.Task : null;
        }
        finally { lock (gate) waiters.RemoveAll(w => w.Done == done); }
    }

    private async Task<ClaudeSyncResult> RunAsync(string? placement, CancellationToken cancellationToken)
    {
        var started = now();
        var product = link.Host?.BrowserProduct;
        if (link.State == CompanionLinkState.Rejected) return new(link.RejectionReason == "generationMismatch" ? ClaudeSyncOutcome.UpdateRequired : ClaudeSyncOutcome.NotConnected, BrowserProduct: product);
        if (link.State != CompanionLinkState.Connected) return new(ClaudeSyncOutcome.NotConnected);
        var handshake = await HandshakeAsync(cancellationToken);
        if (handshake != null) return handshake with { BrowserProduct = product };
        var first = await ReadOnceAsync(placement, cancellationToken);
        if (first.Outcome == ClaudeSyncOutcome.Success || !first.Retryable) return first with { Attempts = 1, BrowserProduct = product };
        // Mac 0.18.4: one retry, 20 seconds after the sync started.
        var wait = started + timings.RetryAfter - now();
        if (wait > TimeSpan.Zero) await Task.Delay(wait, cancellationToken);
        var second = await ReadOnceAsync(placement, cancellationToken);
        return second with { Attempts = 2, BrowserProduct = product };
    }

    private async Task<ClaudeSyncResult?> HandshakeAsync(CancellationToken cancellationToken)
    {
        var id = ClaudeBrowserContract.NewRequestId();
        var ready = await ExchangeAsync(new(ClaudeBrowserContract.WakeCommand, id), m => m is CompanionEvent { Status: "extensionBackgroundReady" } e && e.RequestId == id, timings.Handshake, cancellationToken);
        if (ready is not CompanionEvent { Identity: { } identity }) return Silent();
        if (!Matches(identity)) return new(ClaudeSyncOutcome.UpdateRequired);
        var bridge = await ExchangeAsync(new(ClaudeBrowserContract.QualifyCommand, id), m => m is CompanionEvent { Status: "bridgeReady" } e && e.RequestId == id, timings.Handshake, cancellationToken);
        if (bridge is not CompanionEvent { Identity: { } confirmed }) return Silent();
        if (!Matches(confirmed)) return new(ClaudeSyncOutcome.UpdateRequired);
        ConsecutiveSilent = 0; SilentSince = null;
        return null;
    }
    private ClaudeSyncResult Silent() { ConsecutiveSilent++; SilentSince ??= now(); return new(ClaudeSyncOutcome.CompanionSilent); }
    private bool Matches(CompanionIdentity identity) =>
        identity.ExtensionIdentifier == expected.ExtensionId && identity.RuntimeGenerationId == expected.RuntimeGenerationId &&
        identity.CompanionVersion == expected.CompanionVersion && identity.CompanionBuild == expected.CompanionBuild;

    private async Task<ClaudeSyncResult> ReadOnceAsync(string? placement, CancellationToken cancellationToken)
    {
        var id = ClaudeBrowserContract.NewRequestId();
        var reply = await ExchangeAsync(new(ClaudeBrowserContract.RefreshCommand, id, Placement: placement),
            m => m is CompanionTerminal t && t.RequestId == id || m is CompanionEvent e && e.RequestId == id && ClaudeBrowserContract.FailureStatuses.Contains(e.Status),
            timings.Read, cancellationToken);
        if (reply == null)
        {
            // The read never finished: ask the companion to close the tab it opened for it.
            _ = link.SendAsync(new CompanionCommand(ClaudeBrowserContract.CloseCommand, ClaudeBrowserContract.NewRequestId(), id), CancellationToken.None);
            return new(ClaudeSyncOutcome.PageTimedOut);
        }
        if (reply is CompanionEvent busy) return new(busy.Status == "usageUnavailable" ? ClaudeSyncOutcome.Busy : ClaudeSyncOutcome.TabLost);
        var terminal = (CompanionTerminal)reply;
        if (terminal.RuntimeGenerationId != expected.RuntimeGenerationId) return new(ClaudeSyncOutcome.UpdateRequired);
        if (terminal.Status == "refreshCompleted")
        {
            var observation = terminal.Observation!; var at = now();
            lock (gate)
            {
                if (seenObservations.Contains(terminal.ObservationId!)) return new(ClaudeSyncOutcome.PageUnreadable);
                seenObservations.AddLast(terminal.ObservationId!); if (seenObservations.Count > 64) seenObservations.RemoveFirst();
            }
            if (observation.ObservedAt < at - timings.MaximumObservationAge || observation.ObservedAt > at + timings.MaximumFutureSkew) return new(ClaudeSyncOutcome.PageUnreadable);
            AcceptedObservations++;
            return new(ClaudeSyncOutcome.Success, observation);
        }
        var reason = terminal.ProviderFailureReason;
        return terminal.Status switch
        {
            "permissionRequired" => new(ClaudeSyncOutcome.PermissionRequired, ProviderFailureReason: reason),
            "signInRequired" => new(ClaudeSyncOutcome.SignInRequired, ProviderFailureReason: reason),
            "usageUnavailable" when reason == "PROVIDER_STRUCTURE_UNSUPPORTED" => new(ClaudeSyncOutcome.LayoutUnsupported, ProviderFailureReason: reason),
            "routeRejected" or "usageUnavailable" => new(ClaudeSyncOutcome.PageUnreadable, ProviderFailureReason: reason),
            "tabUnavailable" => new(ClaudeSyncOutcome.PageTimedOut, ProviderFailureReason: reason),
            _ => new(ClaudeSyncOutcome.TabLost, ProviderFailureReason: reason)
        };
    }
}

public static class ClaudeBrowserPresentation
{
    public static string BrowserName(string? product) => product switch { "edge" => "Edge", "chrome" => "Chrome", _ => UiText.T("browser", "浏览器") };
    public static AgentPresentation Success(CompanionObservation observation, string? browserProduct, DateTimeOffset now, QuotaSelection? previous)
    {
        var windows = new[]
        {
            observation.FiveHour is { } five ? new QuotaWindow("claude.fiveHour", 300, Math.Round(100 - five.UsedPercentage, 1), five.ResetAt) : null,
            observation.WeeklyAllModels is { } week ? new QuotaWindow("claude.weekly", 10080, Math.Round(100 - week.UsedPercentage, 1), week.ResetAt) : null
        }.OfType<QuotaWindow>().ToArray();
        var selectedId = QuotaWindowPolicy.Select(windows, previous, now);
        var primary = windows.FirstOrDefault(w => w.Id == selectedId);
        var secondary = windows.FirstOrDefault(w => !ReferenceEquals(w, primary));
        string Label(QuotaWindow? w) => w?.Label ?? UiText.T("Window unavailable", "窗口不可用");
        var browser = BrowserName(browserProduct);
        var source = UiText.T($"{browser} companion · claude.ai official Usage page", $"{browser} 伴侣 · claude.ai 官方用量页");
        var card = new AllowanceCard("claude", "Claude", "✳", null, primary != null ? AllowanceKind.Percentage : AllowanceKind.Unavailable, primary?.Remaining, null,
            Label(primary), source, ProviderData.Observed(observation.ObservedAt), ConnectionState.Connected)
        { WindowMinutes = primary?.Minutes, ResetsAt = primary?.ResetsAt, ObservedAt = observation.ObservedAt };
        var usage = new UsageSnapshot(windows.FirstOrDefault(w => w.Minutes == 10080)?.Remaining, windows.FirstOrDefault(w => w.Minutes == 300)?.Remaining, null, null, null, []);
        return new("claude", "Claude", "✳", usage, false, card, UiText.T("Other · ", "另一窗口 · ") + Label(secondary),
            UsageSnapshot.RemainingText(secondary?.Remaining), UiText.T("claude.ai Usage page · plan-limit percentages only", "claude.ai 用量页 · 仅套餐额度百分比"))
        { Selection = new(selectedId, windows), Windows = windows };
    }

    public static string Message(ClaudeSyncOutcome outcome, string? browserProduct)
    {
        var browser = BrowserName(browserProduct);
        return outcome switch
        {
            ClaudeSyncOutcome.NotConnected => UiText.T("Waiting for Chrome or Edge with the AUV companion. Open the browser to sync Claude.", "正在等待装有 AUV 伴侣的 Chrome 或 Edge。打开浏览器后即可同步 Claude。"),
            ClaudeSyncOutcome.UpdateRequired => UiText.T("The browser companion needs an update. Open Claude settings to update it.", "浏览器伴侣需要更新，请在 Claude 设置中更新。"),
            ClaudeSyncOutcome.CompanionSilent => UiText.T($"The browser companion is not answering. Reload it on {browser}'s extensions page, or restart {browser}.", $"浏览器伴侣没有响应。请在 {browser} 的扩展页重新加载它，或重启 {browser}。"),
            ClaudeSyncOutcome.PermissionRequired => UiText.T($"The companion needs access to claude.ai. Allow site access for AUV Companion in {browser}'s extension settings, then refresh.", $"伴侣需要访问 claude.ai。请在 {browser} 的扩展设置中允许 AUV 伴侣访问该网站，然后刷新。"),
            ClaudeSyncOutcome.SignInRequired => UiText.T($"Sign in to claude.ai in {browser}, then refresh.", $"请在 {browser} 中登录 claude.ai，然后刷新。"),
            ClaudeSyncOutcome.LayoutUnsupported => UiText.T("Claude's Usage page layout is not recognized, so no figures are shown.", "无法识别 Claude 用量页的布局，因此不显示数字。"),
            ClaudeSyncOutcome.PageUnreadable => UiText.T("Claude's Usage page could not be read. AUV tries again at the next sync.", "无法读取 Claude 用量页。AUV 会在下次同步时重试。"),
            ClaudeSyncOutcome.PageTimedOut or ClaudeSyncOutcome.TabLost or ClaudeSyncOutcome.Busy => UiText.T("The Usage page did not answer in time. AUV tries again at the next sync.", "用量页没有及时响应。AUV 会在下次同步时重试。"),
            _ => ""
        };
    }

    public static AgentPresentation Failure(ClaudeSyncOutcome outcome, string? browserProduct) =>
        ProviderData.Unavailable("claude", Message(outcome, browserProduct), outcome switch
        {
            ClaudeSyncOutcome.NotConnected or ClaudeSyncOutcome.UpdateRequired or ClaudeSyncOutcome.SignInRequired or ClaudeSyncOutcome.PermissionRequired => ConnectionState.Disconnected,
            ClaudeSyncOutcome.CompanionSilent => ConnectionState.Reconnecting,
            _ => ConnectionState.Failed
        });

    public static string Disabled => UiText.T("Browser sync is off. Turn it on in Claude settings to read Claude's exact figures from claude.ai.", "浏览器同步已关闭。在 Claude 设置中开启后，可从 claude.ai 读取 Claude 的精确读数。");
    public static string NotPackaged => UiText.T("This copy of AUV has no browser companion package.", "这份 AUV 不含浏览器伴侣安装包。");
    public static string Syncing => UiText.T("Syncing exact figures…", "正在同步精确读数…");
    public static string FormatBuild(DateTimeOffset at) => at.ToString("yyyyMMddHH", CultureInfo.InvariantCulture);
}
