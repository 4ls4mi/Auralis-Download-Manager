// Isolated Windows x64 visual-hosting proof. No MDM engine or real downloads.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <windowsx.h>
#include <dwmapi.h>
#include <DispatcherQueue.h>
#include <windows.ui.composition.interop.h>
#include <windows.graphics.interop.h>
#include <d2d1.h>
#include <winrt/Windows.Graphics.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.UI.Composition.Desktop.h>
#include <wrl.h>
#include <WebView2.h>
#include <string>
#pragma comment(lib,"windowsapp.lib")
#pragma comment(lib,"CoreMessaging.lib")
#pragma comment(lib,"dwmapi.lib")
#pragma comment(lib,"d2d1.lib")
#pragma comment(lib,"user32.lib")
using namespace winrt;
using namespace winrt::Windows::UI::Composition;
using namespace winrt::Windows::UI::Composition::Desktop;
using Microsoft::WRL::ComPtr;
using Microsoft::WRL::Callback;
winrt::Windows::System::DispatcherQueueController queue{nullptr};
Compositor compositor{nullptr}; DesktopWindowTarget target{nullptr};
ContainerVisual root{nullptr},webVisual{nullptr}; SpriteVisual backdrop{nullptr};
ShapeVisual waterShape{nullptr}; CompositionSpriteShape bubble{nullptr};
winrt::com_ptr<ID2D1Factory> d2dFactory;
// CompositionPath consumes Direct2D geometry through this WinRT adapter.
struct GeometrySource : winrt::implements<GeometrySource, winrt::Windows::Graphics::IGeometrySource2D, ABI::Windows::Graphics::IGeometrySource2DInterop> {
 winrt::com_ptr<ID2D1Geometry> geometry;
 explicit GeometrySource(winrt::com_ptr<ID2D1Geometry> const& value):geometry(value){}
 IFACEMETHODIMP GetGeometry(ID2D1Geometry** value) override { geometry.copy_to(value); return S_OK; }
 IFACEMETHODIMP TryGetGeometryUsingFactory(ID2D1Factory*,ID2D1Geometry** value) override { *value=nullptr; return E_NOTIMPL; }
};
ComPtr<ICoreWebView2CompositionController> compositionController;
ComPtr<ICoreWebView2Controller> controller;
const wchar_t html[]=LR"HTML(<!doctype html><html><head><meta charset="utf-8"><style>
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;background:transparent;font:15px 'Segoe UI',sans-serif;color:#f4ffff}body{padding:18px}.glass{position:relative;height:100%;overflow:hidden;background:transparent}.content{position:relative;padding:22px 30px;height:100%;display:flex;flex-direction:column;gap:12px}h1{font-size:24px;margin:0}.note{font-size:12px;color:#c1e9ef}.panel{padding:15px 18px;border:1px solid #b0f6ffac;border-radius:35px 45px 30px 40px/40px 30px 45px 35px;background:linear-gradient(155deg,#48a8b967,#042b3dbb 46%,#0b718466);box-shadow:inset 0 4px 10px #d8ffff46,inset 0 -5px 12px #45dcf548,0 3px 10px #00192580}.details{display:grid;grid-template-columns:1fr 1fr;gap:6px 25px}.details .url{grid-column:1/-1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}strong{display:inline-block;min-width:110px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;flex:1;min-height:150px}.meter{height:30px;border-radius:50px;background:#a5f5ff32;border:1px solid #c8ffff90;overflow:hidden}.fill{height:100%;width:64%;border-radius:50px;background:linear-gradient(100deg,#006dff,#7955ff,#bc25ee);box-shadow:inset 0 5px 5px #d7ffff88,0 0 14px #48ceff}.blocks{display:grid;grid-template-columns:repeat(8,1fr);gap:4px;margin-top:12px}.block{height:24px;border-radius:8px;background:#367c8a80;border:1px solid #adffff68}.block:nth-child(-n+5){background:linear-gradient(120deg,#0786ff,#912bfa)}svg{height:70px;width:100%;margin-top:9px}button{padding:9px 23px;border:1px solid #a6feff;border-radius:25px;color:white;background:linear-gradient(#65d6e881,#04596dac);font:inherit;cursor:pointer}button:hover{background:#34b8d4;color:#001b2b}footer{display:flex;justify-content:flex-end;gap:12px}.status{margin-right:auto;color:#9df5ff}@media(max-width:640px){body{padding:8px}.content{padding:18px;gap:8px}.grid{grid-template-columns:1fr}.details{font-size:13px}.panel{padding:10px}}
</style></head><body><div class="glass"><div class="content"><header><h1>Water Bubble Glass</h1><div class="note">Composition-host prototype · sample data · not a download</div></header><section class="panel details"><div class="url"><strong>URL</strong> https://example.com/sample-download.zip</div><div><strong>Status</strong> Downloading</div><div><strong>File size</strong> 1.82 GB</div><div><strong>Downloaded</strong> 1.16 GB (64%)</div><div><strong>Transfer rate</strong> 42.7 MB/s</div><div><strong>Time left</strong> 16 sec</div><div><strong>Resume</strong> Yes</div><div><strong>Server</strong> Example</div></section><div class="grid"><section class="panel"><div class="meter"><div class="fill"></div></div><p>Transfer speed · sample</p><svg viewBox="0 0 300 70" preserveAspectRatio="none"><path d="M0 63 Q30 10 60 32 T120 27 T180 30 T240 25 T300 22 V70 H0Z" fill="#2da3ff55" stroke="#56efff" stroke-width="2"/></svg></section><section class="panel"><b>Connections (8)</b><div class="blocks"><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div></div><p>Sample connection visualization</p></section></div><footer><span class="status" id="status">Ready to test input</span><button onclick="document.getElementById('status').textContent='Pause clicked'">Pause</button><button onclick="document.getElementById('status').textContent='Cancel clicked'">Cancel</button></footer></div></div></body></html>)HTML";
void resize(HWND h){
 RECT r{};GetClientRect(h,&r);float w=float(r.right),v=float(r.bottom);
 if(root)root.Size({w,v});if(backdrop)backdrop.Size({w,v});if(waterShape)waterShape.Size({w,v});if(webVisual)webVisual.Size({w,v});if(controller)controller->put_Bounds(r);
 if(!root||!bubble||w<100||v<100)return;
 // The same actual Direct2D path drives the rendered material and the
 // Composition visual clip. No screen capture or overlapping HWND region.
 winrt::com_ptr<ID2D1PathGeometry> path;check_hresult(d2dFactory->CreatePathGeometry(path.put()));
 winrt::com_ptr<ID2D1GeometrySink> sink;check_hresult(path->Open(sink.put()));
 sink->BeginFigure({20,v*.18f},D2D1_FIGURE_BEGIN_FILLED);
 sink->AddBezier({{18,v*.05f},{w*.07f,5},{w*.18f,15}});
 sink->AddBezier({{w*.34f,25},{w*.37f,8},{w*.52f,12}});
 sink->AddBezier({{w*.70f,18},{w*.76f,3},{w*.88f,14}});
 sink->AddBezier({{w-15,20},{w-10,v*.09f},{w-17,v*.23f}});
 sink->AddBezier({{w-23,v*.38f},{w-9,v*.52f},{w-15,v*.70f}});
 sink->AddBezier({{w-10,v*.91f},{w-27,v-12},{w*.88f,v-15}});
 sink->AddBezier({{w*.72f,v-23},{w*.65f,v-5},{w*.50f,v-13}});
 sink->AddBezier({{w*.35f,v-20},{w*.27f,v-7},{w*.13f,v-15}});
 sink->AddBezier({{20,v-13},{12,v*.90f},{18,v*.72f}});
 sink->AddBezier({{24,v*.55f},{11,v*.40f},{20,v*.18f}});
 sink->EndFigure(D2D1_FIGURE_END_CLOSED);check_hresult(sink->Close());
 CompositionPath source(winrt::make<GeometrySource>(path.as<ID2D1Geometry>()));
 auto geometry=compositor.CreatePathGeometry(source);bubble.Geometry(geometry);
 root.Clip(compositor.CreateGeometricClip(geometry));
}
void fail(HWND h,const wchar_t* message){SetWindowTextW(h,message);}
void attach(HWND h){BOOL enable=TRUE;check_hresult(DwmSetWindowAttribute(h,DWMWA_USE_HOSTBACKDROPBRUSH,&enable,sizeof(enable)));auto interop=compositor.as<ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop>();check_hresult(interop->CreateDesktopWindowTarget(h,TRUE,reinterpret_cast<ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget**>(put_abi(target))));root=compositor.CreateContainerVisual();backdrop=compositor.CreateSpriteVisual();backdrop.Brush(compositor.CreateHostBackdropBrush());waterShape=compositor.CreateShapeVisual();bubble=compositor.CreateSpriteShape();
 auto fill=compositor.CreateLinearGradientBrush();fill.StartPoint({0,0});fill.EndPoint({1,1});
 fill.ColorStops().Append(compositor.CreateColorGradientStop(0.0f,{160,24,176,191}));
 fill.ColorStops().Append(compositor.CreateColorGradientStop(.45f,{215,0,37,55}));
 fill.ColorStops().Append(compositor.CreateColorGradientStop(1.0f,{170,0,118,144}));
 bubble.FillBrush(fill);bubble.StrokeBrush(compositor.CreateColorBrush({240,162,247,255}));bubble.StrokeThickness(4.0f);
 waterShape.Shapes().Append(bubble);webVisual=compositor.CreateContainerVisual();root.Children().InsertAtTop(backdrop);root.Children().InsertAtTop(waterShape);root.Children().InsertAtTop(webVisual);target.Root(root);resize(h);
 HRESULT hr=CreateCoreWebView2EnvironmentWithOptions(nullptr,nullptr,nullptr,Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([h](HRESULT result,ICoreWebView2Environment* env)->HRESULT{if(FAILED(result)||!env){fail(h,L"WebView2 environment failed");return result;}ComPtr<ICoreWebView2Environment3> env3;if(FAILED(env->QueryInterface(IID_PPV_ARGS(&env3)))){fail(h,L"WebView2 composition unavailable");return E_FAIL;}return env3->CreateCoreWebView2CompositionController(h,Callback<ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler>([h](HRESULT result,ICoreWebView2CompositionController* visual)->HRESULT{if(FAILED(result)||!visual){fail(h,L"WebView2 composition controller failed");return result;}compositionController=visual;compositionController.As(&controller);ComPtr<ICoreWebView2Controller2> c2;if(SUCCEEDED(controller.As(&c2))){COREWEBVIEW2_COLOR transparent{0,0,0,0};c2->put_DefaultBackgroundColor(transparent);}compositionController->put_RootVisualTarget(reinterpret_cast<IUnknown*>(get_abi(webVisual)));resize(h);ComPtr<ICoreWebView2> web;controller->get_CoreWebView2(&web);web->NavigateToString(html);controller->put_IsVisible(TRUE);SetWindowTextW(h,L"Water Bubble composition lab — sample data");return S_OK;}).Get());}).Get());if(FAILED(hr))fail(h,L"WebView2 startup failed");}
LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){switch(m){case WM_SIZE:resize(h);return 0;case WM_SETFOCUS:if(controller)controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);break;case WM_MOUSEMOVE:case WM_LBUTTONDOWN:case WM_LBUTTONUP:case WM_RBUTTONDOWN:case WM_RBUTTONUP:case WM_MOUSEWHEEL:if(compositionController){POINT p{GET_X_LPARAM(l),GET_Y_LPARAM(l)};if(m==WM_MOUSEWHEEL)ScreenToClient(h,&p);auto k=static_cast<COREWEBVIEW2_MOUSE_EVENT_KIND>(m);auto keys=static_cast<COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS>(GET_KEYSTATE_WPARAM(w));UINT data=m==WM_MOUSEWHEEL?GET_WHEEL_DELTA_WPARAM(w):0;if(m==WM_LBUTTONDOWN){SetFocus(h);SetCapture(h);}if(m==WM_LBUTTONUP)ReleaseCapture();compositionController->SendMouseInput(k,keys,data,p);return 0;}break;case WM_DESTROY:if(controller)controller->Close();compositionController.Reset();controller.Reset();target=nullptr;PostQuitMessage(0);return 0;}return DefWindowProcW(h,m,w,l);}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,LPWSTR,int show){try{init_apartment(apartment_type::single_threaded);DispatcherQueueOptions options{sizeof(DispatcherQueueOptions),DQTYPE_THREAD_CURRENT,DQTAT_COM_STA};check_hresult(CreateDispatcherQueueController(options,reinterpret_cast<ABI::Windows::System::IDispatcherQueueController**>(put_abi(queue))));compositor=Compositor();check_hresult(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,d2dFactory.put()));WNDCLASSW cls{};cls.hInstance=instance;cls.lpfnWndProc=proc;cls.lpszClassName=L"MHGCompositionWaterLab";cls.hCursor=LoadCursor(nullptr,IDC_ARROW);RegisterClassW(&cls);HWND h=CreateWindowExW(WS_EX_NOREDIRECTIONBITMAP,cls.lpszClassName,L"Starting composition lab",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,900,600,nullptr,nullptr,instance,nullptr);if(!h)return 2;attach(h);ShowWindow(h,show);MSG msg{};while(GetMessageW(&msg,nullptr,0,0)>0){TranslateMessage(&msg);DispatchMessageW(&msg);}return 0;}catch(hresult_error const&){return 3;}}
