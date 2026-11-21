namespace Auralis.WinUI;

internal sealed record DownloadTransition(ulong Id, string Status);

/// Observes state changes without opening windows for downloads merely loaded
/// from an earlier session. The owner decides how to present each transition.
internal sealed class DownloadTransitionTracker
{
    private Dictionary<ulong,string>? _previous;

    internal IReadOnlyList<DownloadTransition> Observe(DownloadSnapshot snapshot)
    {
        var next=snapshot.Downloads.ToDictionary(item=>item.Id,item=>item.Status);
        var transitions=new List<DownloadTransition>();
        if (_previous is not null)
            foreach (var item in snapshot.Downloads)
                if ((!_previous.TryGetValue(item.Id,out var previous) || previous!=item.Status) &&
                    (item.Status is "Downloading" or "Complete"))
                    transitions.Add(new(item.Id,item.Status));
        _previous=next;
        return transitions;
    }

    internal void Reset() => _previous=null;
}
