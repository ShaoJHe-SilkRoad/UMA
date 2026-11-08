using System.Globalization;

namespace AUV.Windows.Core;

public enum UiLanguage { English, Chinese }

/// <summary>Process-wide display language for text produced by Core. Tests may override it per async flow.</summary>
public static class UiText
{
    private static UiLanguage current = UiLanguage.English;
    private static readonly AsyncLocal<UiLanguage?> scoped = new();
    public static event Action? Changed;
    public static UiLanguage Current
    {
        get => scoped.Value ?? current;
        set { if (current == value) return; current = value; Changed?.Invoke(); }
    }
    public static bool IsChinese => Current == UiLanguage.Chinese;
    public static string T(string english, string chinese) => IsChinese ? chinese : english;
    /// <summary>"System" follows the Windows display language; anything else falls back to English.</summary>
    public static UiLanguage Resolve(string? preference, CultureInfo? culture = null) => preference switch
    {
        "zh" => UiLanguage.Chinese,
        "en" => UiLanguage.English,
        _ => (culture ?? CultureInfo.CurrentUICulture).TwoLetterISOLanguageName == "zh" ? UiLanguage.Chinese : UiLanguage.English
    };
    public static IDisposable Override(UiLanguage language)
    {
        var previous = scoped.Value; scoped.Value = language;
        return new Scope(() => scoped.Value = previous);
    }
    private sealed class Scope(Action restore) : IDisposable { public void Dispose() => restore(); }
}
