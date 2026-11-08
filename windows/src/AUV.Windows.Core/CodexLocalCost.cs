using System.Globalization;
using System.Text.Json;

namespace AUV.Windows.Core;

public sealed record CodexModelPrice(string Version, string DisplayName, decimal InputPerMillion, decimal CachedInputPerMillion, decimal OutputPerMillion);

/// <summary>Public list prices copied from the Mac catalogue (2026-07-13-standard). Unknown or earlier usage is unpriced.</summary>
public static class CodexPriceTable
{
    public const string Version = "2026-07-13-standard";
    public static readonly DateTimeOffset EffectiveFrom = new(2026, 7, 13, 0, 0, 0, TimeSpan.Zero);
    private static readonly (string Model, string Name, decimal Input, decimal Cached, decimal Output)[] Rows =
    [
        ("gpt-5.6-sol", "GPT-5.6 Sol", 5m, 0.5m, 30m), ("gpt-5.6-terra", "GPT-5.6 Terra", 2.5m, 0.25m, 15m),
        ("gpt-5.6-luna", "GPT-5.6 Luna", 1m, 0.1m, 6m), ("gpt-5.5", "GPT-5.5", 5m, 0.5m, 30m), ("gpt-5.4", "GPT-5.4", 2.5m, 0.25m, 15m)
    ];
    public static CodexModelPrice? For(string? rawModel, DateTimeOffset? observedAt)
    {
        if (rawModel == null || observedAt is not { } observed || observed < EffectiveFrom) return null;
        var model = rawModel.ToLowerInvariant();
        foreach (var row in Rows)
            if (model == row.Model || model.StartsWith(row.Model + "-", StringComparison.Ordinal))
                return new(Version, row.Name, row.Input, row.Cached, row.Output);
        return null;
    }
    public static decimal Cost(CodexModelPrice price, long input, long cached, long output)
    {
        var cachedInput = Math.Min(Math.Max(0, cached), Math.Max(0, input)); var uncached = Math.Max(0, input - cachedInput);
        return uncached / 1_000_000m * price.InputPerMillion + cachedInput / 1_000_000m * price.CachedInputPerMillion + Math.Max(0, output) / 1_000_000m * price.OutputPerMillion;
    }
}

public sealed record LocalCostEstimate(decimal SevenDayUsd, decimal LifetimeUsd, long SevenDayTokens, long LifetimeTokens, long PricedTokens,
    int FilesRead, int FilesSkipped, DateTimeOffset ComputedAt)
{
    public double PricedCoverage => LifetimeTokens > 0 ? (double)PricedTokens / LifetimeTokens : 0;
    public bool HasPricedUsage => PricedTokens > 0;
}

/// <summary>
/// Reads token counters from local Codex session logs. Only these fields are parsed: line type and timestamp,
/// turn_context.payload.model, session_meta fork markers, and event_msg/token_count total_token_usage counts.
/// Prompts, responses, tool calls, paths and identifiers are never decoded, kept or written anywhere.
/// </summary>
public sealed class CodexLocalCostEstimator
{
    public const int MaxFiles = 4000;
    public const long MaxFileBytes = 256L * 1024 * 1024;
    public const int MaxLineBytes = 1024 * 1024;
    public sealed record CostDelta(DateOnly Day, long Total, decimal Usd, bool Priced);
    private sealed record FileResult(long Length, DateTime Written, IReadOnlyList<CostDelta> Deltas);
    private readonly Dictionary<string, FileResult> cache = new(StringComparer.OrdinalIgnoreCase);
    private readonly object gate = new();
    public static IReadOnlyList<string> DefaultRoots()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return [Path.Combine(home, ".codex", "sessions"), Path.Combine(home, ".codex", "archived_sessions")];
    }
    public LocalCostEstimate? Estimate(IEnumerable<string> roots, DateTimeOffset now, TimeZoneInfo zone, CancellationToken token = default)
    {
        var files = new List<FileInfo>();
        foreach (var root in roots)
        {
            try
            {
                if (!Directory.Exists(root)) continue;
                var rootInfo = new DirectoryInfo(root);
                if (rootInfo.Attributes.HasFlag(FileAttributes.ReparsePoint)) continue;
                foreach (var file in rootInfo.EnumerateFiles("*.jsonl", new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint }))
                { files.Add(file); if (files.Count >= MaxFiles) break; }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
        }
        if (files.Count == 0) return null;
        var today = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(now, zone).DateTime);
        decimal week = 0, lifetime = 0; long weekTokens = 0, lifetimeTokens = 0, priced = 0; int read = 0, skipped = 0;
        lock (gate)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var file in files)
            {
                token.ThrowIfCancellationRequested();
                seen.Add(file.FullName);
                if (file.Length > MaxFileBytes) { skipped++; continue; }
                if (!cache.TryGetValue(file.FullName, out var result) || result.Length != file.Length || result.Written != file.LastWriteTimeUtc)
                {
                    var deltas = ReadFile(file.FullName, zone);
                    if (deltas == null) { skipped++; cache.Remove(file.FullName); continue; }
                    cache[file.FullName] = result = new(file.Length, file.LastWriteTimeUtc, deltas);
                }
                read++;
                foreach (var d in result.Deltas)
                {
                    lifetimeTokens += d.Total; if (d.Priced) { priced += d.Total; lifetime += d.Usd; }
                    if (d.Day <= today && d.Day > today.AddDays(-7)) { weekTokens += d.Total; if (d.Priced) week += d.Usd; }
                }
            }
            foreach (var stale in cache.Keys.Where(k => !seen.Contains(k)).ToArray()) cache.Remove(stale);
        }
        return new(decimal.Round(week, 2), decimal.Round(lifetime, 2), weekTokens, lifetimeTokens, priced, read, skipped, now);
    }
    private static List<CostDelta>? ReadFile(string path, TimeZoneInfo zone)
    {
        try
        {
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 64 * 1024, FileOptions.SequentialScan);
            using var reader = new StreamReader(stream);
            return Read(reader, zone);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }
    /// <summary>Converts cumulative per-session counters to dated deltas. Exposed for tests with synthetic logs.</summary>
    public static List<CostDelta>? ReadForTest(TextReader reader, TimeZoneInfo zone) => Read(reader, zone);
    public static (long Total, decimal Usd, long Priced) Summarize(IEnumerable<CostDelta> deltas) =>
        deltas.Aggregate((0L, 0m, 0L), (a, d) => (a.Item1 + d.Total, a.Item2 + (d.Priced ? d.Usd : 0), a.Item3 + (d.Priced ? d.Total : 0)));
    private static List<CostDelta> Read(TextReader reader, TimeZoneInfo zone)
    {
        var output = new List<CostDelta>(); string? model = null; bool forked = false, baselined = false;
        long lastInput = 0, lastCached = 0, lastOutput = 0, lastTotal = 0;
        string? line;
        while ((line = reader.ReadLine()) != null)
        {
            if (line.Length > MaxLineBytes) continue;
            var interesting = line.Contains("\"token_count\"", StringComparison.Ordinal) || line.Contains("\"turn_context\"", StringComparison.Ordinal) || line.Contains("\"session_meta\"", StringComparison.Ordinal);
            if (!interesting) continue;
            JsonDocument document;
            try { document = JsonDocument.Parse(line); } catch (JsonException) { continue; }
            using (document)
            {
                var root = document.RootElement; if (root.ValueKind != JsonValueKind.Object) continue;
                var type = ProviderData.Text(ProviderData.Get(root, "type")); var payload = ProviderData.Get(root, "payload");
                if (type == "session_meta")
                {
                    // A forked or child thread starts from copied totals; its first checkpoint is a baseline, not new usage.
                    foreach (var key in new[] { "forked_from_id", "parent_thread_id", "parent_session_id", "fork_id" })
                        if (ProviderData.Text(ProviderData.Get(payload, key)) is { Length: > 0 }) forked = true;
                    continue;
                }
                if (type == "turn_context") { model = ProviderData.Text(ProviderData.Get(payload, "model")); continue; }
                if (type != "event_msg" || ProviderData.Text(ProviderData.Get(payload, "type")) != "token_count") continue;
                var usage = ProviderData.Get(ProviderData.Get(payload, "info"), "total_token_usage");
                if (!ProviderData.Object(usage)) continue;
                long Count(string key) => ProviderData.Integer(ProviderData.Get(usage, key)) ?? 0;
                var input = Count("input_tokens"); var cached = Count("cached_input_tokens"); var outputTokens = Count("output_tokens");
                var total = ProviderData.Integer(ProviderData.Get(usage, "total_tokens")) ?? input + outputTokens;
                if (!DateTimeOffset.TryParse(ProviderData.Text(ProviderData.Get(root, "timestamp")), CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var at)) continue;
                if (forked && !baselined) { baselined = true; (lastInput, lastCached, lastOutput, lastTotal) = (input, cached, outputTokens, total); continue; }
                baselined = true;
                // Counters are cumulative per session. A decrease means a new counter epoch; count it from zero.
                var reset = total < lastTotal || input < lastInput || outputTokens < lastOutput;
                var dInput = reset ? input : input - lastInput; var dCached = reset ? cached : Math.Max(0, cached - lastCached);
                var dOutput = reset ? outputTokens : outputTokens - lastOutput; var dTotal = reset ? total : total - lastTotal;
                (lastInput, lastCached, lastOutput, lastTotal) = (input, cached, outputTokens, total);
                if (dTotal <= 0) continue;
                var price = CodexPriceTable.For(model, at);
                var day = DateOnly.FromDateTime(TimeZoneInfo.ConvertTime(at, zone).DateTime);
                output.Add(new(day, dTotal, price == null ? 0 : CodexPriceTable.Cost(price, dInput, dCached, dOutput), price != null));
            }
        }
        return output;
    }
}
