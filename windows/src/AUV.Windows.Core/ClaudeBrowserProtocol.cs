using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AUV.Windows.Core;

// The Claude browser companion's wire contract on Windows. It follows the Mac Safari companion's
// schema 2 (BrowserExtension/Shared, Sources/ClaudeBrowserBridgeProtocol) with browserFamily "chromium",
// plus a few Windows-only envelopes for the native host and the named pipe. Every object must have
// exactly the allowed keys. There is no field for a URL, page text, cookie, token or account identity.
// This file has no UI dependency, so the native host compiles it too.

public static class ClaudeBrowserContract
{
    public const int MaximumMessageBytes = 4096;
    public const int MaximumPipeFrameBytes = 8192;
    public const int SchemaVersion = 2;
    public const int WindowsSchemaVersion = 1;
    public const int ExtractorSchemaVersion = 2;
    public const int SourceLayoutVersion = 1;
    public const string SourceId = "claude-browser-usage";
    public const string BrowserFamily = "chromium";
    public const string NativeHostName = "com.silkrd.auv.claude_browser";
    public const string ContainingApplicationIdentifier = "com.silkrd.auv.windows";
    public const string WakeCommand = "umaClaudeWakeBridge";
    public const string QualifyCommand = "umaClaudeRuntimeQualification";
    public const string RefreshCommand = "umaClaudeAutomaticRefresh";
    public const string CloseCommand = "umaClaudeCloseOwnedUsageTab";
    public static readonly string[] Placements = ["backgroundTab", "minimizedWindow"];
    public static readonly string[] FailureStatuses =
        ["permissionRequired", "signInRequired", "routeRejected", "usageUnavailable", "tabUnavailable", "ownedTabClosed", "ownedTabOwnershipLost"];
    public static readonly string[] ProviderFailureReasons =
    [
        "ROUTE_NOT_READY", "ROUTE_READINESS_TIMEOUT", "PROVIDER_DOCUMENT_NOT_READY", "TARGET_DATA_NOT_READY", "TARGET_DATA_TIMEOUT",
        "PROVIDER_STRUCTURE_UNSUPPORTED", "PROVIDER_SESSION_UNAVAILABLE", "SITE_PERMISSION_MISSING", "EXTRACTION_VALIDATION_FAILED",
        "REQUEST_CANCELLED", "PROVIDER_TAB_CLOSED"
    ];
    /// <summary>Statuses whose events carry the companion's identity (Mac handshake statuses).</summary>
    public static readonly string[] IdentityStatuses =
    [
        "extensionBackgroundReady", "nativeHandlerEntered", "nativeRequestDecoded", "runtimeGenerationValidated",
        "nativeResponseCreated", "nativeResponseSent", "extensionResponseReceived", "bridgeReady"
    ];
    public static readonly string[] EventStatuses = [.. IdentityStatuses, "refreshStarted", "refreshCompleted", "browserUnavailable", .. FailureStatuses];
    private static readonly Regex Uuid = new("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", RegexOptions.CultureInvariant | RegexOptions.IgnoreCase);
    private static readonly Regex ExtensionIdPattern = new("^[a-p]{32}$", RegexOptions.CultureInvariant);
    private static readonly Regex Timestamp = new(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$", RegexOptions.CultureInvariant);
    public static bool IsUuid(string? value) => value != null && Uuid.IsMatch(value);
    public static bool IsExtensionId(string? value) => value != null && ExtensionIdPattern.IsMatch(value);
    public static string ExtensionOrigin(string extensionId) => $"chrome-extension://{extensionId}/";
    public static DateTimeOffset? ParseTimestamp(string? value)
    {
        if (value == null || Encoding.UTF8.GetByteCount(value) > 64 || !Timestamp.IsMatch(value)) return null;
        return DateTimeOffset.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed) ? parsed : null;
    }
    public static string NewRequestId() => Guid.NewGuid().ToString("D");
}

/// <summary>A fixed, content-free reason. The message never contains provider data.</summary>
public sealed class CompanionProtocolException(string code) : Exception(code)
{
    public string Code { get; } = code;
}

public sealed record CompanionWindow(double UsedPercentage, DateTimeOffset? ResetAt);
public sealed record CompanionObservation(CompanionWindow? FiveHour, CompanionWindow? WeeklyAllModels, DateTimeOffset ObservedAt);
public sealed record CompanionIdentity(string CompanionVersion, string CompanionBuild, string ExtensionIdentifier, string RuntimeGenerationId);

public abstract record CompanionMessage;
public sealed record CompanionEvent(string RequestId, string Status, DateTimeOffset OccurredAt, CompanionIdentity? Identity) : CompanionMessage;
public sealed record CompanionTerminal(string RequestId, string? TargetRequestId, string RuntimeGenerationId, string Status, DateTimeOffset OccurredAt,
    string? ObservationId, CompanionObservation? Observation, string? ProviderFailureReason) : CompanionMessage;
public sealed record CompanionPong(string PingId) : CompanionMessage;
public sealed record CompanionPing(string PingId) : CompanionMessage;
public sealed record CompanionTrace(string Trace) : CompanionMessage;
/// <summary>The user clicked the extension's toolbar button (D13): a request to sync now. Carries nothing else.</summary>
public sealed record CompanionSyncRequest(string RequestId) : CompanionMessage;
public sealed record CompanionCommand(string Command, string RequestId, string? TargetRequestId = null, string? Placement = null) : CompanionMessage;
public sealed record HostStatus(bool AppConnected) : CompanionMessage;
public sealed record HostHello(string HostVersion, string HostBuild, string ExtensionOrigin, string BrowserProduct, string RuntimeGenerationId) : CompanionMessage;
public sealed record HostWelcome(bool Accepted, string Reason) : CompanionMessage;

public static class CompanionMessageCodec
{
    public static readonly string[] WelcomeReasons = ["accepted", "generationMismatch", "browserNotSelected", "busy", "originRejected"];
    public static readonly string[] BrowserProducts = ["chrome", "edge", "unknown"];
    private static readonly Regex TraceText = new("^[A-Za-z0-9=+,\\- ]{0,800}$", RegexOptions.CultureInvariant);
    private static readonly Regex Version = new(@"^[0-9A-Za-z.\-]{1,32}$", RegexOptions.CultureInvariant);
    private static readonly Regex Digits = new("^[0-9]{1,32}$", RegexOptions.CultureInvariant);

    /// <summary>Messages the browser extension may send (to the host, and through it to AUV).</summary>
    public static CompanionMessage DecodeFromExtension(ReadOnlySpan<byte> bytes)
    {
        using var document = Parse(bytes, ClaudeBrowserContract.MaximumMessageBytes);
        var root = document.RootElement;
        return Text(root, "kind") switch
        {
            "claudeBrowserAutomationEvent" => Event(root),
            "claudeBrowserTerminalPacket" => Terminal(root),
            "auvCompanionPong" => Pong(root),
            "auvCompanionPing" => Ping(root),
            "auvCompanionSyncRequest" => SyncRequest(root),
            "umaCompanionPageTraceV1" => Trace(root),
            _ => throw new CompanionProtocolException("unexpected-kind")
        };
    }

    /// <summary>Messages AUV may send to the host (forwarded to the extension unless addressed to the host).</summary>
    public static CompanionMessage DecodeFromApp(ReadOnlySpan<byte> bytes)
    {
        using var document = Parse(bytes, ClaudeBrowserContract.MaximumMessageBytes);
        var root = document.RootElement;
        return Text(root, "kind") switch
        {
            "auvCompanionCommand" => Command(root),
            "auvCompanionPing" => Ping(root),
            "auvBrowserHostWelcome" => Welcome(root),
            _ => throw new CompanionProtocolException("unexpected-kind")
        };
    }

    /// <summary>Messages the host itself sends to AUV.</summary>
    public static CompanionMessage DecodeFromHost(ReadOnlySpan<byte> bytes)
    {
        using var document = Parse(bytes, ClaudeBrowserContract.MaximumMessageBytes);
        var root = document.RootElement;
        if (Text(root, "kind") == "auvBrowserHostHello") return Hello(root);
        return DecodeFromExtension(bytes);
    }

    /// <summary>Messages the host sends to the extension.</summary>
    public static CompanionMessage DecodeForExtension(ReadOnlySpan<byte> bytes)
    {
        using var document = Parse(bytes, ClaudeBrowserContract.MaximumMessageBytes);
        var root = document.RootElement;
        return Text(root, "kind") switch
        {
            "auvCompanionCommand" => Command(root),
            "auvCompanionPing" => Ping(root),
            "auvHostStatus" => Status(root),
            _ => throw new CompanionProtocolException("unexpected-kind")
        };
    }

    public static byte[] Encode(CompanionMessage message)
    {
        var bytes = message switch
        {
            CompanionCommand c => Write(w =>
            {
                w.WriteString("kind", "auvCompanionCommand"); w.WriteNumber("schemaVersion", ClaudeBrowserContract.WindowsSchemaVersion);
                w.WriteString("command", c.Command); w.WriteString("requestID", c.RequestId);
                if (c.TargetRequestId != null) w.WriteString("targetRequestID", c.TargetRequestId);
                if (c.Placement != null) w.WriteString("placement", c.Placement);
            }),
            CompanionPing p => Write(w => { w.WriteString("kind", "auvCompanionPing"); w.WriteNumber("schemaVersion", ClaudeBrowserContract.WindowsSchemaVersion); w.WriteString("pingID", p.PingId); }),
            CompanionPong p => Write(w => { w.WriteString("kind", "auvCompanionPong"); w.WriteNumber("schemaVersion", ClaudeBrowserContract.WindowsSchemaVersion); w.WriteString("pingID", p.PingId); }),
            HostStatus s => Write(w => { w.WriteString("kind", "auvHostStatus"); w.WriteNumber("schemaVersion", ClaudeBrowserContract.WindowsSchemaVersion); w.WriteBoolean("appConnected", s.AppConnected); }),
            HostHello h => Write(w =>
            {
                w.WriteString("kind", "auvBrowserHostHello"); w.WriteNumber("schemaVersion", ClaudeBrowserContract.WindowsSchemaVersion);
                w.WriteString("hostVersion", h.HostVersion); w.WriteString("hostBuild", h.HostBuild); w.WriteString("extensionOrigin", h.ExtensionOrigin);
                w.WriteString("browserProduct", h.BrowserProduct); w.WriteString("runtimeGenerationID", h.RuntimeGenerationId);
            }),
            HostWelcome h => Write(w => { w.WriteString("kind", "auvBrowserHostWelcome"); w.WriteNumber("schemaVersion", ClaudeBrowserContract.WindowsSchemaVersion); w.WriteBoolean("accepted", h.Accepted); w.WriteString("reason", h.Reason); }),
            _ => throw new CompanionProtocolException("unencodable")
        };
        // Validate our own output with the receiving side's decoder, so nothing malformed is ever sent.
        _ = message switch
        {
            CompanionCommand or HostStatus => DecodeForExtension(bytes),
            HostWelcome => DecodeFromApp(bytes),
            HostHello => DecodeFromHost(bytes),
            CompanionPing => DecodeFromApp(bytes),
            _ => DecodeFromExtension(bytes)
        };
        return bytes;
    }

    private static byte[] Write(Action<Utf8JsonWriter> body)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream)) { writer.WriteStartObject(); body(writer); writer.WriteEndObject(); }
        return stream.ToArray();
    }

    private static JsonDocument Parse(ReadOnlySpan<byte> bytes, int limit)
    {
        if (bytes.Length == 0) throw new CompanionProtocolException("message-empty");
        if (bytes.Length > limit) throw new CompanionProtocolException("message-too-large");
        JsonDocument document;
        try { document = JsonDocument.Parse(bytes.ToArray(), new JsonDocumentOptions { MaxDepth = 8 }); }
        catch (JsonException) { throw new CompanionProtocolException("malformed-json"); }
        if (document.RootElement.ValueKind != JsonValueKind.Object) { document.Dispose(); throw new CompanionProtocolException("invalid-top-level"); }
        return document;
    }

    /// <summary>Exactly the allowed keys, no duplicates, every required key present. Optional keys may be JSON null.</summary>
    private static void Keys(JsonElement e, string[] allowed, string[] required)
    {
        if (e.ValueKind != JsonValueKind.Object) throw new CompanionProtocolException("invalid-object");
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in e.EnumerateObject())
        {
            if (!seen.Add(property.Name)) throw new CompanionProtocolException("duplicate-field");
            if (!allowed.Contains(property.Name, StringComparer.Ordinal)) throw new CompanionProtocolException("unexpected-field");
        }
        foreach (var key in required) if (!seen.Contains(key)) throw new CompanionProtocolException("missing-field");
    }

    private static JsonElement Get(JsonElement e, string key) => e.TryGetProperty(key, out var value) ? value : default;
    private static bool IsAbsent(JsonElement e) => e.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null;
    private static string? Text(JsonElement e, string key) => Get(e, key) is { ValueKind: JsonValueKind.String } v ? v.GetString() : null;
    private static string RequiredText(JsonElement e, string key) => Text(e, key) ?? throw new CompanionProtocolException("invalid-contract");
    private static string? OptionalText(JsonElement e, string key)
    {
        var value = Get(e, key);
        if (IsAbsent(value)) return null;
        return value.ValueKind == JsonValueKind.String ? value.GetString() : throw new CompanionProtocolException("invalid-contract");
    }
    private static void Integer(JsonElement e, string key, int expected)
    {
        var value = Get(e, key);
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var number) || number != expected) throw new CompanionProtocolException("invalid-contract");
    }
    private static string Uuid(JsonElement e, string key)
    {
        var value = RequiredText(e, key);
        return ClaudeBrowserContract.IsUuid(value) ? value.ToLowerInvariant() : throw new CompanionProtocolException("invalid-contract");
    }
    private static DateTimeOffset Time(JsonElement e, string key, string code = "invalid-timestamp") =>
        ClaudeBrowserContract.ParseTimestamp(Text(e, key)) ?? throw new CompanionProtocolException(code);
    private static void Base(JsonElement e, string kind)
    {
        if (Text(e, "kind") != kind) throw new CompanionProtocolException("invalid-contract");
        Integer(e, "schemaVersion", ClaudeBrowserContract.SchemaVersion);
        if (Text(e, "sourceID") != ClaudeBrowserContract.SourceId || Text(e, "browserFamily") != ClaudeBrowserContract.BrowserFamily)
            throw new CompanionProtocolException("invalid-contract");
    }
    private static void Windows(JsonElement e, string kind)
    {
        if (Text(e, "kind") != kind) throw new CompanionProtocolException("invalid-contract");
        Integer(e, "schemaVersion", ClaudeBrowserContract.WindowsSchemaVersion);
    }

    private static CompanionEvent Event(JsonElement e)
    {
        string[] baseKeys = ["kind", "schemaVersion", "sourceID", "browserFamily", "requestID", "status", "occurredAt"];
        string[] identityKeys = ["companionVersion", "companionBuild", "protocolSchemaVersion", "containingApplicationIdentifier", "extensionIdentifier", "teamIdentifier", "runtimeGenerationID"];
        var status = Text(e, "status");
        if (status == null || !ClaudeBrowserContract.EventStatuses.Contains(status, StringComparer.Ordinal)) throw new CompanionProtocolException("invalid-contract");
        var carriesIdentity = ClaudeBrowserContract.IdentityStatuses.Contains(status, StringComparer.Ordinal);
        string[] keys = carriesIdentity ? [.. baseKeys, .. identityKeys] : baseKeys;
        Keys(e, keys, keys);
        Base(e, "claudeBrowserAutomationEvent");
        var requestId = Uuid(e, "requestID"); var occurred = Time(e, "occurredAt");
        CompanionIdentity? identity = null;
        if (carriesIdentity)
        {
            var version = RequiredText(e, "companionVersion"); var build = RequiredText(e, "companionBuild");
            var extension = RequiredText(e, "extensionIdentifier");
            Integer(e, "protocolSchemaVersion", ClaudeBrowserContract.SchemaVersion);
            if (!Version.IsMatch(version) || !Digits.IsMatch(build) || !ClaudeBrowserContract.IsExtensionId(extension) ||
                Text(e, "containingApplicationIdentifier") != ClaudeBrowserContract.ContainingApplicationIdentifier ||
                Text(e, "teamIdentifier") != "")
                throw new CompanionProtocolException("invalid-contract");
            identity = new(version, build, extension, Uuid(e, "runtimeGenerationID"));
        }
        return new(requestId, status, occurred, identity);
    }

    private static CompanionTerminal Terminal(JsonElement e)
    {
        string[] keys = ["kind", "schemaVersion", "sourceID", "browserFamily", "requestID", "targetRequestID", "runtimeGenerationID", "status", "occurredAt", "observation", "providerFailureReason"];
        Keys(e, keys, ["kind", "schemaVersion", "sourceID", "browserFamily", "requestID", "runtimeGenerationID", "status", "occurredAt"]);
        Base(e, "claudeBrowserTerminalPacket");
        var requestId = Uuid(e, "requestID"); var generation = Uuid(e, "runtimeGenerationID");
        var status = RequiredText(e, "status"); var occurred = Time(e, "occurredAt", "invalid-contract");
        var target = OptionalText(e, "targetRequestID"); var reason = OptionalText(e, "providerFailureReason");
        var rawObservation = Get(e, "observation");
        if (status == "refreshCompleted")
        {
            if (target != null || reason != null || IsAbsent(rawObservation)) throw new CompanionProtocolException("invalid-contract");
            var (observationRequest, observationId, observation) = Envelope(rawObservation);
            if (observationRequest != requestId) throw new CompanionProtocolException("invalid-contract");
            return new(requestId, null, generation, status, occurred, observationId, observation, null);
        }
        if (!ClaudeBrowserContract.FailureStatuses.Contains(status, StringComparer.Ordinal) || !IsAbsent(rawObservation)) throw new CompanionProtocolException("invalid-contract");
        if (reason != null && (target != null || !ClaudeBrowserContract.ProviderFailureReasons.Contains(reason, StringComparer.Ordinal) ||
            status is not ("permissionRequired" or "signInRequired" or "routeRejected" or "usageUnavailable" or "tabUnavailable")))
            throw new CompanionProtocolException("invalid-contract");
        if (target != null)
        {
            if (status is not ("ownedTabClosed" or "ownedTabOwnershipLost") || !ClaudeBrowserContract.IsUuid(target)) throw new CompanionProtocolException("invalid-contract");
            target = target.ToLowerInvariant();
            if (target == requestId) throw new CompanionProtocolException("invalid-contract");
        }
        return new(requestId, target, generation, status, occurred, null, null, reason);
    }

    private static (string RequestId, string ObservationId, CompanionObservation Observation) Envelope(JsonElement e)
    {
        string[] keys = ["kind", "schemaVersion", "sourceID", "browserFamily", "routeState", "requestID", "observationID", "observation"];
        Keys(e, keys, keys);
        Base(e, "claudeUsageObservation");
        if (Text(e, "routeState") != "verifiedUsage") throw new CompanionProtocolException("invalid-contract");
        var requestId = Uuid(e, "requestID"); var observationId = Uuid(e, "observationID");
        var observation = Get(e, "observation");
        Keys(observation, ["fiveHour", "weeklyAllModels", "modelSpecificWeekly", "observedAt", "extractorSchemaVersion", "sourceLayoutVersion"],
            ["observedAt", "extractorSchemaVersion", "sourceLayoutVersion"]);
        Integer(observation, "extractorSchemaVersion", ClaudeBrowserContract.ExtractorSchemaVersion);
        Integer(observation, "sourceLayoutVersion", ClaudeBrowserContract.SourceLayoutVersion);
        var fiveHour = Window(Get(observation, "fiveHour"));
        var weekly = Window(Get(observation, "weeklyAllModels"));
        var model = Get(observation, "modelSpecificWeekly");
        if (!IsAbsent(model))
        {
            // Validated as on the Mac, then dropped: AUV does not use the model-specific row.
            Keys(model, ["modelFamily", "window"], ["modelFamily", "window"]);
            if (Text(model, "modelFamily") is not ("sonnet" or "opus" or "haiku") || Window(Get(model, "window")) == null) throw new CompanionProtocolException("invalid-contract");
        }
        if (fiveHour == null && weekly == null) throw new CompanionProtocolException("no-account-window");
        return (requestId, observationId, new(fiveHour, weekly, Time(observation, "observedAt")));
    }

    private static CompanionWindow? Window(JsonElement e)
    {
        if (IsAbsent(e)) return null;
        Keys(e, ["usedPercentage", "resetAt"], ["usedPercentage"]);
        var used = Get(e, "usedPercentage");
        if (used.ValueKind != JsonValueKind.Number || !used.TryGetDouble(out var value) || !double.IsFinite(value) || value is < 0 or > 100)
            throw new CompanionProtocolException("invalid-percentage");
        var reset = Get(e, "resetAt"); DateTimeOffset? resetAt = null;
        if (!IsAbsent(reset)) resetAt = reset.ValueKind == JsonValueKind.String ? ClaudeBrowserContract.ParseTimestamp(reset.GetString()) ?? throw new CompanionProtocolException("invalid-reset") : throw new CompanionProtocolException("invalid-reset");
        return new(value, resetAt);
    }

    private static CompanionPong Pong(JsonElement e) { Keys(e, ["kind", "schemaVersion", "pingID"], ["kind", "schemaVersion", "pingID"]); Windows(e, "auvCompanionPong"); return new(Uuid(e, "pingID")); }
    private static CompanionPing Ping(JsonElement e) { Keys(e, ["kind", "schemaVersion", "pingID"], ["kind", "schemaVersion", "pingID"]); Windows(e, "auvCompanionPing"); return new(Uuid(e, "pingID")); }
    private static CompanionSyncRequest SyncRequest(JsonElement e) { Keys(e, ["kind", "schemaVersion", "requestID"], ["kind", "schemaVersion", "requestID"]); Windows(e, "auvCompanionSyncRequest"); return new(Uuid(e, "requestID")); }
    private static HostStatus Status(JsonElement e)
    {
        Keys(e, ["kind", "schemaVersion", "appConnected"], ["kind", "schemaVersion", "appConnected"]); Windows(e, "auvHostStatus");
        var value = Get(e, "appConnected");
        return value.ValueKind is JsonValueKind.True or JsonValueKind.False ? new(value.GetBoolean()) : throw new CompanionProtocolException("invalid-contract");
    }
    private static CompanionTrace Trace(JsonElement e)
    {
        Keys(e, ["kind", "trace"], ["kind", "trace"]);
        var trace = RequiredText(e, "trace");
        return TraceText.IsMatch(trace) ? new(trace) : throw new CompanionProtocolException("invalid-contract");
    }
    private static CompanionCommand Command(JsonElement e)
    {
        var command = Text(e, "command");
        string[] keys = command switch
        {
            ClaudeBrowserContract.CloseCommand => ["kind", "schemaVersion", "command", "requestID", "targetRequestID"],
            ClaudeBrowserContract.RefreshCommand when e.TryGetProperty("placement", out _) => ["kind", "schemaVersion", "command", "requestID", "placement"],
            ClaudeBrowserContract.WakeCommand or ClaudeBrowserContract.QualifyCommand or ClaudeBrowserContract.RefreshCommand => ["kind", "schemaVersion", "command", "requestID"],
            _ => throw new CompanionProtocolException("invalid-contract")
        };
        Keys(e, keys, keys); Windows(e, "auvCompanionCommand");
        var requestId = Uuid(e, "requestID");
        string? target = null, placement = null;
        if (command == ClaudeBrowserContract.CloseCommand) { target = Uuid(e, "targetRequestID"); if (target == requestId) throw new CompanionProtocolException("invalid-contract"); }
        if (keys.Contains("placement")) { placement = RequiredText(e, "placement"); if (!ClaudeBrowserContract.Placements.Contains(placement)) throw new CompanionProtocolException("invalid-contract"); }
        return new(command!, requestId, target, placement);
    }
    private static HostHello Hello(JsonElement e)
    {
        string[] keys = ["kind", "schemaVersion", "hostVersion", "hostBuild", "extensionOrigin", "browserProduct", "runtimeGenerationID"];
        Keys(e, keys, keys); Windows(e, "auvBrowserHostHello");
        var version = RequiredText(e, "hostVersion"); var build = RequiredText(e, "hostBuild"); var origin = RequiredText(e, "extensionOrigin"); var product = RequiredText(e, "browserProduct");
        if (!Version.IsMatch(version) || !Digits.IsMatch(build) || !BrowserProducts.Contains(product) ||
            !origin.StartsWith("chrome-extension://", StringComparison.Ordinal) || !origin.EndsWith('/') || !ClaudeBrowserContract.IsExtensionId(origin["chrome-extension://".Length..^1]))
            throw new CompanionProtocolException("invalid-contract");
        return new(version, build, origin, product, Uuid(e, "runtimeGenerationID"));
    }
    private static HostWelcome Welcome(JsonElement e)
    {
        Keys(e, ["kind", "schemaVersion", "accepted", "reason"], ["kind", "schemaVersion", "accepted", "reason"]); Windows(e, "auvBrowserHostWelcome");
        var accepted = Get(e, "accepted"); var reason = RequiredText(e, "reason");
        if (accepted.ValueKind is not (JsonValueKind.True or JsonValueKind.False) || !WelcomeReasons.Contains(reason) || accepted.GetBoolean() != (reason == "accepted"))
            throw new CompanionProtocolException("invalid-contract");
        return new(accepted.GetBoolean(), reason);
    }
}

/// <summary>Length-prefixed frames: a 4-byte little-endian length, then UTF-8 JSON (Chrome native messaging on Windows, and the pipe).</summary>
public static class CompanionFraming
{
    public static async Task<byte[]?> ReadAsync(Stream stream, int limit, CancellationToken cancellationToken)
    {
        var header = new byte[4];
        if (!await ReadExactlyOrEndAsync(stream, header, cancellationToken)) return null;
        var length = BitConverter.ToInt32(header, 0);
        if (length <= 0 || length > limit) throw new CompanionProtocolException("frame-malformed");
        var body = new byte[length];
        if (!await ReadExactlyOrEndAsync(stream, body, cancellationToken)) throw new CompanionProtocolException("frame-truncated");
        return body;
    }
    public static async Task WriteAsync(Stream stream, ReadOnlyMemory<byte> body, int limit, CancellationToken cancellationToken)
    {
        if (body.Length == 0 || body.Length > limit) throw new CompanionProtocolException("frame-malformed");
        var frame = new byte[4 + body.Length];
        BitConverter.GetBytes(body.Length).CopyTo(frame, 0); body.CopyTo(frame.AsMemory(4));
        await stream.WriteAsync(frame, cancellationToken); await stream.FlushAsync(cancellationToken);
    }
    private static async Task<bool> ReadExactlyOrEndAsync(Stream stream, byte[] buffer, CancellationToken cancellationToken)
    {
        var read = 0;
        while (read < buffer.Length)
        {
            var count = await stream.ReadAsync(buffer.AsMemory(read), cancellationToken);
            if (count == 0) return read == 0 ? false : throw new CompanionProtocolException("frame-truncated");
            read += count;
        }
        return true;
    }
}
