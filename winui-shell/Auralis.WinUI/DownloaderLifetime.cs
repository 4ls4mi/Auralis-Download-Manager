using System.Text.Json;

namespace Auralis.WinUI;

/// Serializes downloader startup and shutdown. The native window must await
/// StopAsync before exiting; a failed or timed-out start can still leave the
/// embedded worker alive, so it also requires a stop attempt.
internal sealed class DownloaderLifetime
{
    internal enum Profile { Development, Installed }
    private readonly Func<DownloaderBridge.Operation, Task<JsonElement>> _call;
    private readonly Profile _profile;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private bool _mightBeRunning;
    private bool _started;

    internal DownloaderLifetime(Func<DownloaderBridge.Operation, Task<JsonElement>>? call = null, Profile profile = Profile.Development)
    {
        _call = call ?? DownloaderBridge.CallAsync;
        _profile = profile;
    }

    internal async Task StartAsync()
    {
        await _gate.WaitAsync();
        try
        {
            if (_started) return;
            await _call(_profile == Profile.Installed ? DownloaderBridge.Operation.InitializeInstalledProfile : DownloaderBridge.Operation.InitializeDevelopmentProfile);
            _mightBeRunning = true;
            await _call(DownloaderBridge.Operation.Start);
            _started = true;
        }
        finally { _gate.Release(); }
    }

    internal async Task StopAsync()
    {
        await _gate.WaitAsync();
        try
        {
            if (!_mightBeRunning) return;
            await _call(DownloaderBridge.Operation.Stop);
            _started = false;
            _mightBeRunning = false;
        }
        finally { _gate.Release(); }
    }
}
