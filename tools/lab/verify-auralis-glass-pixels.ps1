<#
.SYNOPSIS
Measures whether an installed Auralis window passes through the color behind it.
.EXAMPLE
powershell.exe -NoProfile -STA -File tools/lab/verify-auralis-glass-pixels.ps1 -WindowHandle 527166 -FocusDelaySeconds 4
.DESCRIPTION
Use an isolated instance with an empty download list and a desktop glass material.
Keep the exact main HWND foreground in an interactive Windows session. Use
FocusDelaySeconds to switch from a console to Auralis before the measurement. The helper
places a temporary nonactivating color fixture immediately beneath that window
and reads three pixels within the empty list. No screen images are saved.
Exit codes are 0 for visible backing, 1 for an opaque result or error, and 2 when
focus, window placement, or the desktop does not allow a measurement.
#>
param(
    [Parameter(Mandatory)][long]$WindowHandle,
    [ValidateRange(0, 30)][int]$FocusDelaySeconds = 0
)
$ErrorActionPreference = 'Stop'

Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

public static class AuralisGlassPixelProbe
{
    private const uint PlaceWithoutActivation = 0x0010 | 0x0040 | 0x0200;
    private const uint CopyCompositedPixels = 0x00CC0020 | 0x40000000;

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr window, out Rect bounds);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr window, ref Point point);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll")] private static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr after,
        int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr window);
    [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr window, IntPtr context);
    [DllImport("gdi32.dll", SetLastError = true)] private static extern bool BitBlt(IntPtr target,
        int x, int y, int width, int height, IntPtr source, int sourceX, int sourceY, uint operation);
    [DllImport("dwmapi.dll")] private static extern int DwmFlush();

    private sealed class Fixture : Form
    {
        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams parameters = base.CreateParams;
                parameters.ExStyle |= 0x08000000 | 0x00000080; // no activation, no taskbar entry
                return parameters;
            }
        }
    }

    private static Rectangle ClientBounds(IntPtr target)
    {
        Rect client;
        Point origin = Point.Empty;
        if (!GetClientRect(target, out client) || !ClientToScreen(target, ref origin))
            return Rectangle.Empty;
        return new Rectangle(origin.X, origin.Y, client.Right - client.Left, client.Bottom - client.Top);
    }

    private static Color[] Sample(IntPtr target, Fixture fixture, Rectangle bounds, Point[] points, Color backing)
    {
        fixture.BackColor = backing;
        fixture.Refresh();
        Application.DoEvents();
        Thread.Sleep(350);
        DwmFlush();

        const uint NextWindow = 2;
        const uint RootWindow = 2;
        if (GetForegroundWindow() != target || ClientBounds(target) != bounds
            || GetWindow(target, NextWindow) != fixture.Handle)
            return null;

        var colors = new Color[points.Length];
        IntPtr desktop = GetDC(IntPtr.Zero);
        if (desktop == IntPtr.Zero)
            throw new InvalidOperationException("Could not open the interactive desktop for pixel sampling.");

        try
        {
            using (var pixels = new Bitmap(points.Length, 1, PixelFormat.Format32bppRgb))
            {
                using (var graphics = Graphics.FromImage(pixels))
                {
                    IntPtr bitmap = graphics.GetHdc();
                    try
                    {
                        for (int index = 0; index < points.Length; index++)
                        {
                            Point point = points[index];
                            if (GetAncestor(WindowFromPoint(point), RootWindow) != target)
                                return null;
                            if (!BitBlt(bitmap, index, 0, 1, 1, desktop, point.X, point.Y, CopyCompositedPixels))
                                throw new Win32Exception(Marshal.GetLastWin32Error());
                        }
                    }
                    finally { graphics.ReleaseHdc(bitmap); }
                }
                for (int index = 0; index < points.Length; index++)
                    colors[index] = pixels.GetPixel(index, 0);
            }
        }
        finally { ReleaseDC(IntPtr.Zero, desktop); }

        return GetForegroundWindow() == target && ClientBounds(target) == bounds ? colors : null;
    }

    private static string Hex(Color color)
    {
        return String.Format("#{0:X2}{1:X2}{2:X2}", color.R, color.G, color.B);
    }

    public static object Measure(long handle)
    {
        if (!Environment.UserInteractive)
            return new { Status = "inconclusive", Reason = "No interactive desktop." };

        IntPtr target = new IntPtr(handle);
        if (GetForegroundWindow() != target)
            return new { Status = "inconclusive", Reason = "The target main window is not foreground." };

        IntPtr previousDpi = SetThreadDpiAwarenessContext(new IntPtr(-4)); // Per Monitor V2
        try
        {
            Rectangle bounds = ClientBounds(target);
            if (bounds.Width < 440 || bounds.Height < 300)
                return new { Status = "inconclusive", Reason = "The target client area is too small for the known empty-list sample points." };

            Point[] points = {
                new Point(bounds.Left + bounds.Width * 64 / 100, bounds.Top + bounds.Height * 72 / 100),
                new Point(bounds.Left + bounds.Width * 76 / 100, bounds.Top + bounds.Height * 72 / 100),
                new Point(bounds.Left + bounds.Width * 88 / 100, bounds.Top + bounds.Height * 72 / 100)
            };
            Color red = Color.FromArgb(234, 24, 24);
            Color cyan = Color.FromArgb(24, 234, 234);
            using (var fixture = new Fixture {
                FormBorderStyle = FormBorderStyle.None, ShowInTaskbar = false,
                StartPosition = FormStartPosition.Manual, Bounds = bounds, BackColor = red
            })
            {
                fixture.Show();
                if (!SetWindowPos(fixture.Handle, target, bounds.Left, bounds.Top,
                    bounds.Width, bounds.Height, PlaceWithoutActivation))
                    return new { Status = "inconclusive", Reason = "Could not place the fixture directly behind the main window." };

                Color[] first = Sample(target, fixture, bounds, points, red);
                Color[] changed = Sample(target, fixture, bounds, points, cyan);
                Color[] restored = Sample(target, fixture, bounds, points, red);
                if (first == null || changed == null || restored == null)
                    return new { Status = "inconclusive", Reason = "Focus, bounds, or stacking order changed during sampling." };

                var samples = new object[points.Length];
                int matching = 0;
                for (int index = 0; index < points.Length; index++)
                {
                    Color a = first[index], b = changed[index], c = restored[index];
                    int shift = (a.R - b.R) + (b.G - a.G) + (b.B - a.B);
                    int repeatError = Math.Abs(a.R - c.R) + Math.Abs(a.G - c.G) + Math.Abs(a.B - c.B);
                    bool visible = shift >= 24 && repeatError <= 18;
                    if (visible) matching++;
                    samples[index] = new { First = Hex(a), Changed = Hex(b), Restored = Hex(c), Visible = visible };
                }
                return new { Status = matching >= 2 ? "visible" : "opaque", Samples = samples };
            }
        }
        finally
        {
            if (previousDpi != IntPtr.Zero)
                SetThreadDpiAwarenessContext(previousDpi);
        }
    }
}
'@

if ($FocusDelaySeconds -gt 0) { Start-Sleep -Seconds $FocusDelaySeconds }
$result = [AuralisGlassPixelProbe]::Measure($WindowHandle)
$result | ConvertTo-Json -Depth 4 -Compress
switch ($result.Status) {
    'visible' { exit 0 }
    'inconclusive' { exit 2 }
    default { exit 1 }
}
