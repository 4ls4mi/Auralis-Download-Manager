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
