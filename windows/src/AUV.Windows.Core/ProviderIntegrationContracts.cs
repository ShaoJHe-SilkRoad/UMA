using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AUV.Windows.Core;

/// <summary>Prepared sources have no transport and cannot produce an admitted live allowance.</summary>
public enum IntegrationStage { Prepared, Live }
public sealed record UsageConnectionPlan(string ProviderId, string Name, string AccountChannel, string LocalChannel,
    string PendingQualification, IntegrationStage Stage = IntegrationStage.Prepared)
{
    public string UserStatus => "Connection prepared · live reading is not enabled.";
}
public interface IReadOnlyUsageConnector
{
    string ProviderId { get; }
    IntegrationStage Stage { get; }
    Task<AgentPresentation> ReadAsync(CancellationToken cancellationToken);
}
public sealed class PreparedUsageConnector(UsageConnectionPlan plan) : IReadOnlyUsageConnector
{
    public string ProviderId => plan.ProviderId;
    public IntegrationStage Stage => IntegrationStage.Prepared;
    public Task<AgentPresentation> ReadAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(ProviderData.Unavailable(ProviderId, plan.UserStatus));
    }
}
public static class PreparedConnections
{
    public static IReadOnlyList<UsageConnectionPlan> Plans { get; } = Array.AsReadOnly(new[]
    {
        new UsageConnectionPlan("claude", "Claude", "Sanitized Claude status-line packets; separate official-account page channel",
            "Explicitly selected local aggregate records", "Windows status-line producer, account identity and browser qualification"),
        new UsageConnectionPlan("antigravity", "Antigravity", "Versioned read-only quota buckets",
            "No local history source admitted", "A Windows executable identity and proven no-inference usage command; Mac arm64 admission is not portable")
    });
    public static UsageConnectionPlan? Find(string id) => Plans.FirstOrDefault(p => p.ProviderId == id);
}

// Pure protocol types are independent of login, installed-client discovery and transport.
// These decoders are not connected to the live admission path in this iteration.
public sealed record PreparedQuotaWindow(double RemainingPercent, DateTimeOffset ResetsAt);
public sealed record PreparedClaudePacket(string? Version, PreparedQuotaWindow? FiveHour, PreparedQuotaWindow? SevenDay, DateTimeOffset ObservedAt);
public static class PreparedClaudePacketDecoder
{
    public static PreparedClaudePacket Decode(ReadOnlyMemory<byte> bytes)
    {
        if (bytes.Length > 4096) throw new InvalidDataException("Claude packet exceeds its size limit.");
        using var document = JsonDocument.Parse(bytes); var root = document.RootElement;
        Shape(root, ["schemaVersion", "claudeVersion", "fiveHour", "sevenDay", "observedAt"], ["schemaVersion", "observedAt"]);
        if (ProviderData.Integer(ProviderData.Get(root, "schemaVersion")) != 1) throw new InvalidDataException("Unsupported Claude packet version.");
        var rawVersion = ProviderData.Get(root, "claudeVersion");
        var version = ProviderData.Text(rawVersion);
        if (rawVersion.ValueKind is not (JsonValueKind.Undefined or JsonValueKind.Null or JsonValueKind.String) ||
            version != null && (version.Length == 0 || Encoding.UTF8.GetByteCount(version) > 128 || version.Any(char.IsControl))) throw new InvalidDataException("Malformed Claude version.");
        return new(version, Window(ProviderData.Get(root, "fiveHour")), Window(ProviderData.Get(root, "sevenDay")), ObservedAt(ProviderData.Get(root, "observedAt")));
    }
    internal static void Shape(JsonElement e, string[] allowed, string[] required)
    {
        if (!ProviderData.Object(e)) throw new InvalidDataException("Invalid usage object.");
        var keys = e.EnumerateObject().Select(p => p.Name).ToArray();
        if (keys.Distinct(StringComparer.Ordinal).Count() != keys.Length || keys.Except(allowed).Any() || required.Except(keys).Any()) throw new InvalidDataException("Unexpected usage fields.");
    }
    private static PreparedQuotaWindow? Window(JsonElement e)
    {
        if (e.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return null;
        Shape(e, ["usedPercentage", "resetsAtEpochSeconds"], ["usedPercentage", "resetsAtEpochSeconds"]);
        var used = ProviderData.Get(e, "usedPercentage");
        if (used.ValueKind != JsonValueKind.Number || !used.TryGetDouble(out var value) || !double.IsFinite(value) || value is < 0 or > 100) throw new InvalidDataException("Invalid Claude percentage.");
        var reset = ProviderData.Integer(ProviderData.Get(e, "resetsAtEpochSeconds"));
        if (reset is null or > 4102444800) throw new InvalidDataException("Invalid Claude reset timestamp.");
        return new(100 - value, DateTimeOffset.FromUnixTimeSeconds(reset.Value));
    }
    private static DateTimeOffset ObservedAt(JsonElement e)
    {
        // Swift's millisecondsSince1970 encoder can retain fractional milliseconds.
        if (e.ValueKind != JsonValueKind.Number || !e.TryGetDouble(out var value) || !double.IsFinite(value) || value < -62135596800000 || value > 253402300799999) throw new InvalidDataException("Invalid usage timestamp.");
        return DateTimeOffset.UnixEpoch.AddMilliseconds(value);
    }
}

public sealed record PreparedAntigravityBucket(string Id, double RemainingPercent, DateTimeOffset? ResetsAt, string? DisplayLabel);
public static class PreparedAntigravityDecoder
{
    // Pinned Mac schema only. No Windows executable or command is admitted by this decoder.
    public static IReadOnlyList<PreparedAntigravityBucket> Decode(ReadOnlyMemory<byte> bytes, string schemaVersion)
    {
        if (schemaVersion != "agy-1.1.11" || bytes.Length > 65536) throw new InvalidDataException("Unsupported Antigravity quota packet.");
        using var document = JsonDocument.Parse(bytes); var root = document.RootElement;
        PreparedClaudePacketDecoder.Shape(root, ["command", "conversation_id", "duration_seconds", "num_turns", "response", "status", "usage"], ["command", "num_turns", "usage"]);
        var conversation = ProviderData.Get(root, "conversation_id");
        if (!NumericZero(ProviderData.Get(root, "num_turns")) ||
            conversation.ValueKind is not (JsonValueKind.Undefined or JsonValueKind.String) || !string.IsNullOrWhiteSpace(ProviderData.Text(conversation))) throw new InvalidDataException("Quota read contains provider work.");
        var usage = ProviderData.Get(root, "usage");
        if (!ProviderData.Object(usage)) throw new InvalidDataException("Invalid usage-work envelope.");
        var work = usage.EnumerateObject().ToArray();
        if (work.Length is 0 or > 32 || work.Select(p => p.Name).Distinct(StringComparer.Ordinal).Count() != work.Length || work.Any(p => !Identifier(p.Name) || !NumericZero(p.Value))) throw new InvalidDataException("Quota read contains usage work.");
        var command = ProviderData.Get(root, "command");
        PreparedClaudePacketDecoder.Shape(command, ["data", "name"], ["data", "name"]);
        if (ProviderData.Text(ProviderData.Get(command, "name")) != "usage") throw new InvalidDataException("Unsupported quota command.");
        var data = ProviderData.Get(command, "data");
        PreparedClaudePacketDecoder.Shape(data, ["description", "groups"], ["description", "groups"]);
        if (ProviderData.Get(data, "description").ValueKind != JsonValueKind.String) throw new InvalidDataException("Invalid quota command description.");
        var groups = ProviderData.Get(data, "groups");
        if (groups.ValueKind != JsonValueKind.Array || groups.GetArrayLength() > 32) throw new InvalidDataException("Unsupported quota groups.");
        var output = new List<PreparedAntigravityBucket>(); var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var group in groups.EnumerateArray())
        {
            PreparedClaudePacketDecoder.Shape(group, ["name", "description", "buckets"], ["name", "description", "buckets"]);
            if (SafeText(ProviderData.Get(group, "name"), 128) == null || SafeText(ProviderData.Get(group, "description"), 512) == null) throw new InvalidDataException("Invalid quota group metadata.");
            var buckets = ProviderData.Get(group, "buckets");
            if (buckets.ValueKind != JsonValueKind.Array || output.Count + buckets.GetArrayLength() > 64) throw new InvalidDataException("Invalid quota buckets.");
            foreach (var bucket in buckets.EnumerateArray())
            {
                PreparedClaudePacketDecoder.Shape(bucket, ["id", "name", "window", "remaining_fraction", "reset_time"], ["id", "name", "window", "remaining_fraction"]);
                var id = ProviderData.Text(ProviderData.Get(bucket, "id")); var fraction = ProviderData.Get(bucket, "remaining_fraction");
                if (id == null || !Identifier(id) || !ids.Add(id) || ProviderData.Get(bucket, "name").ValueKind != JsonValueKind.String || SafeText(ProviderData.Get(bucket, "window"), 128) == null || fraction.ValueKind != JsonValueKind.Number || !fraction.TryGetDouble(out var number) || !double.IsFinite(number) || number is < 0 or > 1) throw new InvalidDataException("Invalid quota bucket.");
                var reset = ProviderData.Get(bucket, "reset_time"); DateTimeOffset? time = null;
                if (reset.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined))
                {
                    var text = ProviderData.Text(reset);
                    if (text == null || !Regex.IsMatch(text, @"\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})\z", RegexOptions.CultureInvariant) || !DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed)) throw new InvalidDataException("Invalid quota reset.");
                    time = parsed;
                }
                output.Add(new(id, number * 100, time, SafeText(ProviderData.Get(bucket, "name"), 48)));
            }
        }
        if (output.Count == 0) throw new InvalidDataException("No quota buckets.");
        return output.AsReadOnly();
    }
    private static bool NumericZero(JsonElement e) => e.ValueKind == JsonValueKind.Number && e.TryGetDouble(out var value) && value == 0;
    private static bool Identifier(string value) => Regex.IsMatch(value, @"\A[a-zA-Z0-9_.:-]{1,64}\z", RegexOptions.CultureInvariant);
    private static string? SafeText(JsonElement e, int maximumBytes)
    {
        var value = ProviderData.Text(e)?.Trim();
        return value is { Length: > 0 } && Encoding.UTF8.GetByteCount(value) <= maximumBytes && !value.Any(char.IsControl) ? value : null;
    }
}

/// <summary>Local aggregates never substitute for account quota or account token totals.</summary>
public sealed record LocalUsageAggregate(string ProviderId, DateOnly Day, long Tokens, string Source);
public interface ILocalUsageReader
{
    Task<IReadOnlyList<LocalUsageAggregate>> ReadAsync(string explicitlySelectedRoot, CancellationToken cancellationToken);
}
public sealed record StorageReadiness(bool InventoryAvailable, bool CanMutate, string Reason);
public interface IWindowsStorageBackend
{
    StorageReadiness Readiness { get; }
}
public sealed class PreparedWindowsStorageBackend : IWindowsStorageBackend
{
    public StorageReadiness Readiness { get; } = new(false, false, "Windows storage connection prepared; drive access is not enabled.");
}
