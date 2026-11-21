using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace Auralis.WinUI;

/// A single Windows notification-area icon owned by the preview window.
/// UI and downloader lifetime remain with the window, including on shell exit.
internal sealed class NativeTrayIcon : IDisposable
{
    private const uint NimAdd=0, NimModify=1, NimDelete=2;
    private const uint NifMessage=1, NifIcon=2, NifTip=4;
    private const uint WmApp=0x8000, WmLeftButtonUp=0x0202, WmRightButtonUp=0x0205, WmNull=0;
    private const uint TpmReturnCommand=0x0100, TpmRightButton=0x0002;
    private const uint MfString=0, MfGrayed=1, MfSeparator=0x0800;
    private const uint ImageIcon=1, LrLoadFromFile=0x10, LrDefaultSize=0x40;
    private const uint SubclassBase=0x41555240;
    private readonly IntPtr _hwnd, _icon;
    private readonly Action _show, _exit;
    private readonly Action<string>? _menuAction;
    private readonly Func<string,bool>? _menuEnabled;
    private readonly SubclassProc _subclass;
    private readonly uint _taskbarCreated, _iconId;
    private readonly bool _showMenu;
    private string _tooltip;
    private bool _disposed, _added;
    internal bool IsAvailable => !_disposed && _added;

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    private struct NotifyIconData
    {
        internal uint Size;
        internal IntPtr Window;
        internal uint Id, Flags, CallbackMessage;
        internal IntPtr Icon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] internal string Tip;
        internal uint State, StateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=256)] internal string Info;
        internal uint TimeoutOrVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] internal string InfoTitle;
        internal uint InfoFlags;
        internal Guid GuidItem;
        internal IntPtr BalloonIcon;
    }
    [StructLayout(LayoutKind.Sequential)] private struct Point { internal int X,Y; }
    private delegate IntPtr SubclassProc(IntPtr hwnd,uint message,UIntPtr wParam,IntPtr lParam,UIntPtr subclassId,UIntPtr data);

    [DllImport("comctl32.dll", SetLastError=true)] private static extern bool SetWindowSubclass(IntPtr hwnd,SubclassProc callback,UIntPtr id,UIntPtr data);
    [DllImport("comctl32.dll", SetLastError=true)] private static extern bool RemoveWindowSubclass(IntPtr hwnd,SubclassProc callback,UIntPtr id);
    [DllImport("comctl32.dll")] private static extern IntPtr DefSubclassProc(IntPtr hwnd,uint message,UIntPtr wParam,IntPtr lParam);
    [DllImport("shell32.dll",CharSet=CharSet.Unicode,EntryPoint="Shell_NotifyIconW",ExactSpelling=true,SetLastError=true)] private static extern bool ShellNotifyIcon(uint message,ref NotifyIconData data);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="LoadImageW",ExactSpelling=true,SetLastError=true)] private static extern IntPtr LoadImage(IntPtr instance,string path,uint type,int width,int height,uint flags);
    [DllImport("user32.dll",SetLastError=true)] private static extern bool DestroyIcon(IntPtr icon);
    [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="RegisterWindowMessageW",ExactSpelling=true)] private static extern uint RegisterWindowMessage(string name);
    [DllImport("user32.dll",SetLastError=true)] private static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="AppendMenuW",ExactSpelling=true,SetLastError=true)] private static extern bool AppendMenu(IntPtr menu,uint flags,UIntPtr id,string? text);
    [DllImport("user32.dll",SetLastError=true)] private static extern bool DestroyMenu(IntPtr menu);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint TrackPopupMenu(IntPtr menu,uint flags,int x,int y,int reserved,IntPtr owner,IntPtr rect);
    [DllImport("user32.dll",EntryPoint="PostMessageW",ExactSpelling=true)] private static extern bool PostMessage(IntPtr hwnd,uint message,UIntPtr wParam,IntPtr lParam);

    internal NativeTrayIcon(Window owner, Action show, Action exit, uint iconId=1, string tooltip="Auralis development preview", bool showMenu=true, Action<string>? menuAction=null, Func<string,bool>? menuEnabled=null)
    {
        _hwnd=WinRT.Interop.WindowNative.GetWindowHandle(owner);
        _show=show; _exit=exit; _subclass=OnWindowMessage;
        _iconId=iconId; _tooltip=TrayTooltipPolicy.Clamp(tooltip); _showMenu=showMenu; _menuAction=menuAction; _menuEnabled=menuEnabled;
        _taskbarCreated=RegisterWindowMessage("TaskbarCreated");
        var path=Path.Combine(AppContext.BaseDirectory,"Assets","Auralis.ico");
        _icon=LoadImage(IntPtr.Zero,path,ImageIcon,0,0,LrLoadFromFile|LrDefaultSize);
        if (_icon==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"Could not load the tray icon.");
        if (!SetWindowSubclass(_hwnd,_subclass,(UIntPtr)(SubclassBase+_iconId),UIntPtr.Zero))
        {
            DestroyIcon(_icon);
            throw new Win32Exception(Marshal.GetLastWin32Error(),"Could not attach the tray icon.");
        }
        try { Add(); }
        catch { RemoveWindowSubclass(_hwnd,_subclass,(UIntPtr)(SubclassBase+_iconId)); DestroyIcon(_icon); throw; }
    }

    private NotifyIconData Data() => new() {
        Size=(uint)Marshal.SizeOf<NotifyIconData>(), Window=_hwnd, Id=_iconId,
        Flags=NifMessage|NifIcon|NifTip, CallbackMessage=WmApp+42, Icon=_icon,
        Tip=_tooltip, Info="", InfoTitle=""
    };

    internal void SetTooltip(string value)
    {
        if (_disposed) return;
        value=TrayTooltipPolicy.Clamp(value);
        if (value==_tooltip) return;
        _tooltip=value;
        if (_added) { var data=Data(); ShellNotifyIcon(NimModify,ref data); }
    }

    internal static (int X,int Y) CursorPosition() => GetCursorPos(out var point) ? (point.X,point.Y) : (0,0);

    private void Add()
    {
        var data=Data();
        if (!ShellNotifyIcon(NimAdd,ref data)) throw new Win32Exception(Marshal.GetLastWin32Error(),"Could not create the tray icon.");
        _added=true;
    }

    private IntPtr OnWindowMessage(IntPtr hwnd,uint message,UIntPtr wParam,IntPtr lParam,UIntPtr id,UIntPtr data)
    {
        if (!_disposed && message==_taskbarCreated && _taskbarCreated!=0)
        {
            _added=false;
            try { Add(); } catch { try { _show(); } catch { } }
        }
        if (!_disposed && message==WmApp+42 && wParam.ToUInt64()==_iconId)
        {
            uint action=unchecked((uint)lParam.ToInt64());
            try { if (action==WmLeftButtonUp || (action==WmRightButtonUp && !_showMenu)) _show(); else if (action==WmRightButtonUp) ShowMenu(); }
            catch { /* Never propagate an exception through a native window callback. */ }
            return IntPtr.Zero;
        }
        return DefSubclassProc(hwnd,message,wParam,lParam);
    }

    private void ShowMenu()
    {
        var menu=CreatePopupMenu();
        if (menu==IntPtr.Zero) return;
        try
        {
            foreach (var entry in TrayMenuPolicy.Entries)
            {
                if (entry.Action=="exit" && !AppendMenu(menu,MfSeparator,UIntPtr.Zero,null)) return;
                bool enabled=entry.Action is "show" or "exit" || (_menuEnabled?.Invoke(entry.Action) ?? false);
                if (!AppendMenu(menu,MfString | (enabled ? 0u : MfGrayed),(UIntPtr)entry.Id,entry.Label)) return;
            }
            if (!GetCursorPos(out var point)) return;
            SetForegroundWindow(_hwnd);
            uint selected=TrackPopupMenu(menu,TpmReturnCommand|TpmRightButton,point.X,point.Y,0,_hwnd,IntPtr.Zero);
            PostMessage(_hwnd,WmNull,UIntPtr.Zero,IntPtr.Zero);
            var action=TrayMenuPolicy.Entries.FirstOrDefault(entry=>entry.Id==selected)?.Action;
            if (action=="show") _show();
            else if (action=="exit") _exit();
            else if (action is not null && (_menuEnabled?.Invoke(action) ?? false)) _menuAction?.Invoke(action);
        }
        finally { DestroyMenu(menu); }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed=true;
        if (_added) { var data=Data(); ShellNotifyIcon(NimDelete,ref data); _added=false; }
        RemoveWindowSubclass(_hwnd,_subclass,(UIntPtr)(SubclassBase+_iconId));
        DestroyIcon(_icon);
        GC.KeepAlive(_subclass);
    }
}
