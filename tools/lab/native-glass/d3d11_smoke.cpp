// Windows x64 smoke test: create the same Direct3D renderer used by the
// experimental progress window. The outline is tested separately in Tauri.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <dxgi1_2.h>
#include <cstdio>
extern "C" int mhg_d3d11_water_surface(HWND,unsigned,int,unsigned,unsigned);
extern "C" void mhg_d3d11_water_remove(HWND);
extern "C" int mhg_water_clip(HWND){return 1;}
// This smoke test exercises opaque Direct3D independently of WinRT composition.
extern "C" void* mhg_water_composition_create(HWND,IDXGISwapChain1*,unsigned,unsigned){return nullptr;}
extern "C" int mhg_water_composition_resize(void*,unsigned,unsigned){return 0;}
extern "C" void mhg_water_composition_destroy(void*){}
LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){return DefWindowProcW(h,m,w,l);}
int main(){
 HINSTANCE instance=GetModuleHandleW(nullptr);WNDCLASSW cls{};cls.hInstance=instance;cls.lpfnWndProc=proc;cls.lpszClassName=L"MHGD3DSmoke";
 if(!RegisterClassW(&cls)){std::fprintf(stderr,"Cannot register test window\n");return 1;}
 HWND hwnd=CreateWindowExW(0,cls.lpszClassName,L"D3D smoke",WS_OVERLAPPEDWINDOW,0,0,320,240,nullptr,nullptr,instance,nullptr);
 if(!hwnd){std::fprintf(stderr,"Cannot create test window\n");return 2;}
 int ok=mhg_d3d11_water_surface(hwnd,0x35a9df,0,77,22);
 if(ok){SetWindowPos(hwnd,nullptr,0,0,480,320,SWP_NOMOVE|SWP_NOZORDER);UpdateWindow(hwnd);mhg_d3d11_water_remove(hwnd);}
 DestroyWindow(hwnd);
 if(!ok){std::fprintf(stderr,"Direct3D device, swap chain, or shader initialization failed\n");return 3;}
 std::puts("Direct3D device, swap chain and shaders initialized; visual quality requires desktop review");return 0;
}
