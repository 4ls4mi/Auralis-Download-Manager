using System.Text.Json;

namespace Auralis.WinUI;

/// Serializes downloader startup and shutdown. The native window must await
/// StopAsync before exiting; a failed or timed-out start can still leave the
/// embedded worker alive, so it also requires a stop attempt.
internal sealed class DownloaderLifetime
{
    private readonly Func<DownloaderBridge.Operation, Task<JsonElement>> _call;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private bool _mightBeRunning;
    private bool _started;

    internal DownloaderLifetime(Func<DownloaderBridge.Operation, Task<JsonElement>>? call = null) =>
        _call = call ?? DownloaderBridge.CallAsync;

    internal async Task StartAsync()
    {
        await _gate.WaitAsync();
        try
        {
            if (_started) return;
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
