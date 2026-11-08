using System.IO;
using System.Text.Json;
using System.Windows;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace AUV.Windows.App;

/// <summary>
/// Opt-in companion checks (D17: run in WebView2). --companion-check-dir loads windows/tests/companion/harness.html
/// from a virtual https host mapped to the repository, in a throwaway WebView2 profile, and records each result.
/// The page never reaches the network: the host name is local to this WebView2 and claude.ai is never opened.
/// </summary>
internal static class CompanionVerification
{
    private const string VirtualHost = "auv-companion.test";
    public static string? RepositoryRoot()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory != null; directory = directory.Parent)
            if (File.Exists(Path.Combine(directory.FullName, "windows", "tests", "companion", "harness.html")) && Directory.Exists(Path.Combine(directory.FullName, "BrowserExtension", "Shared")))
                return directory.FullName;
        return null;
    }

    internal static async Task Run(string output)
    {
        Directory.CreateDirectory(output);
        var repository = RepositoryRoot();
        if (repository == null) { File.WriteAllText(Path.Combine(output, "NOT_RUN.txt"), "Run from a build inside the repository: the harness and the Mac fixtures are read from there."); return; }
        var profile = Path.Combine(Path.GetTempPath(), "auv-companion-check-" + Guid.NewGuid().ToString("N"));
        var view = new WebView2();
        var window = new Window { Width = 400, Height = 300, ShowInTaskbar = false, WindowStyle = WindowStyle.ToolWindow, Left = -10000, Top = -10000, Content = view, Title = "AUV companion checks" };
        try
        {
            window.Show();
            await view.EnsureCoreWebView2Async(await CoreWebView2Environment.CreateAsync(null, profile));
            var core = view.CoreWebView2;
            core.Settings.AreDevToolsEnabled = false;
            core.SetVirtualHostNameToFolderMapping(VirtualHost, repository, CoreWebView2HostResourceAccessKind.DenyCors);
            // Only the virtual host may load; anything else is refused before it leaves the machine.
            core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All);
            core.WebResourceRequested += (_, e) =>
            {
                if (!Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var uri) || uri.Host != VirtualHost)
                    e.Response = core.Environment.CreateWebResourceResponse(null, 403, "Blocked", "");
            };
            var done = new TaskCompletionSource<string>(TaskCreationOptions.RunContinuationsAsynchronously);
            core.WebMessageReceived += (_, e) => { try { done.TrySetResult(e.TryGetWebMessageAsString()); } catch (ArgumentException) { } };
            core.Navigate($"https://{VirtualHost}/windows/tests/companion/harness.html");
            var raw = await done.Task.WaitAsync(TimeSpan.FromMinutes(3));
            using var document = JsonDocument.Parse(raw);
            var results = document.RootElement.GetProperty("results").EnumerateArray()
                .Select(r => new { Name = r.GetProperty("name").GetString(), Pass = r.GetProperty("pass").GetBoolean(), Detail = r.GetProperty("detail").GetString() }).ToArray();
            File.WriteAllText(Path.Combine(output, "companion-checks.json"), JsonSerializer.Serialize(new { Runtime = core.Environment.BrowserVersionString, Results = results }, new JsonSerializerOptions { WriteIndented = true }));
            var failed = results.Where(r => !r.Pass).ToArray();
            File.WriteAllText(Path.Combine(output, failed.Length == 0 ? "PASS.txt" : "ERROR.txt"),
                $"{results.Length - failed.Length}/{results.Length} companion checks passed." + string.Concat(failed.Select(f => $"\nFAIL {f.Name}: {f.Detail}")));
        }
        catch (Exception e) when (e is TimeoutException or JsonException or InvalidOperationException or KeyNotFoundException or System.Runtime.InteropServices.COMException or WebView2RuntimeNotFoundException)
        { File.WriteAllText(Path.Combine(output, "ERROR.txt"), "Companion checks did not complete: " + e.GetType().Name + " " + e.Message); }
        finally
        {
            window.Close(); view.Dispose();
            try { Directory.Delete(profile, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
