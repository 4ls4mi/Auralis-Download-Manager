using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace Auralis.WinUI;

internal static class NativeWindowDrag
{
    private const uint WmSysCommand = 0x0112;
    private const int ScMove = 0xF010;
    private const int ScSize = 0xF000;
    private const int HtCaption = 2;
    private const int VkLeftButton = 0x01;

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();
    [DllImport("user32.dll", EntryPoint = "PostMessageW", ExactSpelling = true, SetLastError = true)]
    private static extern bool PostMessageW(IntPtr hwnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int key);

    internal static void Start(Window window, string? resizeDirection)
    {
        // Only accept a live pointer gesture; a delayed or synthetic request
        // must not make a window unexpectedly start moving.
        if ((GetAsyncKeyState(VkLeftButton) & 0x8000) == 0)
            throw new InvalidOperationException("The pointer gesture has ended.");
        int command = resizeDirection is null ? ScMove | HtCaption : ScSize | WindowDragPolicy.ResizeEdge(resizeDirection);
        var hwnd=WinRT.Interop.WindowNative.GetWindowHandle(window);
        ReleaseCapture();
        if (!PostMessageW(hwnd,WmSysCommand,new IntPtr(command),IntPtr.Zero))
            throw new Win32Exception(Marshal.GetLastWin32Error(),"Could not move or resize the window.");
    }
}
