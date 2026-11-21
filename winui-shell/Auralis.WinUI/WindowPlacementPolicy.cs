namespace Auralis.WinUI;

internal sealed record WindowPlacement(int Version, int X, int Y, int Width, int Height, bool Maximized, bool KeepInTray, bool StartMinimized);
internal readonly record struct WindowBounds(int X, int Y, int Width, int Height);

internal static class WindowPlacementPolicy
{
    internal static bool Valid(WindowPlacement? value) => value is { Version:1, Width:>=320 and <=16384, Height:>=120 and <=16384, X:>=-1000000 and <=1000000, Y:>=-1000000 and <=1000000 };

    internal static WindowBounds Fit(WindowBounds value, WindowBounds work)
    {
        if (work.Width<=0 || work.Height<=0) throw new ArgumentException("Invalid work area.");
        int width=Math.Min(Math.Max(1,value.Width),work.Width);
        int height=Math.Min(Math.Max(1,value.Height),work.Height);
        long maxX=(long)work.X+work.Width-width, maxY=(long)work.Y+work.Height-height;
        int x=(int)Math.Clamp((long)value.X,work.X,maxX);
        int y=(int)Math.Clamp((long)value.Y,work.Y,maxY);
        return new(x,y,width,height);
    }

    internal static WindowBounds BottomRight(WindowBounds work, int width, int height, int margin)
    {
        if (work.Width<=0 || work.Height<=0 || width<=0 || height<=0 || margin<0) throw new ArgumentException("Invalid notification placement.");
        width=Math.Min(width,work.Width);
        height=Math.Min(height,work.Height);
        long x=Math.Max((long)work.X,(long)work.X+work.Width-width-margin);
        long y=Math.Max((long)work.Y,(long)work.Y+work.Height-height-margin);
        return new((int)x,(int)y,width,height);
    }
}
