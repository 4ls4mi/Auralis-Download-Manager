// Windows 11 host-backdrop composition feasibility experiment.
// Separate from the app; no display capture, saved pixels, or injected overlays.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <dwmapi.h>
#include <DispatcherQueue.h>
#include <windows.ui.composition.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.UI.Composition.Desktop.h>
#include <string>
#pragma comment(lib, "windowsapp.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "CoreMessaging.lib")
using namespace winrt;
using namespace Windows::UI::Composition;
using namespace Windows::UI::Composition::Desktop;
namespace {
Windows::System::DispatcherQueueController queue{nullptr};
Compositor compositor{nullptr};
DesktopWindowTarget target{nullptr};
SpriteVisual surface{nullptr};
void initialize_compositor(){
 init_apartment(apartment_type::single_threaded);
 DispatcherQueueOptions options{sizeof(DispatcherQueueOptions),DQTYPE_THREAD_CURRENT,DQTAT_COM_STA};
 check_hresult(CreateDispatcherQueueController(options,reinterpret_cast<ABI::Windows::System::IDispatcherQueueController**>(put_abi(queue))));
 compositor=Compositor();
}
void resize(HWND hwnd){
 if(!surface)return;RECT rect{};GetClientRect(hwnd,&rect);
 surface.Size({static_cast<float>(rect.right-rect.left),static_cast<float>(rect.bottom-rect.top)});
}
void attach(HWND hwnd){
 // Windows 11 22000+: enables host backdrop brushes for this window.
 BOOL enabled=TRUE;check_hresult(DwmSetWindowAttribute(hwnd,DWMWA_USE_HOSTBACKDROPBRUSH,&enabled,sizeof(enabled)));
 auto interop=compositor.as<ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop>();
 check_hresult(interop->CreateDesktopWindowTarget(hwnd,true,reinterpret_cast<ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget**>(put_abi(target))));
 surface=compositor.CreateSpriteVisual();surface.Brush(compositor.CreateHostBackdropBrush());resize(hwnd);target.Root(surface);
}
LRESULT CALLBACK proc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp){
 switch(msg){case WM_SIZE:resize(hwnd);return 0;case WM_NCHITTEST:{LRESULT hit=DefWindowProcW(hwnd,msg,wp,lp);return hit==HTCLIENT?HTCAPTION:hit;}case WM_DESTROY:surface=nullptr;target=nullptr;PostQuitMessage(0);return 0;}
 return DefWindowProcW(hwnd,msg,wp,lp);
}
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,LPWSTR command,int show){
 try{
  initialize_compositor();if(std::wstring(command)==L"--self-test")return 0;
  WNDCLASSW cls{};cls.hInstance=instance;cls.lpfnWndProc=proc;cls.lpszClassName=L"MHGHostBackdropLab";cls.hCursor=LoadCursor(nullptr,IDC_ARROW);
  if(!RegisterClassW(&cls))return 2;
  HWND hwnd=CreateWindowExW(WS_EX_NOREDIRECTIONBITMAP,cls.lpszClassName,L"Mister Hybrid Glass - host backdrop lab",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,800,500,nullptr,nullptr,instance,nullptr);
  if(!hwnd)return 3;attach(hwnd);ShowWindow(hwnd,show);
  MSG msg{};while(GetMessageW(&msg,nullptr,0,0)>0){TranslateMessage(&msg);DispatchMessageW(&msg);}return static_cast<int>(msg.wParam);
 }catch(hresult_error const& e){MessageBoxW(nullptr,e.message().c_str(),L"Host backdrop unavailable",MB_OK|MB_ICONERROR);return 1;}
}
