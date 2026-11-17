// Standalone Windows x64 Direct2D material geometry experiment.
// This does not capture the desktop or replace any application window.
#define UNICODE
#define _UNICODE
#define NOMINMAX
#include <windows.h>
#include <d2d1.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <algorithm>
#include <cmath>
#include <cwchar>
#include <string>
#pragma comment(lib, "d2d1.lib")
#pragma comment(lib, "dwrite.lib")
#pragma comment(lib, "user32.lib")
using Microsoft::WRL::ComPtr;

namespace {
ComPtr<ID2D1Factory> factory;
ComPtr<IDWriteFactory> writeFactory;
ComPtr<IDWriteTextFormat> textFormat;
ComPtr<ID2D1HwndRenderTarget> target;
int style = 0;
bool light = false;
int accent = 0;
const wchar_t* labels[] = {L"Water Bubble", L"Ice Edge", L"Smoked Crystal", L"Frosted Layers", L"Aero Gloss", L"Prismatic Glass"};
const D2D1_COLOR_F accents[] = {{0.1f,0.75f,0.95f,1},{0.65f,0.30f,0.96f,1},{0.1f,0.85f,0.57f,1},{1,0.48f,0.18f,1}};

HRESULT geometry(float w, float h, int mode, ID2D1PathGeometry** result) {
 ComPtr<ID2D1PathGeometry> path; HRESULT hr=factory->CreatePathGeometry(&path); if(FAILED(hr))return hr;
 ComPtr<ID2D1GeometrySink> sink; hr=path->Open(&sink);if(FAILED(hr))return hr;
 float x=12,y=12,r=w-12,b=h-12;
 if(mode==0){
  sink->BeginFigure({x+48,y+9},D2D1_FIGURE_BEGIN_FILLED);
  sink->AddBezier({{w*.30f,y-9},{w*.40f,y+22},{w*.52f,y+5}});
  sink->AddBezier({{w*.70f,y-12},{w*.80f,y+12},{r-48,y+4}});
  sink->AddBezier({{r+5,y-2},{r+10,y+38},{r-1,h*.38f}});
  sink->AddBezier({{r-13,h*.54f},{r+15,h*.68f},{r-2,b-48}});
  sink->AddBezier({{r-7,b+3},{r-40,b+8},{w*.70f,b-2}});
  sink->AddBezier({{w*.49f,b+12},{w*.28f,b-9},{x+48,b-1}});
  sink->AddBezier({{x-3,b-4},{x-4,b-40},{x+2,h*.65f}});
  sink->AddBezier({{x+12,h*.51f},{x-5,h*.30f},{x+2,y+50}});
  sink->AddBezier({{x+6,y+21},{x+19,y+9},{x+48,y+9}});
 }else{
  float cut=mode==1||mode==5?32.0f:mode==2?18.0f:8.0f;
  sink->BeginFigure({x+cut,y},D2D1_FIGURE_BEGIN_FILLED);
  D2D1_POINT_2F pts[]={{r-cut,y},{r,y+cut},{r,b-cut},{r-cut,b},{x+cut,b},{x,b-cut},{x,y+cut}};
  sink->AddLines(pts,7);
 }
 sink->EndFigure(D2D1_FIGURE_END_CLOSED);hr=sink->Close();if(FAILED(hr))return hr;*result=path.Detach();return S_OK;
}
HRESULT initialize(){
 HRESULT hr=D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,factory.GetAddressOf());if(FAILED(hr))return hr;
 hr=DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,__uuidof(IDWriteFactory),reinterpret_cast<IUnknown**>(writeFactory.GetAddressOf()));if(FAILED(hr))return hr;
 return writeFactory->CreateTextFormat(L"Segoe UI",nullptr,DWRITE_FONT_WEIGHT_SEMI_BOLD,DWRITE_FONT_STYLE_NORMAL,DWRITE_FONT_STRETCH_NORMAL,24,L"en-us",&textFormat);
}
HRESULT ensureTarget(HWND hwnd){
 if(target)return S_OK;RECT rc{};GetClientRect(hwnd,&rc);
 return factory->CreateHwndRenderTarget(D2D1::RenderTargetProperties(),D2D1::HwndRenderTargetProperties(hwnd,D2D1::SizeU(std::max(1L,rc.right),std::max(1L,rc.bottom))),&target);
}
void paint(HWND hwnd){
 PAINTSTRUCT ps{};BeginPaint(hwnd,&ps);if(FAILED(ensureTarget(hwnd))){EndPaint(hwnd,&ps);return;}
 auto size=target->GetSize();float w=size.width,h=size.height;
 ComPtr<ID2D1PathGeometry> path;if(FAILED(geometry(w,h,style,&path))){EndPaint(hwnd,&ps);return;}
 ComPtr<ID2D1SolidColorBrush> brush;target->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::White),&brush);
 if(!brush){EndPaint(hwnd,&ps);return;}
 const auto ac=accents[accent];D2D1_GRADIENT_STOP stops[3];
 stops[0]={0,light?D2D1::ColorF(.87f,.94f,1.f):D2D1::ColorF(.10f,.24f,.43f)};
 stops[1]={.55f,light?D2D1::ColorF(.55f+ac.r*.18f,.65f+ac.g*.18f,.73f+ac.b*.18f):D2D1::ColorF(ac.r*.20f+.015f,ac.g*.20f+.025f,ac.b*.20f+.07f)};
 stops[2]={1,light?D2D1::ColorF(.70f,.81f,.90f):D2D1::ColorF(.015f,.035f,.09f)};
 ComPtr<ID2D1GradientStopCollection> collection;target->CreateGradientStopCollection(stops,3,&collection);
 ComPtr<ID2D1LinearGradientBrush> grad;if(collection)target->CreateLinearGradientBrush(D2D1::LinearGradientBrushProperties({0,0},{w,h}),collection.Get(),&grad);
 target->BeginDraw();target->Clear(D2D1::ColorF(.035f,.05f,.09f));
 if(grad)target->FillGeometry(path.Get(),grad.Get());
 brush->SetColor(D2D1::ColorF(ac.r,ac.g,ac.b,.32f));target->DrawGeometry(path.Get(),brush.Get(),7.f);
 brush->SetColor(D2D1::ColorF(.85f,.97f,1.f,.85f));target->DrawGeometry(path.Get(),brush.Get(),1.5f);
 if(style==1||style==5){
  brush->SetColor(D2D1::ColorF(.75f,.91f,1.f,.28f));
  for(int n=0;n<5;n++){float px=w*(.16f+n*.17f);target->DrawLine({px,15},{px+60,h*.27f},brush.Get(),1.f);target->DrawLine({px+60,h*.27f},{px+130,15},brush.Get(),1.f);}
 }
 if(style==3){brush->SetColor(D2D1::ColorF(1.f,1.f,1.f,.12f));target->FillRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(34,55,w-34,h-34),24,24),brush.Get());}
 if(style==4||style==0){brush->SetColor(D2D1::ColorF(.82f,.96f,1.f,.17f));target->FillEllipse(D2D1::Ellipse({w*.52f,30},w*.34f,24),brush.Get());}
 brush->SetColor(light?D2D1::ColorF(.03f,.10f,.19f):D2D1::ColorF(.92f,.97f,1.f));
 std::wstring title=labels[style];target->DrawTextW(title.c_str(),(UINT32)title.size(),textFormat.Get(),D2D1::RectF(44,62,w-35,105),brush.Get());
 const wchar_t* note=L"Direct2D native geometry lab  |  1–6: material  |  L: light/dark  |  C: accent";
 target->DrawTextW(note,(UINT32)wcslen(note),textFormat.Get(),D2D1::RectF(44,h-85,w-35,h-28),brush.Get());
 HRESULT hr=target->EndDraw();if(hr==D2DERR_RECREATE_TARGET)target.Reset();EndPaint(hwnd,&ps);
}
LRESULT CALLBACK windowProc(HWND hwnd,UINT msg,WPARAM w,LPARAM l){
 switch(msg){case WM_PAINT:paint(hwnd);return 0;case WM_SIZE:if(target)target->Resize(D2D1::SizeU(std::max(1U,(UINT)LOWORD(l)),std::max(1U,(UINT)HIWORD(l))));InvalidateRect(hwnd,nullptr,FALSE);return 0;
 case WM_KEYDOWN:if(w>='1'&&w<='6')style=(int)(w-'1');else if(w=='L')light=!light;else if(w=='C')accent=(accent+1)%4;InvalidateRect(hwnd,nullptr,FALSE);return 0;
 case WM_DESTROY:PostQuitMessage(0);return 0;}return DefWindowProcW(hwnd,msg,w,l);
}
}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,LPWSTR command,int show){
 if(FAILED(initialize()))return 1;
 if(std::wstring(command)==L"--self-test") {ComPtr<ID2D1PathGeometry> p;for(int i=0;i<6;i++){p.Reset();if(FAILED(geometry(800,480,i,&p)))return 2;}return 0;}
 WNDCLASSW wc{};wc.hInstance=instance;wc.lpfnWndProc=windowProc;wc.lpszClassName=L"MHGNativeGlassLab";wc.hCursor=LoadCursor(nullptr,IDC_ARROW);if(!RegisterClassW(&wc))return 3;
 HWND hwnd=CreateWindowExW(0,wc.lpszClassName,L"Mister Hybrid Glass - Direct2D lab",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,900,540,nullptr,nullptr,instance,nullptr);if(!hwnd)return 4;
 ShowWindow(hwnd,show);MSG msg{};while(GetMessageW(&msg,nullptr,0,0)>0){TranslateMessage(&msg);DispatchMessageW(&msg);}return (int)msg.wParam;
}
