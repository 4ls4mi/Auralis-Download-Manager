using Auralis.WinUI;

if (!PreviewLayoutPolicy.UseCompactLayout(true,1920,1920) ||
    !PreviewLayoutPolicy.UseCompactLayout(false,960,1920) ||
    PreviewLayoutPolicy.UseCompactLayout(false,1600,1920) ||
    PreviewLayoutPolicy.UseCompactLayout(false,0,1920))
    throw new Exception("Preview window layout should adapt to maximized and narrow windows.");

if (WindowDragPolicy.ResizeEdge("West") != 1 || WindowDragPolicy.ResizeEdge("SouthEast") != 8)
    throw new Exception("Window resize directions must match the Windows system commands.");
bool invalidDirectionRejected=false;
try { WindowDragPolicy.ResizeEdge("unexpected"); } catch (InvalidOperationException) { invalidDirectionRejected=true; }
if (!invalidDirectionRejected) throw new Exception("Invalid resize direction accepted.");

if (!WindowClosePolicy.ShouldHide(true,true,false) || WindowClosePolicy.ShouldHide(true,false,false) ||
    WindowClosePolicy.ShouldHide(true,true,true) || WindowClosePolicy.ShouldHide(false,true,false))
    throw new Exception("Closing may hide only when a tray icon can restore the window and exit was not requested.");

if (TrayMenuPolicy.Entries.Select(entry=>entry.Id).Distinct().Count()!=TrayMenuPolicy.Entries.Length ||
    TrayMenuPolicy.Entries.Count(entry=>entry.Action=="start_queue")!=1 ||
    TrayMenuPolicy.Entries.Count(entry=>entry.Action=="stop_queue")!=1)
    throw new Exception("Tray actions must have unique identifiers and one entry per queue action.");

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
string downloadingTip=TrayTooltipPolicy.ForDownload(snapshot.Downloads[0]);
if (!downloadingTip.Contains("sample.zip") || !downloadingTip.Contains("30") || !downloadingTip.Contains("left"))
    throw new Exception("The hidden download tooltip should include file, progress and remaining time.");
if (!TrayTooltipPolicy.ForDownload(snapshot.Downloads[1]).Contains("size unknown"))
    throw new Exception("Unknown download size must not appear as zero percent.");
string longTip=new string('a',126)+"😀"+"b";
string clamped=TrayTooltipPolicy.Clamp(longTip);
if (clamped.Length>127 || char.IsHighSurrogate(clamped[^1])) throw new Exception("Tray tooltip truncation split a Unicode character.");
var tracker=new DownloadTransitionTracker();
if (tracker.Observe(snapshot).Count!=0) throw new Exception("Initial downloads must not trigger windows.");
using var transitionedJson=System.Text.Json.JsonDocument.Parse("""{"downloads":[{"id":1,"status":"Complete"},{"id":2,"status":"Downloading"},{"id":4,"status":"Downloading"}]}""");
var transitions=tracker.Observe(DownloadSnapshot.FromJson(transitionedJson.RootElement));
if (transitions.Count!=2 || !transitions.Any(item=>item.Id==1 && item.Status=="Complete") || !transitions.Any(item=>item.Id==4 && item.Status=="Downloading"))
    throw new Exception("Download transitions must fire once for new activity and completion.");
if (tracker.Observe(DownloadSnapshot.FromJson(transitionedJson.RootElement)).Count!=0) throw new Exception("Unchanged states must not reopen windows.");
Console.WriteLine("Downloader snapshot model checks passed.");

var request = BridgeMessage.Parse("https://auralis.local/index.html", """{"id":1,"command":"dashboard_snapshot"}""");
if (request.Command != "dashboard_snapshot") throw new Exception("Expected list request.");
var settingRequest = BridgeMessage.Parse("https://auralis.local/index.html", """{"id":2,"command":"update_glass_setting","key":"show_complete","value":"false"}""");
if (settingRequest.Key != "show_complete" || settingRequest.Value != "false") throw new Exception("Expected validated setting request.");
foreach (var pair in new[] {
    ("https://evil.example/index.html", """{"id":1,"command":"dashboard_snapshot"}"""),
    ("https://auralis.local/index.html", """{"id":1,"command":"delete_download"}"""),
    ("https://auralis.local/index.html", """{"id":1,"command":"update_glass_setting","key":"automation_api","value":"true"}"""),
    ("https://auralis.local/index.html", """{"id":1,"command":"add_download","url":"file:///secret"}""") })
{
    try { BridgeMessage.Parse(pair.Item1, pair.Item2); throw new Exception("Unsafe bridge request was accepted."); }
    catch (InvalidOperationException error) when (error.Message != "Unsafe bridge request was accepted.") { }
}
foreach (var command in new[] { "window_hide", "window_minimize", "window_toggle_maximize", "window_close", "window_is_maximized", "window_outer_position", "window_outer_size", "window_current_monitor" })
{
    var windowRequest = BridgeMessage.Parse("https://auralis.local/index.html", "{\"id\":1,\"command\":\"" + command + "\"}");
    if (windowRequest.Command != command) throw new Exception("Window control was not validated.");
}
var resizeRequest=BridgeMessage.Parse("https://auralis.local/index.html", """{"id":8,"command":"window_start_resize","direction":"NorthWest"}""");
if (resizeRequest.Value != "NorthWest") throw new Exception("Resize direction was not preserved.");
bool badResizeRejected=false;
try { BridgeMessage.Parse("https://auralis.local/index.html", """{"id":8,"command":"window_start_resize","direction":"invalid"}"""); } catch (InvalidOperationException) { badResizeRejected=true; }
if (!badResizeRejected) throw new Exception("Invalid resize request accepted.");
var exportRequest=BridgeMessage.Parse("https://auralis.local/index.html", """{"id":6,"command":"export_theme_file","contents":"{\"format\":\"auralis-theme\"}"}""");
if (exportRequest.Value is null || !exportRequest.Value.Contains("auralis-theme")) throw new Exception("Theme export was not preserved.");
var queueRequest=BridgeMessage.Parse("https://auralis.local/index.html", """{"id":7,"command":"queue_action","name":"Main download queue","action":"stop_queue"}""");
if (queueRequest.Key != "Main download queue" || queueRequest.Value != "stop_queue") throw new Exception("Queue request was not preserved.");
var limitRequest = BridgeMessage.Parse("https://auralis.local/index.html", """{"id":5,"command":"file_speed_limit","downloadId":7,"value":512}""");
if (limitRequest.DownloadId != 7 || limitRequest.Value != "512") throw new Exception("Speed limit request was not preserved.");
try { BridgeMessage.Parse("https://auralis.local/index.html", """{"id":5,"command":"file_speed_limit","downloadId":7,"value":10000001}"""); throw new Exception("Unbounded speed limit was accepted."); }
catch (InvalidOperationException) { }
var auxiliary = BridgeMessage.Parse("https://auralis.local/index.html", """{"id":4,"command":"open_glass_window","label":"settings","url":"/?settings=1","width":968,"height":765}""");
if (auxiliary.Label != "settings" || auxiliary.Url != "/?settings=1" || auxiliary.Width != 968) throw new Exception("Invalid auxiliary window request.");
foreach (var bad in new[] {
    """{"id":4,"command":"open_glass_window","label":"settings","url":"https://evil.example/","width":968,"height":765}""",
    """{"id":4,"command":"open_glass_window","label":"../settings","url":"/?settings=1","width":968,"height":765}""",
    """{"id":4,"command":"open_glass_window","label":"settings","url":"/?settings=1","width":99999,"height":765}""" })
{
    bool rejected=false;
    try { BridgeMessage.Parse("https://auralis.local/index.html",bad); } catch (InvalidOperationException) { rejected=true; }
    if (!rejected) throw new Exception("Unsafe auxiliary window request was accepted.");
}
Console.WriteLine("Web interface request validation checks passed.");

var lifecycleCalls = new List<DownloaderBridge.Operation>();
var lifetime = new DownloaderLifetime(operation => { lifecycleCalls.Add(operation); return Task.FromResult(default(System.Text.Json.JsonElement)); });
await Task.WhenAll(lifetime.StartAsync(), lifetime.StartAsync());
await Task.WhenAll(lifetime.StopAsync(), lifetime.StopAsync());
if (!lifecycleCalls.SequenceEqual(new[] { DownloaderBridge.Operation.InitializeDevelopmentProfile, DownloaderBridge.Operation.Start, DownloaderBridge.Operation.Stop }))
    throw new Exception("Downloader lifecycle must serialize and deduplicate start and stop.");
lifecycleCalls.Clear();
var failedStart = new DownloaderLifetime(operation => {
    lifecycleCalls.Add(operation);
    return operation == DownloaderBridge.Operation.Start
        ? Task.FromException<System.Text.Json.JsonElement>(new InvalidOperationException("start timed out"))
        : Task.FromResult(default(System.Text.Json.JsonElement));
});
try { await failedStart.StartAsync(); throw new Exception("Expected startup failure."); }
catch (InvalidOperationException error) when (error.Message == "start timed out") { }
await failedStart.StopAsync();
if (!lifecycleCalls.SequenceEqual(new[] { DownloaderBridge.Operation.InitializeDevelopmentProfile, DownloaderBridge.Operation.Start, DownloaderBridge.Operation.Stop }))
    throw new Exception("A failed start must still be followed by a stop attempt.");
Console.WriteLine("Downloader lifecycle checks passed.");

var appearanceRequest = BridgeMessage.Parse("https://auralis.local/index.html", """{"id":3,"command":"set_native_appearance","appearance":{"material":"window-glass","tint":[10,40,90],"light":false}}""");
if (appearanceRequest.Appearance is not { Backdrop: NativeBackdrop.Acrylic, Red: 10, Green: 40, Blue: 90, Light: false })
    throw new Exception("Native appearance must preserve the theme tint and chosen material.");
var customRequest = BridgeMessage.Parse("https://auralis.local/index.html", """{"id":4,"command":"set_native_appearance","appearance":{"material":"custom-6162","finish":"matte","translucency":25,"tint":[245,250,255],"light":true}}""");
if (customRequest.Appearance is not { Backdrop: NativeBackdrop.Mica, Light: true })
    throw new Exception("Custom matte materials should use Mica and preserve light mode.");
foreach (var appearance in new[] {
    """{"material":"window-glass","tint":[-1,0,0],"light":false}""",
    """{"material":"custom-bad!","finish":"clear","translucency":50,"tint":[0,0,0],"light":false}""",
    """{"material":"custom-6162","finish":"script","translucency":50,"tint":[0,0,0],"light":false}""",
    """{"material":"custom-6162","finish":"clear","translucency":101,"tint":[0,0,0],"light":false}""" })
{
    try { BridgeMessage.Parse("https://auralis.local/index.html", "{\"id\":5,\"command\":\"set_native_appearance\",\"appearance\":" + appearance + "}"); throw new Exception("Invalid appearance was accepted."); }
    catch (InvalidOperationException) { }
}
Console.WriteLine("Native appearance validation checks passed.");
