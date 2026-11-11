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
    /// <summary>0.18.6 checklist step 2: browsers whose companion has passed a handshake ("chrome", "edge"). Missing before 0.18.6: empty.</summary>
    public List<string> LoadedBrowsers { get; set; } = [];
    /// <summary>0.18.6 checklist step 3: an exact reading has been accepted at least once. Missing before 0.18.6: false.</summary>
    public bool ExactReadingSeen { get; set; }
    /// <summary>The extension folder the checklist's step 2 was ticked for. Each AUV install has its own folder, so a new one starts step 2 again. Default: null.</summary>
    public string? LoadedFolder { get; set; }
    /// <summary>The one-time question about deleting the 0.18.5 copy under %LOCALAPPDATA% has been asked (whatever the answer). Default: false.</summary>
    public bool LegacyCleanupAsked { get; set; }
    /// <summary>The person said yes to deleting the 0.18.5 copy but some of it was in use (a browser still ran its helper); the rest is retried at start-up and when that helper exits. Default: false.</summary>
    public bool LegacyCleanupPending { get; set; }
    /// <summary>Step 2 was ticked for another AUV folder than <paramref name="currentFolder"/> (or for an unknown one): load the extension again from this one.</summary>
    public bool LoadedElsewhere(string currentFolder)
    {
        if (LoadedBrowsers.Count == 0) return false;
        if (LoadedFolder is not { } folder) return true;
        try { return !string.Equals(Path.GetFullPath(folder), Path.GetFullPath(currentFolder), StringComparison.OrdinalIgnoreCase); }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException) { return true; }
    }
    /// <summary>The browsers step 2 counts for <paramref name="currentFolder"/>.</summary>
    public IReadOnlyList<string> LoadedIn(string currentFolder) => LoadedElsewhere(currentFolder) ? [] : LoadedBrowsers;
    /// <summary>A browser passed the handshake with this AUV's build, so it now loads the extension from <paramref name="currentFolder"/>. Returns true when something changed.</summary>
    public bool MarkLoaded(string? product, string currentFolder)
    {
        if (product is not ("chrome" or "edge" or "unknown")) return false;
        var changed = false;
        if (LoadedElsewhere(currentFolder) || LoadedFolder == null) { LoadedBrowsers = []; LoadedFolder = currentFolder; changed = true; }
        if (!LoadedBrowsers.Contains(product)) { LoadedBrowsers.Add(product); LoadedBrowsers.Sort(StringComparer.Ordinal); changed = true; }
        return changed;
    }
    public void Normalize()
    {
        if (LoadedFolder is { Length: 0 or > 1024 }) LoadedFolder = null;
        if (!Browsers.Contains(Browser)) Browser = "auto";
        if (!PlacementChoices.Contains(Placement)) Placement = "auto";
        LoadedBrowsers = (LoadedBrowsers ?? []).Where(b => b is "chrome" or "edge" or "unknown").Distinct().Order(StringComparer.Ordinal).ToList();
        if (InstalledBuild != null && (InstalledBuild.Length is 0 or > 32 || !InstalledBuild.All(char.IsAsciiDigit))) InstalledBuild = null;
    }
    /// <summary>The placement sent with a read; "auto" lets the extension choose from the browser's windows (D7).</summary>
    [System.Text.Json.Serialization.JsonIgnore] public string? CommandPlacement => Placement == "auto" ? null : Placement;
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
    HostHello? RejectedHost { get; }
    event Action<CompanionMessage>? Received;
    event Action? StateChanged;
    Task<bool> SendAsync(CompanionMessage message, CancellationToken cancellationToken);
}

public enum ClaudeSyncOutcome { Success, NotConnected, UpdateRequired, CompanionSilent, PermissionRequired, SignInRequired, PageUnreadable, LayoutUnsupported, PageTimedOut, TabLost, Busy }
public sealed record ClaudeSyncResult(ClaudeSyncOutcome Outcome, CompanionObservation? Observation = null, string? ProviderFailureReason = null, int Attempts = 0, string? BrowserProduct = null)
{
    /// <summary>AUV asked the extension to reload itself (an identity from another build was seen).</summary>
    public bool ReloadRequested { get; init; }
    public bool Retryable => Outcome is ClaudeSyncOutcome.PageTimedOut or ClaudeSyncOutcome.PageUnreadable or ClaudeSyncOutcome.TabLost or ClaudeSyncOutcome.Busy;
}

/// <summary>Mac 0.18.4 timings: handshake waits, a 35-second read, a retry 20 seconds after the sync started.</summary>
public sealed record CompanionTimings(TimeSpan Handshake, TimeSpan Read, TimeSpan RetryAfter, TimeSpan MaximumObservationAge, TimeSpan MaximumFutureSkew)
{
    public static CompanionTimings Default { get; } = new(TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(35), TimeSpan.FromSeconds(20), TimeSpan.FromMinutes(5), TimeSpan.FromSeconds(30));
}

/// <summary>
/// 0.18.6: how often AUV may ask one browser's extension to reload itself. Shared by the pipe (a host from another build)
/// and the coordinator (a connected extension reporting another build), so a browser is asked at most once per spacing.
/// The extension keeps its own spacing as well.
/// </summary>
public sealed class CompanionReloadThrottle(TimeSpan? spacing = null, Func<DateTimeOffset>? now = null)
{
    public static readonly TimeSpan DefaultSpacing = TimeSpan.FromMinutes(10);
    private readonly TimeSpan spacing = spacing ?? DefaultSpacing;
    private readonly Func<DateTimeOffset> now = now ?? (() => DateTimeOffset.UtcNow);
    private readonly Dictionary<string, DateTimeOffset> last = new(StringComparer.Ordinal);
    public int Requests { get; private set; }
    public bool TryRequest(string? browserProduct)
    {
        var key = browserProduct ?? "unknown"; var at = now();
        lock (last)
        {
            if (last.TryGetValue(key, out var previous) && at - previous < spacing && at >= previous) return false;
            last[key] = at; Requests++;
            return true;
        }
    }
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
    public string? LastTrace { get; private set; }
    public event Action<CompanionSyncRequest>? SyncRequested;
    /// <summary>A browser's companion passed the handshake with the expected identity (checklist step 2). Carries the browser product.</summary>
    public event Action<string?>? Qualified;
    private readonly CompanionReloadThrottle reloads;
    public ClaudeCompanionCoordinator(IClaudeCompanionLink link, ClaudeCompanionManifest expected, CompanionTimings? timings = null, Func<DateTimeOffset>? now = null, CompanionReloadThrottle? reloads = null)
    {
        this.link = link; this.expected = expected; this.timings = timings ?? CompanionTimings.Default; this.now = now ?? (() => DateTimeOffset.UtcNow);
        this.reloads = reloads ?? new CompanionReloadThrottle(now: this.now);
        link.Received += OnReceived;
    }
    public ClaudeCompanionManifest Expected => expected;
    public void Dispose() { link.Received -= OnReceived; lock (gate) { foreach (var w in waiters) w.Done.TrySetCanceled(); waiters.Clear(); } }

    private void OnReceived(CompanionMessage message)
    {
        if (message is CompanionSyncRequest request) { SyncRequested?.Invoke(request); return; }
        // The page trace is a content-free list of step names and timings (allowlisted charset), kept for diagnostics only.
        if (message is CompanionTrace trace) { LastTrace = trace.Trace; return; }
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
        if (link.State == CompanionLinkState.Rejected) return new(link.RejectionReason == "generationMismatch" ? ClaudeSyncOutcome.UpdateRequired : ClaudeSyncOutcome.NotConnected, BrowserProduct: link.RejectedHost?.BrowserProduct ?? product);
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
        if (!Matches(identity)) return await OtherBuildAsync();
        var bridge = await ExchangeAsync(new(ClaudeBrowserContract.QualifyCommand, id), m => m is CompanionEvent { Status: "bridgeReady" } e && e.RequestId == id, timings.Handshake, cancellationToken);
        if (bridge is not CompanionEvent { Identity: { } confirmed }) return Silent();
        if (!Matches(confirmed)) return await OtherBuildAsync();
        ConsecutiveSilent = 0; SilentSince = null;
        Qualified?.Invoke(link.Host?.BrowserProduct);
        return null;
    }
    /// <summary>
    /// 0.18.6: the channel works but the extension is from another build. It loads from the folder AUV installs into, so a
    /// reload brings in the installed build. Extensions before 0.18.6 ignore the request; those are reloaded once by hand.
    /// </summary>
    private async Task<ClaudeSyncResult> OtherBuildAsync()
    {
        var requested = reloads.TryRequest(link.Host?.BrowserProduct) &&
            await link.SendAsync(new CompanionCommand(ClaudeBrowserContract.ReloadCommand, ClaudeBrowserContract.NewRequestId()), CancellationToken.None);
        return new(ClaudeSyncOutcome.UpdateRequired) { ReloadRequested = requested };
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

public enum ClaudeRemedy { None, OpenClaude, OpenExtensions, OpenBrowser }

/// <summary>
/// 0.18.6: the three-step checklist on the Claude page and in Claude settings. ① registered for Chrome and Edge;
/// ② the extension passed a handshake in a browser; ③ an exact reading was accepted (the person is signed in).
/// </summary>
public sealed record ClaudeChecklist(bool Registered, IReadOnlyList<string> LoadedBrowsers, bool SignedIn, string? Browser, DateTimeOffset? LastReading)
{
    public bool ExtensionLoaded => LoadedBrowsers.Count > 0;
    public bool Complete => Registered && ExtensionLoaded && SignedIn;
    public bool LoadedIn(string product) => LoadedBrowsers.Contains(product);
    /// <param name="connectedBrowser">The browser connected right now, if any; otherwise the first one that passed a handshake is named.</param>
    public static ClaudeChecklist Derive(bool registered, IEnumerable<string> loadedBrowsers, bool exactReadingSeen, string? connectedBrowser, DateTimeOffset? lastReading)
    {
        var loaded = loadedBrowsers.Where(b => b is "chrome" or "edge" or "unknown").Distinct().Order(StringComparer.Ordinal).ToArray();
        var browser = connectedBrowser is "chrome" or "edge" ? connectedBrowser : loaded.FirstOrDefault();
        return new(registered, loaded, exactReadingSeen, browser, lastReading);
    }
    /// <summary>The one line shown once all three steps are done: "Connected · Chrome · last reading 14:05".</summary>
    public string Summary
    {
        get
        {
            var browser = ClaudeBrowserPresentation.BrowserName(Browser);
            return LastReading is { } at
                ? UiText.T($"Connected · {browser} · last reading {at.ToLocalTime():HH:mm}", $"已连接 · {browser} · 上次读数 {at.ToLocalTime():HH:mm}")
                : UiText.T($"Connected · {browser}", $"已连接 · {browser}");
        }
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

    /// <param name="movedFolder">The extension in the browser was loaded from another AUV install folder (each version has its own): reloading cannot help.</param>
    public static string Message(ClaudeSyncOutcome outcome, string? browserProduct, bool movedFolder = false)
    {
        var browser = BrowserName(browserProduct);
        return outcome switch
        {
            ClaudeSyncOutcome.NotConnected => UiText.T("Waiting for Chrome or Edge with the AUV companion. Open the browser to sync Claude.", "正在等待装有 AUV 伴侣的 Chrome 或 Edge。打开浏览器后即可同步 Claude。"),
            // 2026-11-11: the companion lives in each AUV install folder, so a new AUV folder means loading the extension from
            // it again; the reload request only helps when the folder stayed the same.
            ClaudeSyncOutcome.UpdateRequired when movedFolder => UiText.T($"The AUV extension in {browser} still comes from your previous AUV folder. Load it from this AUV's folder: Claude page → step 2 → Load in {browser}. Reloading the old one does not help.",
                $"{browser} 中的 AUV 扩展仍来自上一份 AUV 的文件夹。请从这份 AUV 的文件夹加载：Claude 页 → 第 2 步 →“在 {browser} 中加载”。对旧扩展“重新加载”没有用。"),
            ClaudeSyncOutcome.UpdateRequired => UiText.T($"The AUV extension in {browser} is from a different build. AUV asks it to reload itself; if this stays, reload it once on {browser}'s extensions page (needed once after upgrading from AUV 0.18.5).", $"{browser} 中的 AUV 扩展来自不同的构建。AUV 会请它自行重新加载；如果此提示一直存在，请在 {browser} 的扩展页手动重新加载一次（从 AUV 0.18.5 升级后需要这样做一次）。"),
            ClaudeSyncOutcome.CompanionSilent => UiText.T($"The browser companion is not answering. Reload it on {browser}'s extensions page, or restart {browser}.", $"浏览器伴侣没有响应。请在 {browser} 的扩展页重新加载它，或重启 {browser}。"),
            ClaudeSyncOutcome.PermissionRequired => UiText.T($"The companion needs access to claude.ai. Allow site access for AUV Companion in {browser}'s extension settings, then refresh.", $"伴侣需要访问 claude.ai。请在 {browser} 的扩展设置中允许 AUV 伴侣访问该网站，然后刷新。"),
            ClaudeSyncOutcome.SignInRequired => UiText.T($"Sign in to claude.ai in {browser}, then refresh.", $"请在 {browser} 中登录 claude.ai，然后刷新。"),
            ClaudeSyncOutcome.LayoutUnsupported => UiText.T("Claude's Usage page layout is not recognized, so no figures are shown.", "无法识别 Claude 用量页的布局，因此不显示数字。"),
            ClaudeSyncOutcome.PageUnreadable => UiText.T("Claude's Usage page could not be read. AUV tries again at the next sync.", "无法读取 Claude 用量页。AUV 会在下次同步时重试。"),
            ClaudeSyncOutcome.PageTimedOut or ClaudeSyncOutcome.TabLost or ClaudeSyncOutcome.Busy => UiText.T("The Usage page did not answer in time. AUV tries again at the next sync.", "用量页没有及时响应。AUV 会在下次同步时重试。"),
            _ => ""
        };
    }

    public static AgentPresentation Failure(ClaudeSyncOutcome outcome, string? browserProduct, bool movedFolder = false) =>
        ProviderData.Unavailable("claude", Message(outcome, browserProduct, movedFolder), outcome switch
        {
            ClaudeSyncOutcome.NotConnected or ClaudeSyncOutcome.UpdateRequired or ClaudeSyncOutcome.SignInRequired or ClaudeSyncOutcome.PermissionRequired => ConnectionState.Disconnected,
            ClaudeSyncOutcome.CompanionSilent => ConnectionState.Reconnecting,
            _ => ConnectionState.Failed
        });

    /// <summary>0.18.6: the action button that goes with a failure reason on the Claude card.</summary>
    public static ClaudeRemedy Remedy(ClaudeSyncOutcome outcome) => outcome switch
    {
        ClaudeSyncOutcome.SignInRequired => ClaudeRemedy.OpenClaude,
        ClaudeSyncOutcome.PermissionRequired or ClaudeSyncOutcome.UpdateRequired or ClaudeSyncOutcome.CompanionSilent => ClaudeRemedy.OpenExtensions,
        ClaudeSyncOutcome.NotConnected => ClaudeRemedy.OpenBrowser,
        _ => ClaudeRemedy.None
    };
    public static string RemedyLabel(ClaudeRemedy remedy, string? browserProduct) => remedy switch
    {
        ClaudeRemedy.OpenClaude => UiText.T("Open claude.ai", "打开 claude.ai"),
        ClaudeRemedy.OpenExtensions => UiText.T($"Open {BrowserName(browserProduct ?? "chrome")} extensions page", $"打开 {BrowserName(browserProduct ?? "chrome")} 扩展页"),
        ClaudeRemedy.OpenBrowser => UiText.T($"Open {BrowserName(browserProduct ?? "chrome")}", $"打开 {BrowserName(browserProduct ?? "chrome")}"),
        _ => ""
    };

    public static string Disabled => UiText.T("Claude is not connected. Choose Connect on the Claude page to read Claude's exact figures from claude.ai.", "Claude 尚未连接。在 Claude 页选择“连接”后，可从 claude.ai 读取 Claude 的精确读数。");
    public static string NotSetUp => UiText.T("The browser companion is not set up. Choose Connect on the Claude page to read Claude's exact figures.", "浏览器伴侣尚未设置。在 Claude 页选择“连接”即可读取 Claude 的精确读数。");
    public static string NotPackaged => UiText.T("This copy of AUV has no browser companion package.", "这份 AUV 不含浏览器伴侣安装包。");
    public static string Syncing => UiText.T("Syncing exact figures…", "正在同步精确读数…");
}
