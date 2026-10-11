using System.Security.Cryptography;
using System.Text;
namespace AUV.Windows.App;

/// <summary>One process per Windows preference profile; a second launch requests the existing main window.</summary>
internal sealed class PreviewInstance : IDisposable
{
    private readonly Mutex mutex;
    private EventWaitHandle? signal;
    private RegisteredWaitHandle? wait;
    public bool IsOwner { get; }
    public PreviewInstance(string settingsPath, Action restore)
    {
        var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(System.IO.Path.GetFullPath(settingsPath).ToUpperInvariant())))[..24];
        var name = @"Local\AUV.Windows.Preview." + key;
        mutex = new Mutex(false, name);
        try { IsOwner = mutex.WaitOne(0); } catch (AbandonedMutexException) { IsOwner = true; }
        if (IsOwner)
        {
            signal = new(false, EventResetMode.AutoReset, name + ".Show");
            wait = ThreadPool.RegisterWaitForSingleObject(signal, (_, _) => restore(), null, Timeout.Infinite, false);
        }
        else
        {
            try { using var existing = EventWaitHandle.OpenExisting(name + ".Show"); existing.Set(); }
            catch (WaitHandleCannotBeOpenedException) { /* First launch is still initializing and will show its main window. */ }
        }
    }
    public void Dispose()
    { wait?.Unregister(null); signal?.Dispose(); if (IsOwner) mutex.ReleaseMutex(); mutex.Dispose(); }
}
