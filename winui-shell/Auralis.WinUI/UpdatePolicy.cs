using System.Text.Json;
using System.Text.RegularExpressions;

namespace Auralis.WinUI;

internal sealed record UpdateCandidate(string Version, string Notes, Uri Installer, string Sha256, long Size);

/// Validates release metadata before an update can be offered or downloaded.
internal static class UpdatePolicy
{
    internal const long MaximumInstallerBytes=256L*1024*1024;
    private const string ReleasePath="/4ls4mi/Auralis-Download-Manager/releases/download/";
    private static readonly Regex VersionPattern=new(@"^[0-9]+\.[0-9]+\.[0-9]+$",RegexOptions.CultureInvariant | RegexOptions.NonBacktracking);

    internal static UpdateCandidate? Select(JsonElement releases,string currentVersion)
    {
        if (releases.ValueKind!=JsonValueKind.Array || !TryVersion(currentVersion,out var installed))
            throw new InvalidOperationException("Invalid update metadata.");
        UpdateCandidate? latest=null;
        Version? latestVersion=null;
        foreach (var release in releases.EnumerateArray())
        {
            if (release.ValueKind!=JsonValueKind.Object || IsTrue(release,"draft") || IsTrue(release,"prerelease")) continue;
            if (!release.TryGetProperty("tag_name",out var tagValue) || tagValue.ValueKind!=JsonValueKind.String) continue;
            string tag=tagValue.GetString()!;
            string version=tag.StartsWith('v') || tag.StartsWith('V') ? tag[1..] : tag;
            if (!TryVersion(version,out var parsed) || parsed<=installed) continue;
            if (!release.TryGetProperty("assets",out var assets) || assets.ValueKind!=JsonValueKind.Array) continue;
            string[] names={ $"Auralis.Download.Manager_{version}_x64-setup.exe", $"Auralis Download Manager_{version}_x64-setup.exe" };
            var matches=assets.EnumerateArray().Where(asset=>asset.ValueKind==JsonValueKind.Object &&
                asset.TryGetProperty("name",out var name) && name.ValueKind==JsonValueKind.String && names.Contains(name.GetString(),StringComparer.Ordinal)).ToArray();
            if (matches.Length==0) continue;
            if (matches.Length!=1) throw new InvalidOperationException("The release contains multiple matching installers.");
            var selected=matches[0];
            string nameValue=selected.GetProperty("name").GetString()!;
            if (!selected.TryGetProperty("browser_download_url",out var urlValue) || urlValue.ValueKind!=JsonValueKind.String ||
                !Uri.TryCreate(urlValue.GetString(),UriKind.Absolute,out var url) || url.Scheme!=Uri.UriSchemeHttps ||
                !url.Host.Equals("github.com",StringComparison.OrdinalIgnoreCase) || !url.IsDefaultPort || url.UserInfo.Length!=0 ||
                url.Query.Length!=0 || url.Fragment.Length!=0 || Uri.UnescapeDataString(url.AbsolutePath)!=ReleasePath+tag+"/"+nameValue)
                throw new InvalidOperationException("The release installer address is invalid.");
            if (!selected.TryGetProperty("digest",out var digestValue) || digestValue.ValueKind!=JsonValueKind.String ||
                digestValue.GetString() is not string digest || !digest.StartsWith("sha256:",StringComparison.Ordinal) ||
                digest.Length!=71 || !digest.AsSpan(7).ToString().All(Uri.IsHexDigit))
                throw new InvalidOperationException("The release installer digest is invalid.");
            if (!selected.TryGetProperty("size",out var sizeValue) || !sizeValue.TryGetInt64(out long size) || size<=0 || size>MaximumInstallerBytes)
                throw new InvalidOperationException("The release installer size is invalid.");
            string notes=release.TryGetProperty("body",out var body) && body.ValueKind==JsonValueKind.String ? body.GetString() ?? "" : "";
            if (notes.Length>65536) notes=notes[..65536];
            if (latestVersion is null || parsed>latestVersion)
            {
                latest=new(version,notes,url,digest[7..].ToLowerInvariant(),size);
                latestVersion=parsed;
            }
        }
        return latest;
    }

    internal static bool TryVersion(string text,out Version version)
    {
        version=new Version(0,0,0);
        if (text.Length>48 || !VersionPattern.IsMatch(text) || !Version.TryParse(text,out var parsed) || parsed is null) return false;
        version=parsed;
        return true;
    }
    private static bool IsTrue(JsonElement value,string name) => value.TryGetProperty(name,out var flag) && flag.ValueKind==JsonValueKind.True;
}
