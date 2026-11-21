using Auralis.WinUI;

var materials = MaterialPolicy.BuiltIns;
if (materials.Length != 8 || materials.Select(m => m.Id).Distinct().Count() != materials.Length)
    throw new Exception("Every built-in material must have a unique backdrop policy.");
if (materials.Single(m => m.Id == "frosted-water-351").Backdrop != NativeBackdrop.Acrylic ||
    materials.Single(m => m.Id == "window-glass").Backdrop != NativeBackdrop.Acrylic ||
    materials.Single(m => m.Id == "rose-pine").Backdrop != NativeBackdrop.Mica ||
    materials.Single(m => m.Id == "oversimplified").Backdrop != NativeBackdrop.MicaAlt)
    throw new Exception("A built-in material was mapped to the wrong native backdrop.");
if (materials.Single(m => m.Id == "window-glass").OverlayOpacity >= materials.Single(m => m.Id == "builtin-smoked-glass").OverlayOpacity)
    throw new Exception("Window Glass should leave more of the backdrop visible than Smoked Glass.");
Console.WriteLine("WinUI material policy checks passed.");

using var snapshotJson = System.Text.Json.JsonDocument.Parse("""{"downloads":[{"id":1,"file":"sample.zip","status":"Downloading","size":100,"downloaded":30,"speed":5},{"id":2,"status":"Downloading","size":null},{"id":3,"status":"Complete","size":null}],"speed":5}""");
var snapshot = DownloadSnapshot.FromJson(snapshotJson.RootElement);
if (snapshot.Downloads.Count != 3 || snapshot.Downloads[0].Progress != 30 || snapshot.Downloads[1].Progress != null || snapshot.Downloads[2].Progress != 100)
    throw new Exception("Download progress does not match the downloader snapshot.");
using var invalidJson = System.Text.Json.JsonDocument.Parse("{} ");
try { DownloadSnapshot.FromJson(invalidJson.RootElement); throw new Exception("Invalid snapshots must be rejected."); }
catch (System.Text.Json.JsonException) { }
Console.WriteLine("Downloader snapshot model checks passed.");

var request = BridgeMessage.Parse("https://auralis.local/index.html", """{"id":1,"command":"dashboard_snapshot"}""");
if (request.Command != "dashboard_snapshot") throw new Exception("Expected list request.");
foreach (var pair in new[] {
    ("https://evil.example/index.html", """{"id":1,"command":"dashboard_snapshot"}"""),
    ("https://auralis.local/index.html", """{"id":1,"command":"delete_download"}"""),
    ("https://auralis.local/index.html", """{"id":1,"command":"add_download","url":"file:///secret"}""") })
{
    try { BridgeMessage.Parse(pair.Item1, pair.Item2); throw new Exception("Unsafe bridge request was accepted."); }
    catch (InvalidOperationException error) when (error.Message != "Unsafe bridge request was accepted.") { }
}
Console.WriteLine("Web interface request validation checks passed.");
