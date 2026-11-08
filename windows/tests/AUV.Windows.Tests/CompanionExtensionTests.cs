using System.Security.Cryptography;
using System.Text.Json;

namespace AUV.Windows.Tests;

/// <summary>Static checks of the Chrome/Edge extension source in windows/browser-extension.</summary>
public class CompanionExtensionTests
{
    internal const string ExtensionId = "jnbjegolfmhehndgimjidefmggpnagji";
    internal static string Repository()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory != null; directory = directory.Parent)
            if (File.Exists(Path.Combine(directory.FullName, "windows", "browser-extension", "manifest.json"))) return directory.FullName;
        throw new DirectoryNotFoundException("Repository root not found.");
    }
    private static string Extension(string relative) => Path.Combine(Repository(), "windows", "browser-extension", relative);

    [Fact] public void ManifestAsksForTheLeastAccess()
    {
        using var manifest = JsonDocument.Parse(File.ReadAllText(Extension("manifest.json")));
        var root = manifest.RootElement;
        Assert.Equal(3, root.GetProperty("manifest_version").GetInt32());
        Assert.Equal(["nativeMessaging", "storage", "alarms"], root.GetProperty("permissions").EnumerateArray().Select(e => e.GetString()));
        Assert.Equal(["https://claude.ai/new*"], root.GetProperty("host_permissions").EnumerateArray().Select(e => e.GetString()));
        Assert.False(root.TryGetProperty("optional_permissions", out _));
        Assert.False(root.TryGetProperty("externally_connectable", out _));
        Assert.False(root.TryGetProperty("web_accessible_resources", out _));
        var script = Assert.Single(root.GetProperty("content_scripts").EnumerateArray());
        Assert.Equal(["https://claude.ai/new*"], script.GetProperty("matches").EnumerateArray().Select(e => e.GetString()));
        Assert.False(script.GetProperty("all_frames").GetBoolean());
        Assert.Equal(["Shared/claude-usage-extractor.js", "Shared/provider-ownership-v2.js", "Shared/content-script.js"], script.GetProperty("js").EnumerateArray().Select(e => e.GetString()));
        Assert.StartsWith("AUV ", root.GetProperty("name").GetString());
    }

    [Fact] public void ManifestKeyGivesTheFixedExtensionId()
    {
        using var manifest = JsonDocument.Parse(File.ReadAllText(Extension("manifest.json")));
        var key = Convert.FromBase64String(manifest.RootElement.GetProperty("key").GetString()!);
        // Chrome's ID: the first 16 bytes of SHA-256 of the public key, each hex digit mapped to a–p.
        var id = string.Concat(Convert.ToHexString(SHA256.HashData(key)[..16]).ToLowerInvariant().Select(c => (char)('a' + Convert.ToInt32(c.ToString(), 16))));
        Assert.Equal(ExtensionId, id);
        // Only a public key is in the repository.
        using var rsa = RSA.Create(); rsa.ImportSubjectPublicKeyInfo(key, out _);
        Assert.Throws<CryptographicException>(() => rsa.ExportRSAPrivateKey());
    }

    [Theory]
    [InlineData("claude-usage-extractor.js")] [InlineData("provider-ownership-v2.js")] [InlineData("owned-provider-tab-v2-reducer.js")] [InlineData("content-script.js")]
    public void VendoredSharedScriptsMatchTheMacOriginals(string file) =>
        Assert.Equal(SHA256.HashData(File.ReadAllBytes(Path.Combine(Repository(), "BrowserExtension", "Shared", file))), SHA256.HashData(File.ReadAllBytes(Extension(Path.Combine("Shared", file)))));

    [Fact] public void LoaderCarriesBuildPlaceholdersForPackaging()
    {
        var loader = File.ReadAllText(Extension("background-loader.js"));
        Assert.Contains("__AUV_COMPANION_BUILD__", loader); Assert.Contains("__AUV_RUNTIME_GENERATION_ID__", loader);
        Assert.Contains("com.silkrd.auv.claude_browser", loader);
        var worker = File.ReadAllText(Extension("background-chromium.js"));
        foreach (var api in new[] { "chrome.cookies", "cookies.get", "webRequest", "history.", "tabs.query", "executeScript", "fetch(" }) Assert.DoesNotContain(api, worker);
    }
}
