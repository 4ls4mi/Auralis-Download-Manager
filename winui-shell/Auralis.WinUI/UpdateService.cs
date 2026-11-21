using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text.Json;

namespace Auralis.WinUI;

/// Downloads only a verified candidate selected from the fixed Auralis feeds.
/// Installation is deliberately not enabled for the development preview.
internal sealed class UpdateService : IDisposable
{
    private const string PrimaryFeed="https://api.github.com/repos/4ls4mi/Auralis-Download-Manager/releases?per_page=30";
    private const string FallbackFeed="https://auralis-release-push.auralis-updates.workers.dev/latest";
    private const int MaximumFeedBytes=4*1024*1024;
    private static readonly HashSet<string> DownloadHosts=new(StringComparer.OrdinalIgnoreCase) {
        "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com", "objects-origin.githubusercontent.com"
    };
    private readonly HttpClient _client;
    private readonly SemaphoreSlim _gate=new(1,1);
    private UpdateCandidate? _candidate;
    private string? _staged;

    internal UpdateService()
    {
        _client=new HttpClient(new HttpClientHandler { AllowAutoRedirect=false, UseCookies=false }) { Timeout=TimeSpan.FromMinutes(10) };
        _client.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("AuralisDownloadManager","1.0"));
        _client.DefaultRequestHeaders.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    }

    internal async Task<UpdateCandidate?> CheckAsync(string currentVersion,CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            byte[] body;
            try { body=await ReadFeedWithTimeoutAsync(PrimaryFeed,cancellationToken); }
            catch (Exception error) when (error is HttpRequestException or IOException or JsonException or TaskCanceledException)
            {
                cancellationToken.ThrowIfCancellationRequested();
                body=await ReadFeedWithTimeoutAsync(FallbackFeed,cancellationToken);
            }
            using var json=JsonDocument.Parse(body,new JsonDocumentOptions { MaxDepth=32 });
            var next=UpdatePolicy.Select(json.RootElement,currentVersion);
            if (next is null || _candidate is null || next.Installer!=_candidate.Installer || next.Sha256!=_candidate.Sha256 || next.Size!=_candidate.Size)
                _staged=null;
            _candidate=next;
            return next;
        }
        finally { _gate.Release(); }
    }

    private async Task<byte[]> ReadFeedWithTimeoutAsync(string address,CancellationToken token)
    {
        using var timeout=CancellationTokenSource.CreateLinkedTokenSource(token);
        timeout.CancelAfter(TimeSpan.FromSeconds(15));
        return await ReadFeedAsync(address,timeout.Token);
    }

    private async Task<byte[]> ReadFeedAsync(string address,CancellationToken token)
    {
        using var response=await _client.GetAsync(address,HttpCompletionOption.ResponseHeadersRead,token);
        response.EnsureSuccessStatusCode();
        if (response.Content.Headers.ContentLength is long size && size>MaximumFeedBytes) throw new IOException("The update feed is too large.");
        await using var input=await response.Content.ReadAsStreamAsync(token);
        using var output=new MemoryStream();
        byte[] buffer=new byte[32768];
        while (true)
        {
            int count=await input.ReadAsync(buffer,token);
            if (count==0) break;
            if (output.Length+count>MaximumFeedBytes) throw new IOException("The update feed is too large.");
            output.Write(buffer,0,count);
        }
        // Validate here so malformed primary JSON falls back to the cached feed.
        using var parsed=JsonDocument.Parse(output.ToArray(),new JsonDocumentOptions { MaxDepth=32 });
        if (parsed.RootElement.ValueKind!=JsonValueKind.Array) throw new JsonException("The update feed is invalid.");
        return output.ToArray();
    }

    internal async Task<bool> IsCurrentAsync(string version,CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try { return _candidate?.Version==version; }
        finally { _gate.Release(); }
    }

    internal async Task<string> DownloadAsync(string folder,Action<long,long>? progress,CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var candidate=_candidate ?? throw new InvalidOperationException("Check for updates first.");
            LocalWebviewBridge.EnsureDevelopmentDirectory(folder);
            string temp=Path.Combine(folder,"update-"+Guid.NewGuid().ToString("N")+".part");
            string final=Path.ChangeExtension(temp,".exe");
            try
            {
                using var response=await DownloadResponseAsync(candidate.Installer,cancellationToken);
                if (response.Content.Headers.ContentLength is long declared && declared!=candidate.Size) throw new IOException("The installer size does not match the release.");
                await using var input=await response.Content.ReadAsStreamAsync(cancellationToken);
                await using var output=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None,65536,FileOptions.Asynchronous);
                using var hash=IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
                byte[] buffer=new byte[65536]; long total=0;
                while (true)
                {
                    int count=await input.ReadAsync(buffer,cancellationToken);
                    if (count==0) break;
                    total+=count;
                    if (total>candidate.Size || total>UpdatePolicy.MaximumInstallerBytes) throw new IOException("The installer size does not match the release.");
                    hash.AppendData(buffer,0,count);
                    await output.WriteAsync(buffer.AsMemory(0,count),cancellationToken);
                    progress?.Invoke(total,candidate.Size);
                }
                await output.FlushAsync(cancellationToken);
                output.Flush(flushToDisk:true);
                if (total!=candidate.Size || !CryptographicOperations.FixedTimeEquals(hash.GetHashAndReset(),Convert.FromHexString(candidate.Sha256)))
                    throw new IOException("Installer verification failed.");
                await output.DisposeAsync();
                File.Move(temp,final);
                _staged=final;
                return final;
            }
            finally { if (File.Exists(temp)) File.Delete(temp); }
        }
        finally { _gate.Release(); }
    }

    private async Task<HttpResponseMessage> DownloadResponseAsync(Uri address,CancellationToken token)
    {
        for (int redirects=0;redirects<=5;redirects++)
        {
            if (address.Scheme!=Uri.UriSchemeHttps || !address.IsDefaultPort || address.UserInfo.Length!=0 || address.Fragment.Length!=0 || !DownloadHosts.Contains(address.Host))
                throw new IOException("The installer redirected to an unsupported address.");
            var response=await _client.GetAsync(address,HttpCompletionOption.ResponseHeadersRead,token);
            if ((int)response.StatusCode is >=300 and <400)
            {
                var location=response.Headers.Location;
                response.Dispose();
                if (location is null || redirects==5) throw new IOException("The installer redirect is invalid.");
                address=location.IsAbsoluteUri ? location : new Uri(address,location);
                continue;
            }
            try { response.EnsureSuccessStatusCode(); return response; }
            catch { response.Dispose(); throw; }
        }
        throw new IOException("The installer redirected too many times.");
    }

    internal async Task<bool> VerifyStagedAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (_candidate is null || _staged is null) return false;
            await using var file=new FileStream(_staged,FileMode.Open,FileAccess.Read,FileShare.Read,65536,FileOptions.Asynchronous);
            return await UpdateVerifier.VerifyAsync(file,_candidate.Size,_candidate.Sha256,cancellationToken);
        }
        finally { _gate.Release(); }
    }

    // In-flight calls may still release the gate after cancellation.
    public void Dispose() { _client.Dispose(); }
}
