using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace AUV.Windows.Core;

public sealed class ProviderPreferences
{
    public bool CodexEnabled { get; set; } = true;
    public string? CodexExecutable { get; set; }
    public bool WorkBuddyConsent { get; set; }
}

public static class ProviderData
{
    public static AgentPresentation Unavailable(string id, string message, ConnectionState state = ConnectionState.Unavailable)
    {
        var (name, mark) = id switch { "codex" => ("Codex", "C"), "claude" => ("Claude", "✳"), "workbuddy" => ("WorkBuddy", "W"), "antigravity" => ("Antigravity", "A"), _ => throw new ArgumentOutOfRangeException(nameof(id)) };
        return new(id, name, mark, UsageSnapshot.Unknown, false,
            new(id, name, mark, null, AllowanceKind.Unavailable, null, null, UiText.T("Quota unavailable", "额度不可用"), message,
                UiText.T("No current verified data", "没有当前的已验证数据"), state), UiText.T("Secondary allowance", "另一额度"), UiText.T("Unavailable", "不可用"));
    }
    public static string Observed(DateTimeOffset time) => UiText.T("Verified ", "已验证 ") + time.ToLocalTime().ToString("MMM dd HH:mm:ss zzz", CultureInfo.InvariantCulture);
    internal static bool Object(JsonElement e) => e.ValueKind == JsonValueKind.Object;
    internal static JsonElement Get(JsonElement e, string key) => Object(e) && e.TryGetProperty(key, out var v) ? v : default;
    internal static string? Text(JsonElement e) => e.ValueKind == JsonValueKind.String ? e.GetString() : null;
    internal static long? Integer(JsonElement e) => e.ValueKind == JsonValueKind.Number && e.TryGetInt64(out var v) && v >= 0 ? v : null;
}

public static class CodexUsageDecoder
{
    private static QuotaWindow? ReadWindow(JsonElement value, string id)
    {
        var used = ProviderData.Get(value, "usedPercent");
        // 0.17.2 compatibility: newer clients name the length windowDurationMinutes; older ones windowDurationMins.
        var minutes = ProviderData.Integer(ProviderData.Get(value, "windowDurationMinutes")) ?? ProviderData.Integer(ProviderData.Get(value, "windowDurationMins"));
        if (used.ValueKind != JsonValueKind.Number || !used.TryGetDouble(out var percent) || !double.IsFinite(percent) || percent < 0 || percent > 100 || minutes is null or 0) return null;
        DateTimeOffset? reset = null;
        if (ProviderData.Integer(ProviderData.Get(value, "resetsAt")) is long unix)
            try { reset = DateTimeOffset.FromUnixTimeSeconds(unix); } catch (ArgumentOutOfRangeException) { }
        return new(id, minutes.Value, 100 - percent, reset);
    }
    private static string Label(QuotaWindow? window) => window?.Label ?? UiText.T("Window unavailable", "窗口不可用");
    public static AgentPresentation Decode(JsonElement accountResult, JsonElement rateResult, JsonElement usageResult, DateTimeOffset now) =>
        Decode(accountResult, rateResult, usageResult, now, null);
    /// <summary>Decodes one read. <paramref name="previous"/> is the in-memory selection from the prior read, if any.</summary>
    public static AgentPresentation Decode(JsonElement accountResult, JsonElement rateResult, JsonElement usageResult, DateTimeOffset now, QuotaSelection? previous)
    {
        var account = ProviderData.Get(accountResult, "account");
        if (ProviderData.Text(ProviderData.Get(account, "type")) != "chatgpt") return ProviderData.Unavailable("codex", UiText.T("Sign in to Codex with ChatGPT to read plan allowances.", "请在 Codex 中用 ChatGPT 登录后再读取套餐额度。"), ConnectionState.Disconnected);
        var buckets = ProviderData.Get(rateResult, "rateLimitsByLimitId");
        // A populated multi-bucket response must select Codex explicitly; never borrow another product's bucket.
        var bucket = ProviderData.Object(buckets) && buckets.EnumerateObject().Any() ? ProviderData.Get(buckets, "codex") : ProviderData.Get(rateResult, "rateLimits");
        var bucketId = ProviderData.Text(ProviderData.Get(bucket, "limitId"));
        if (bucketId != null && bucketId != "codex") bucket = default;
        var windows = new[] { ReadWindow(ProviderData.Get(bucket, "primary"), "codex.primary"), ReadWindow(ProviderData.Get(bucket, "secondary"), "codex.secondary") }.OfType<QuotaWindow>().ToArray();
        var weekly = windows.FirstOrDefault(w => w.Minutes == 10080);
        var selectedId = QuotaWindowPolicy.Select(windows, previous, now);
        var primary = windows.FirstOrDefault(w => w.Id == selectedId);
        var secondary = windows.FirstOrDefault(w => !ReferenceEquals(w, primary));
        var plan = ProviderData.Text(ProviderData.Get(bucket, "planType")) ?? ProviderData.Text(ProviderData.Get(account, "planType"));
        var kind = primary != null ? AllowanceKind.Percentage : AllowanceKind.Unavailable;
        var credits = ProviderData.Get(bucket, "credits");
        if (primary == null && ProviderData.Get(credits, "unlimited").ValueKind == JsonValueKind.True) kind = AllowanceKind.Unlimited;
        var days = new SortedDictionary<DateOnly, long>(); var daily = ProviderData.Get(usageResult, "dailyUsageBuckets");
        var today = DateOnly.FromDateTime(now.UtcDateTime);
        if (daily.ValueKind == JsonValueKind.Array)
        {
            foreach (var day in daily.EnumerateArray().Take(1000))
            {
                if (!DateOnly.TryParseExact(ProviderData.Text(ProviderData.Get(day, "startDate")), "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var date) || date > today || date < today.AddDays(-6)) continue;
                var tokens = ProviderData.Integer(ProviderData.Get(day, "tokens")); if (tokens == null || days.ContainsKey(date)) { days.Clear(); break; }
                days.Add(date, tokens.Value);
            }
        }
        long? weekTokens = null;
        if (days.Count == 7) { try { weekTokens = days.Values.Aggregate(0L, (a, b) => checked(a + b)); } catch (OverflowException) { days.Clear(); } }
        var lifetime = ProviderData.Integer(ProviderData.Get(ProviderData.Get(usageResult, "summary"), "lifetimeTokens"));
        var usage = new UsageSnapshot(weekly?.Remaining, windows.FirstOrDefault(w => w.Minutes == 300)?.Remaining, weekTokens, lifetime, null,
            days.Select(d => new DayUsage(d.Key.ToString("MMM dd", CultureInfo.InvariantCulture), d.Value)).ToArray());
        var source = UiText.T("Codex app-server · official local account source", "Codex app-server · 官方本地账户来源");
        var card = new AllowanceCard("codex", "Codex", "C", plan, kind, primary?.Remaining, null, Label(primary), source, ProviderData.Observed(now), ConnectionState.Connected)
        { WindowMinutes = primary?.Minutes, ResetsAt = primary?.ResetsAt, ObservedAt = now };
        return new("codex", "Codex", "C", usage, false, card, UiText.T("Other · ", "另一窗口 · ") + Label(secondary),
            secondary == null ? UsageSnapshot.RemainingText(null) : UsageSnapshot.RemainingText(secondary.Remaining), UiText.T("Codex account/usage/read · account tokens · service daily buckets", "Codex account/usage/read · 账户令牌 · 服务端每日统计"))
        { Selection = new(selectedId, windows), Windows = windows };
    }
}

public static class WorkBuddyCreditsDecoder
{
    private const decimal Maximum = 999999999999.99m;
    private static decimal Credit(JsonElement e)
    {
        var text = ProviderData.Text(e);
        if (text == null || !Regex.IsMatch(text, @"^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,2})?$", RegexOptions.CultureInvariant) ||
            !decimal.TryParse(text, NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out var value) || value < 0 || value > Maximum)
            throw new InvalidDataException("Malformed Credits.");
        return value;
    }
    private static long? Timestamp(JsonElement e)
    {
        if (e.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return null;
        // WebView2 may serialize JavaScript epoch numbers in decimal/exponent notation.
        // Accept exact integer milliseconds in any JSON numeric notation, never truncate.
        if (e.ValueKind != JsonValueKind.Number || !e.TryGetDecimal(out var value) ||
            value < 0 || value > 253402300799999m || decimal.Truncate(value) != value)
            throw new InvalidDataException("Invalid pool dates.");
        return (long)value;
    }
    public static bool IsUsagePage(Uri? uri) => uri is { Scheme: "https", Host: "www.workbuddy.cn", AbsolutePath: "/profile/plans-usage", Query.Length: 0, Fragment.Length: 0, UserInfo.Length: 0 } && uri.IsDefaultPort;
    public static AgentPresentation Decode(JsonElement payload, DateTimeOffset now)
    {
        var failure = ProviderData.Text(ProviderData.Get(payload, "failure"));
        if (failure != null) throw new InvalidDataException(failure switch
        {
            "incompletePoolSections" => "Not all current Credit sections or pools are visible.",
            "unexpectedPage" => "The official page layout could not be recognized.",
            "pageNotStabilized" => "The official page is still loading.",
            "ambiguousCredits" => "The official page has ambiguous Credit rows.",
            _ => "Official page is not ready for a verified Credits read."
        });
        if (ProviderData.Integer(ProviderData.Get(payload, "extractorVersion")) != 3) throw new InvalidDataException("Unsupported Credits extractor version.");
        var sections = ProviderData.Get(payload, "discoveredSections");
        if (sections.ValueKind != JsonValueKind.Array || !sections.EnumerateArray().Select(ProviderData.Text).Order().SequenceEqual(new[] { "addOn", "benefitGift", "subscription" })) throw new InvalidDataException("Incomplete Credit sections.");
        var identities = new HashSet<string>(); decimal sum = 0; var included = 0;
        var sectionTotals = new Dictionary<string, (int Count, decimal Remaining)>();
        foreach (var section in new[] { ("subscriptionPools", 16), ("addOnPools", 32), ("benefitGiftPools", 64) })
        {
            decimal sectionRemaining = 0; var sectionCount = 0;
            var rows = ProviderData.Get(payload, section.Item1);
            if (rows.ValueKind != JsonValueKind.Array || rows.GetArrayLength() > section.Item2 || section.Item1 == "subscriptionPools" && rows.GetArrayLength() == 0) throw new InvalidDataException("Incomplete Credit pools.");
            foreach (var row in rows.EnumerateArray())
            {
                var kind = ProviderData.Text(ProviderData.Get(row, "kind"));
                if (!(section.Item1 == "subscriptionPools" ? kind is "subscriptionBase" or "subscriptionBonus" : section.Item1 == "addOnPools" ? kind == "addOn" : kind == "benefitGift")) throw new InvalidDataException("Invalid Credit pool kind.");
                var used = Credit(ProviderData.Get(row, "used")); var total = Credit(ProviderData.Get(row, "total"));
                if (total <= 0 || used > total) throw new InvalidDataException("Invalid Credit pool balance.");
                var remaining = total - used; var displayed = ProviderData.Get(row, "displayedRemaining");
                if (displayed.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined) && Math.Abs(Credit(displayed) - remaining) > .01m) throw new InvalidDataException("Credit pool balance mismatch.");
                var effective = Timestamp(ProviderData.Get(row, "effectiveAtMilliseconds")); var expires = Timestamp(ProviderData.Get(row, "expiresAtMilliseconds"));
                if (effective != null && expires != null && effective >= expires) throw new InvalidDataException("Invalid pool date order.");
                var status = ProviderData.Text(ProviderData.Get(row, "pageStatus"));
                if (status is not ("available" or "active" or "exhausted" or "expired" or "future" or "unavailable" or "historical")) throw new InvalidDataException("Ambiguous pool status.");
                var id = ProviderData.Text(ProviderData.Get(row, "stablePageID"));
                if (id != null && !Regex.IsMatch(id, "^[a-z0-9][a-z0-9-]{0,63}$", RegexOptions.CultureInvariant)) throw new InvalidDataException("Invalid pool identity.");
                var identity = id != null ? $"{kind}|id:{id}" : FormattableString.Invariant($"{kind}|{used}|{total}|{effective}|{expires}|{status}");
                if (!identities.Add(identity)) throw new InvalidDataException("Duplicate Credit pool.");
                if (status is "available" or "active" or "exhausted" && (effective == null || effective <= now.ToUnixTimeMilliseconds()) && (expires == null || expires > now.ToUnixTimeMilliseconds()))
                { sum += remaining; included++; sectionRemaining += remaining; sectionCount++; if (sum > Maximum) throw new InvalidDataException("Credit balance is too large."); }
            }
            sectionTotals.Add(section.Item1.Replace("Pools", ""), (sectionCount, sectionRemaining));
        }
        var summaries = ProviderData.Get(payload, "sectionSummaries"); var seenSections = new HashSet<string>();
        if (summaries.ValueKind != JsonValueKind.Array || summaries.GetArrayLength() != 2) throw new InvalidDataException("Credit section summaries are incomplete.");
        foreach (var summary in summaries.EnumerateArray())
        {
            var key = ProviderData.Text(ProviderData.Get(summary, "section"));
            if (key is not ("addOn" or "benefitGift") || !seenSections.Add(key)) throw new InvalidDataException("Credit section summaries are ambiguous.");
            var expected = sectionTotals[key];
            if (ProviderData.Integer(ProviderData.Get(summary, "count")) != expected.Count || Math.Abs(Credit(ProviderData.Get(summary, "remaining")) - expected.Remaining) > .01m)
                throw new InvalidDataException("Current pool rows do not match the official section summary. Show all current pools and retry.");
        }
        var authoritative = ProviderData.Get(payload, "authoritativePageBalances");
        if (authoritative.ValueKind != JsonValueKind.Array || authoritative.GetArrayLength() > 1) throw new InvalidDataException("Ambiguous account balance.");
        if (authoritative.GetArrayLength() == 1 && Math.Abs(Credit(authoritative[0]) - sum) > .01m) throw new InvalidDataException("Account balance reconciliation failed.");
        return new("workbuddy", "WorkBuddy", "W", UsageSnapshot.Unknown, false,
            new AllowanceCard("workbuddy", "WorkBuddy", "W", null, AllowanceKind.Credits, null, sum, UiText.T("Shared Buddy AI Credits", "共享 Buddy AI Credits"),
                UiText.T("WorkBuddy official Plan and Usage page · verified eligible pools: ", "WorkBuddy 官方套餐与用量页 · 已核对的有效额度池：") + included,
                ProviderData.Observed(now), ConnectionState.Connected) { ObservedAt = now }, UiText.T("Secondary allowance", "另一额度"), UiText.T("Unavailable", "不可用"));
    }
}
