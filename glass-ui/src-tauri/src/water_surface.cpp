// Experimental Direct2D backing for a Tauri progress window. Installed only
// when explicitly enabled in a development process; no screen pixels are read.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <commctrl.h>
#include <d2d1.h>
#include <wrl/client.h>
#include <algorithm>
#include <new>
using Microsoft::WRL::ComPtr;
namespace {
constexpr UINT_PTR kSubclass = 0x4d484757;
struct Surface {
 ComPtr<ID2D1Factory> factory;
 ComPtr<ID2D1HwndRenderTarget> target;
 float r,g,b; bool light;
};
HRESULT render(HWND hwnd,Surface &s){
 RECT rc{};if(!GetClientRect(hwnd,&rc))return E_FAIL;
 const UINT width=static_cast<UINT>(std::max(1L,rc.right-rc.left));
 const UINT height=static_cast<UINT>(std::max(1L,rc.bottom-rc.top));
 if(!s.target){HRESULT hr=s.factory->CreateHwndRenderTarget(D2D1::RenderTargetProperties(),D2D1::HwndRenderTargetProperties(hwnd,D2D1::SizeU(width,height)),&s.target);if(FAILED(hr))return hr;}
 float w=static_cast<float>(width),h=static_cast<float>(height),x=7,y=7,r=w-7,b=h-7;
 ComPtr<ID2D1PathGeometry> path;HRESULT hr=s.factory->CreatePathGeometry(&path);if(FAILED(hr))return hr;
 ComPtr<ID2D1GeometrySink> sink;hr=path->Open(&sink);if(FAILED(hr))return hr;
 const float inset=std::min(38.f,w*.08f);
 sink->BeginFigure({x+inset,y+8},D2D1_FIGURE_BEGIN_FILLED);
 sink->AddBezier({{w*.30f,y-4},{w*.40f,y+14},{w*.52f,y+5}});
 sink->AddBezier({{w*.70f,y-6},{w*.80f,y+10},{r-inset,y+5}});
 sink->AddBezier({{r,y+3},{r+2,y+inset},{r-1,h*.38f}});
 sink->AddBezier({{r-7,h*.54f},{r+4,h*.68f},{r-2,b-inset}});
 sink->AddBezier({{r-4,b},{r-inset,b+2},{w*.70f,b-2}});
 sink->AddBezier({{w*.49f,b+6},{w*.28f,b-5},{x+inset,b-1}});
 sink->AddBezier({{x,b-3},{x,b-inset},{x+2,h*.65f}});
 sink->AddBezier({{x+7,h*.51f},{x,h*.30f},{x+2,y+inset}});
 sink->AddBezier({{x+5,y+18},{x+18,y+8},{x+inset,y+8}});
 sink->EndFigure(D2D1_FIGURE_END_CLOSED);hr=sink->Close();if(FAILED(hr))return hr;
 D2D1_GRADIENT_STOP stops[3]={{0,s.light?D2D1::ColorF(.84f,.94f,1.f):D2D1::ColorF(.08f,.22f,.34f)},
  {.5f,s.light?D2D1::ColorF(.62f+s.r*.15f,.70f+s.g*.15f,.76f+s.b*.15f):D2D1::ColorF(.02f+s.r*.18f,.04f+s.g*.18f,.08f+s.b*.18f)},
  {1,s.light?D2D1::ColorF(.72f,.84f,.92f):D2D1::ColorF(.01f,.035f,.065f)}};
 ComPtr<ID2D1GradientStopCollection> collection;hr=s.target->CreateGradientStopCollection(stops,3,&collection);if(FAILED(hr))return hr;
 ComPtr<ID2D1LinearGradientBrush> gradient;hr=s.target->CreateLinearGradientBrush(D2D1::LinearGradientBrushProperties({0,0},{w,h}),collection.Get(),&gradient);if(FAILED(hr))return hr;
 ComPtr<ID2D1SolidColorBrush> brush;hr=s.target->CreateSolidColorBrush(D2D1::ColorF(s.r,s.g,s.b,.45f),&brush);if(FAILED(hr))return hr;
 s.target->BeginDraw();s.target->Clear(s.light?D2D1::ColorF(.88f,.94f,.98f):D2D1::ColorF(.015f,.04f,.065f));
 s.target->FillGeometry(path.Get(),gradient.Get());s.target->DrawGeometry(path.Get(),brush.Get(),5.f);
 brush->SetColor(D2D1::ColorF(.8f,.96f,1.f,.75f));s.target->DrawGeometry(path.Get(),brush.Get(),1.25f);
 brush->SetColor(D2D1::ColorF(.8f,.96f,1.f,.13f));s.target->FillEllipse(D2D1::Ellipse({w*.5f,22.f},w*.3f,17.f),brush.Get());
 hr=s.target->EndDraw();if(hr==D2DERR_RECREATE_TARGET)s.target.Reset();return hr;
}
LRESULT CALLBACK surface_proc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp,UINT_PTR id,DWORD_PTR data){
 auto *s=reinterpret_cast<Surface*>(data);
 if(msg==WM_PAINT){PAINTSTRUCT ps{};BeginPaint(hwnd,&ps);render(hwnd,*s);EndPaint(hwnd,&ps);return 0;}
 if(msg==WM_ERASEBKGND)return 1;
 if(msg==WM_SIZE){if(s->target)s->target.Reset();InvalidateRect(hwnd,nullptr,FALSE);}
 if(msg==WM_NCDESTROY){RemoveWindowSubclass(hwnd,surface_proc,id);delete s;}
 return DefSubclassProc(hwnd,msg,wp,lp);
}
}
extern "C" int mhg_water_surface(HWND hwnd,unsigned rgb,int light){
 if(!IsWindow(hwnd))return 0;
 DWORD_PTR data=0;Surface *s=nullptr;
 if(GetWindowSubclass(hwnd,surface_proc,kSubclass,&data))s=reinterpret_cast<Surface*>(data);
 else{
  s=new(std::nothrow) Surface{};if(!s)return 0;
  if(FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,s->factory.GetAddressOf()))){delete s;return 0;}
  if(!SetWindowSubclass(hwnd,surface_proc,kSubclass,reinterpret_cast<DWORD_PTR>(s))){delete s;return 0;}
 }
 s->r=((rgb>>16)&255)/255.f;s->g=((rgb>>8)&255)/255.f;s->b=(rgb&255)/255.f;s->light=light!=0;
 if(FAILED(render(hwnd,*s))){RemoveWindowSubclass(hwnd,surface_proc,kSubclass);delete s;return 0;}
 InvalidateRect(hwnd,nullptr,FALSE);return 1;
}
