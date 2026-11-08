using System.Diagnostics;
using System.Text;
using System.Text.Json;
using AUV.Windows.App;
using AUV.Windows.Core;
using Microsoft.Win32;

namespace AUV.Windows.Tests;

/// <summary>Registration under a throwaway HKCU test key, and the real native host relaying between a stand-in browser and AUV's pipe.</summary>
public class ClaudeBrowserBridgeTests : IDisposable
{
    private readonly string temp = Path.Combine(Path.GetTempPath(), "auv-companion-" + Guid.NewGuid().ToString("N"));
    private readonly string registryBase = @"Software\AUV-Test-" + Guid.NewGuid().ToString("N");
    public ClaudeBrowserBridgeTests() => Directory.CreateDirectory(temp);
    public void Dispose()
    {
        Registry.CurrentUser.DeleteSubKeyTree(registryBase, false);
        try { Directory.Delete(temp, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private string Package(string build, string generation = ClaudeBrowserTests.Generation)
    {
        var root = Path.Combine(temp, "package-" + build);
        Directory.CreateDirectory(Path.Combine(root, "host")); Directory.CreateDirectory(Path.Combine(root, "extension", "Shared"));
        File.WriteAllBytes(Path.Combine(root, "companion.json"), (ClaudeBrowserTests.Manifest with { CompanionBuild = build, RuntimeGenerationId = generation }).ToJson());
        File.WriteAllText(Path.Combine(root, "host", ClaudeBrowserSetup.HostExecutable), "stand-in " + build);
        File.WriteAllText(Path.Combine(root, "extension", "manifest.json"), "{\"build\":\"" + build + "\"}");
        File.WriteAllText(Path.Combine(root, "extension", "Shared", "x.js"), "//");
        return root;
    }
    private string? Value(string browserPath) { using var key = Registry.CurrentUser.OpenSubKey(registryBase + @"\" + browserPath); return key?.GetValue(null) as string; }
    private const string PipeName = "AUV.Windows.Preview.0123456789ABCDEF01234567.ClaudeBrowser";

    [Fact] public void InstallRegistersBothBrowsersAndWritesAStrictHostManifest()
    {
        var install = Path.Combine(temp, "browser-companion");
        var setup = new ClaudeBrowserSetup(install, Package("2026110801"), PipeName, Registry.CurrentUser, registryBase);
        Assert.Equal(CompanionInstallState.NotInstalled, setup.Status().State);
        var manifest = setup.Install(false);
        var status = setup.Status();
        Assert.Equal(CompanionInstallState.Installed, status.State); Assert.Equal(["chrome", "edge"], status.RegisteredBrowsers);
        foreach (var (_, path) in ClaudeBrowserSetup.Browsers) Assert.Equal(setup.HostManifestPath(manifest), Value(path));
        using var host = JsonDocument.Parse(File.ReadAllText(setup.HostManifestPath(manifest)));
        Assert.Equal(["name", "description", "path", "type", "allowed_origins"], host.RootElement.EnumerateObject().Select(p => p.Name));
        Assert.Equal(ClaudeBrowserContract.NativeHostName, host.RootElement.GetProperty("name").GetString());
        Assert.Equal("AUV.BrowserHost.exe", host.RootElement.GetProperty("path").GetString());
        Assert.Equal([ClaudeBrowserTests.Manifest.ExtensionOrigin], host.RootElement.GetProperty("allowed_origins").EnumerateArray().Select(e => e.GetString()));
        using var config = JsonDocument.Parse(File.ReadAllText(Path.Combine(Path.GetDirectoryName(setup.HostManifestPath(manifest))!, "host-config.json")));
        Assert.Equal(PipeName, config.RootElement.GetProperty("pipeName").GetString());
        // Nothing secret is written: the files hold names, paths, the extension origin and the build identity only.
        var written = string.Join("\n", Directory.GetFiles(install, "*.json", SearchOption.AllDirectories).Select(File.ReadAllText));
        Assert.DoesNotContain("token", written, StringComparison.OrdinalIgnoreCase); Assert.DoesNotContain("cookie", written, StringComparison.OrdinalIgnoreCase);
    }

    [Fact] public void ForeignRegistrationIsReportedNotReplacedOrRemoved()
    {
        var install = Path.Combine(temp, "browser-companion");
        using (var key = Registry.CurrentUser.CreateSubKey(registryBase + @"\" + ClaudeBrowserSetup.Browsers[0].Path)) key.SetValue(null, @"C:\Other\host.json");
        var setup = new ClaudeBrowserSetup(install, Package("2026110801"), PipeName, Registry.CurrentUser, registryBase);
        Assert.Equal(["chrome"], setup.Status().ForeignRegistrations);
        Assert.Equal(["chrome"], Assert.Throws<ForeignRegistrationException>(() => setup.Install(false)).Browsers);
        Assert.False(Directory.Exists(install));
        setup.Remove(false);
        Assert.Equal(@"C:\Other\host.json", Value(ClaudeBrowserSetup.Browsers[0].Path));
    }

    [Fact] public void UpdateKeepsTheOldHostFolderAndBacksUpTheExtension()
    {
        var install = Path.Combine(temp, "browser-companion");
        new ClaudeBrowserSetup(install, Package("2026110801"), PipeName, Registry.CurrentUser, registryBase).Install(false);
        var newer = new ClaudeBrowserSetup(install, Package("2026110902", "7a0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e"), PipeName, Registry.CurrentUser, registryBase);
        Assert.Equal(CompanionInstallState.UpdateAvailable, newer.Status().State);
        newer.Install(false);
        Assert.Equal(CompanionInstallState.Installed, newer.Status().State);
        Assert.True(File.Exists(Path.Combine(install, "host", "2026110801", ClaudeBrowserSetup.HostExecutable)));
        Assert.True(File.Exists(Path.Combine(install, "host", "2026110902", ClaudeBrowserSetup.HostExecutable)));
        var backup = Assert.Single(Directory.GetDirectories(install, "extension.backup-2026110801-*"));
        Assert.Contains("2026110801", File.ReadAllText(Path.Combine(backup, "manifest.json")));
        Assert.Contains("2026110902", File.ReadAllText(Path.Combine(install, "extension", "manifest.json")));
    }

    [Fact] public void RemoveDeletesOnlyAuvsKeysAndOnlyDeletesFilesWhenAsked()
    {
        var install = Path.Combine(temp, "browser-companion");
        var setup = new ClaudeBrowserSetup(install, Package("2026110801"), PipeName, Registry.CurrentUser, registryBase);
        setup.Install(false); setup.Remove(false);
        foreach (var (_, path) in ClaudeBrowserSetup.Browsers) Assert.Null(Value(path));
        Assert.True(Directory.Exists(install));
        setup.Remove(true); Assert.False(Directory.Exists(install));
    }

    // ---- The real host process between a stand-in browser (stdio) and AUV's pipe ----

    private static string HostBuildOutput()
    {
        var testBin = AppContext.BaseDirectory; // …\tests\AUV.Windows.Tests\bin\<Configuration>\net10.0-windows\
        var configuration = new DirectoryInfo(testBin).Parent!.Name;
        var windows = Path.GetFullPath(Path.Combine(testBin, "..", "..", "..", "..", ".."));
        return Path.Combine(windows, "src", "AUV.Windows.BrowserHost", "bin", configuration, "net10.0", "win-x64");
    }

    private (Process Host, Stream Input, Stream Output) StartHost(string install, string pipeName, string origin)
    {
        var folder = Path.Combine(install, "host", "2026110801");
        Directory.CreateDirectory(folder);
        foreach (var file in Directory.GetFiles(HostBuildOutput())) File.Copy(file, Path.Combine(folder, Path.GetFileName(file)), true);
        File.WriteAllText(Path.Combine(folder, "host-config.json"), $$"""{"schemaVersion":1,"pipeName":"{{pipeName}}","allowedOrigin":"{{ClaudeBrowserTests.Manifest.ExtensionOrigin}}","runtimeGenerationID":"{{ClaudeBrowserTests.Generation}}","hostVersion":"1.0.0","hostBuild":"2026110801"}""");
        var start = new ProcessStartInfo(Path.Combine(folder, "AUV.BrowserHost.exe")) { RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false, CreateNoWindow = true };
        start.ArgumentList.Add(origin); start.ArgumentList.Add("--parent-window=0");
        var host = Process.Start(start)!;
        return (host, host.StandardInput.BaseStream, host.StandardOutput.BaseStream);
    }

    private static async Task<CompanionMessage> NextForExtension(Stream output)
    {
        var frame = await CompanionFraming.ReadAsync(output, 4096, CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(15));
        return CompanionMessageCodec.DecodeForExtension(frame!);
    }

    [Fact] public async Task HostRelaysBothWaysAndOnlyForTheConfiguredExtension()
    {
        var install = Path.Combine(temp, "browser-companion");
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        using var server = new ClaudeBrowserPipeServer(pipeName, ClaudeBrowserTests.Manifest, ClaudeBrowserPipeServer.InstalledHostOnly(install), () => "auto");
        var received = new List<CompanionMessage>(); var connected = new TaskCompletionSource();
        server.Received += m => { lock (received) received.Add(m); };
        server.StateChanged += () => { if (server.State == CompanionLinkState.Connected) connected.TrySetResult(); };
        server.Start();
        var (host, input, output) = StartHost(install, pipeName, ClaudeBrowserTests.Manifest.ExtensionOrigin);
        try
        {
            Assert.Equal(new HostStatus(true), await NextForExtension(output));
            await connected.Task.WaitAsync(TimeSpan.FromSeconds(15));
            Assert.Equal(ClaudeBrowserTests.Manifest.ExtensionOrigin, server.Host!.ExtensionOrigin);
            // AUV → extension
            var wake = new CompanionCommand(ClaudeBrowserContract.WakeCommand, ClaudeBrowserContract.NewRequestId());
            Assert.True(await server.SendAsync(wake, CancellationToken.None));
            Assert.Equal(wake, await NextForExtension(output));
            // extension → AUV, including a message the allowlist refuses (it is dropped, the link stays up)
            await CompanionFraming.WriteAsync(input, Encoding.UTF8.GetBytes("{\"kind\":\"claudeBrowserTerminalPacket\",\"cookie\":\"x\"}"), 4096, CancellationToken.None);
            await CompanionFraming.WriteAsync(input, Encoding.UTF8.GetBytes(ClaudeBrowserTests.Ready(wake.RequestId)), 4096, CancellationToken.None);
            for (var i = 0; i < 100 && received.Count == 0; i++) await Task.Delay(100);
            var ready = Assert.IsType<CompanionEvent>(Assert.Single(received));
            Assert.Equal(wake.RequestId, ready.RequestId);
            // The extension's own ping is answered by the host.
            await CompanionFraming.WriteAsync(input, CompanionMessageCodec.Encode(new CompanionPing(ClaudeBrowserContract.NewRequestId())), 4096, CancellationToken.None);
            Assert.Equal(new HostStatus(true), await NextForExtension(output));
            // The browser closing the port ends the host, and AUV sees the browser go.
            input.Close();
            Assert.True(host.WaitForExit(15000)); Assert.Equal(0, host.ExitCode);
            for (var i = 0; i < 50 && server.State == CompanionLinkState.Connected; i++) await Task.Delay(100);
            Assert.Equal(CompanionLinkState.NoBrowser, server.State);
        }
        finally { if (!host.HasExited) host.Kill(); host.Dispose(); }
    }

    [Fact] public async Task HostRefusesAnotherExtension()
    {
        var install = Path.Combine(temp, "browser-companion");
        var (host, _, _) = StartHost(install, PipeName, "chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/");
        try { Assert.True(await Task.Run(() => host.WaitForExit(15000))); Assert.Equal(2, host.ExitCode); }
        finally { if (!host.HasExited) host.Kill(); host.Dispose(); }
    }

    [Fact] public async Task PipeRefusesAProcessThatIsNotTheInstalledHost()
    {
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        using var server = new ClaudeBrowserPipeServer(pipeName, ClaudeBrowserTests.Manifest, ClaudeBrowserPipeServer.InstalledHostOnly(Path.Combine(temp, "browser-companion")), () => "auto");
        server.Start();
        using var client = new System.IO.Pipes.NamedPipeClientStream(".", pipeName, System.IO.Pipes.PipeDirection.InOut, System.IO.Pipes.PipeOptions.Asynchronous | System.IO.Pipes.PipeOptions.CurrentUserOnly);
        await client.ConnectAsync(5000);
        // This test process is not AUV.BrowserHost.exe, so the server hangs up without a welcome.
        var hello = CompanionMessageCodec.Encode(new HostHello("1.0.0", "2026110801", ClaudeBrowserTests.Manifest.ExtensionOrigin, "chrome", ClaudeBrowserTests.Generation));
        try { await CompanionFraming.WriteAsync(client, hello, 8192, CancellationToken.None); } catch (IOException) { }
        Assert.Null(await CompanionFraming.ReadAsync(client, 8192, CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10)));
        Assert.Equal(CompanionLinkState.NoBrowser, server.State);
    }

    [Fact] public async Task WrongBuildIsRejectedAsNeedingAnUpdate()
    {
        var pipeName = "AUV.Windows.Preview." + Convert.ToHexString(Guid.NewGuid().ToByteArray())[..24] + ".ClaudeBrowser";
        var newer = ClaudeBrowserTests.Manifest with { RuntimeGenerationId = "9b0c2d3e-8a41-4b7c-9d2e-1f3a4b5c6d7e" };
        using var server = new ClaudeBrowserPipeServer(pipeName, newer, _ => true, () => "auto");
        var changed = new TaskCompletionSource(); server.StateChanged += () => changed.TrySetResult();
        server.Start();
        using var client = new System.IO.Pipes.NamedPipeClientStream(".", pipeName, System.IO.Pipes.PipeDirection.InOut, System.IO.Pipes.PipeOptions.Asynchronous | System.IO.Pipes.PipeOptions.CurrentUserOnly);
        await client.ConnectAsync(5000);
        await CompanionFraming.WriteAsync(client, CompanionMessageCodec.Encode(new HostHello("1.0.0", "2026110801", ClaudeBrowserTests.Manifest.ExtensionOrigin, "edge", ClaudeBrowserTests.Generation)), 8192, CancellationToken.None);
        var welcome = Assert.IsType<HostWelcome>(CompanionMessageCodec.DecodeFromApp((await CompanionFraming.ReadAsync(client, 8192, CancellationToken.None))!));
        Assert.Equal(new HostWelcome(false, "generationMismatch"), welcome);
        await changed.Task.WaitAsync(TimeSpan.FromSeconds(5));
        Assert.Equal(CompanionLinkState.Rejected, server.State);
    }

    [Fact] public void PipeNameFollowsTheProfileKey()
    {
        var name = ClaudeBrowserPaths.PipeName(@"C:\Users\x\AppData\Local\AUV.Windows.UI.Preview\settings.v1.json");
        Assert.Matches("^AUV\\.Windows\\.Preview\\.[0-9A-F]{24}\\.ClaudeBrowser$", name);
        Assert.Equal(name, ClaudeBrowserPaths.PipeName(@"c:\users\x\appdata\local\AUV.Windows.UI.Preview\settings.v1.json"));
        Assert.Equal(@"C:\Users\x\AppData\Local\AUV.Windows.UI.Preview\browser-companion", ClaudeBrowserPaths.InstallRoot(@"C:\Users\x\AppData\Local\AUV.Windows.UI.Preview\settings.v1.json"));
    }
}
