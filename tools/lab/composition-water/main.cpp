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
#include <cstring>
#include <cwchar>
#include <iostream>
#include <thread>
#include <memory>
#include "material.h"
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
ContainerVisual root{nullptr},webVisual{nullptr}; SpriteVisual backdrop{nullptr},materialVisual{nullptr};
ICompositionSurface materialSurface{nullptr}; LabMaterial material; int materialStyle=0; bool liveMode=false;
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
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;background:transparent;font:15px 'Segoe UI',sans-serif;color:#f4ffff}body{padding:18px}.glass{position:relative;height:100%;overflow:hidden;background:transparent}.content{position:relative;padding:22px 30px;height:100%;min-height:0;display:flex;flex-direction:column;gap:12px}header{flex-shrink:0;display:flex;align-items:flex-start;justify-content:space-between;gap:10px}h1{font-size:24px;margin:0}.window-controls{display:flex;gap:7px}.window-controls button{padding:0;width:34px;height:30px;border-radius:11px;line-height:1;color:#c4ffff;font-size:18px}.window-controls .min:hover{background:#fbad38;color:#221400}.window-controls .max:hover{background:#ad7aff;color:#fff}.window-controls .close:hover{background:#ff5269;color:#fff}.note{font-size:12px;color:#c1e9ef}.panel{padding:15px 18px;border:1px solid #b0f6ffac;border-radius:35px 45px 30px 40px/40px 30px 45px 35px;background:transparent;box-shadow:none;border-color:transparent}.details{flex-shrink:0;display:grid;grid-template-columns:1fr 1fr;gap:6px 25px}.details .url{grid-column:1/-1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}strong{display:inline-block;min-width:110px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:12px;flex:1;min-height:0}.grid>.panel{min-height:0;overflow:hidden}.grid p{margin:8px 0}.meter{height:30px;border-radius:50px;background:#a5f5ff32;border:1px solid #c8ffff90;overflow:hidden}.fill{height:100%;width:64%;border-radius:50px;background:linear-gradient(100deg,#006dff,#7955ff,#bc25ee);box-shadow:inset 0 5px 5px #d7ffff88,0 0 14px #48ceff}.blocks{display:grid;grid-template-columns:repeat(8,1fr);gap:4px;margin-top:12px}.block{height:24px;border-radius:8px;background:#367c8a80;border:1px solid #adffff68}.block:nth-child(-n+5){background:linear-gradient(120deg,#0786ff,#912bfa)}svg{display:block;height:clamp(35px,10vh,70px);width:100%;margin-top:9px}button{padding:9px 23px;border:1px solid #a6feff;border-radius:25px;color:white;background:linear-gradient(#65d6e881,#04596dac);font:inherit;cursor:pointer}button:hover{background:#34b8d4;color:#001b2b}footer{display:flex;flex-shrink:0;justify-content:flex-end;gap:12px}.status{margin-right:auto;color:#9df5ff}@media(max-width:640px){body{padding:8px}.content{padding:18px;gap:8px}.grid{grid-template-columns:1fr}.details{font-size:13px}.panel{padding:10px}}
.ice{color:#061d37}.ice .note,.ice .status{color:#164563}.ice .window-controls button,.ice button{color:#0b304a}.ice .window-controls button:hover{color:white}.ice .meter{background:#c5e8f5a0;border-color:#4c90b4}.ice .block{background:#77a6c080}.ice .block:nth-child(-n+5){background:linear-gradient(120deg,#0786ff,#912bfa)}.ice .details,.ice .grid>.panel{text-shadow:0 1px 0 #ffffff66}.ice svg path{stroke:#245fca}.smoked .note,.smoked .status{color:#bed0f3}
</style></head><body><div class="glass"><div class="content"><header><div><h1>Water Bubble Glass</h1><div class="note">Composition-host prototype · sample data · not a download</div></div><div class="window-controls"><button class="min" title="Minimize" onclick="chrome.webview.postMessage('minimize')">−</button><button class="max" title="Maximize or restore" onclick="chrome.webview.postMessage('maximize')">□</button><button class="close" title="Close" onclick="chrome.webview.postMessage('close')">×</button></div></header><section class="panel details"><div class="url" data-field="url"><strong>URL</strong> https://example.com/sample-download.zip</div><div data-field="Status"><strong>Status</strong> Downloading</div><div data-field="File size"><strong>File size</strong> 1.82 GB</div><div data-field="Downloaded"><strong>Downloaded</strong> 1.16 GB (64%)</div><div data-field="Transfer rate"><strong>Transfer rate</strong> 42.7 MB/s</div><div data-field="Time left"><strong>Time left</strong> 16 sec</div><div data-field="Resume"><strong>Resume</strong> Yes</div><div data-field="Server"><strong>Server</strong> Example</div></section><div class="grid"><section class="panel"><div class="meter"><div class="fill"></div></div><span id="overall-label">64%</span><p>Transfer speed · sample</p><svg viewBox="0 0 300 70" preserveAspectRatio="none"><path d="M0 63 Q30 10 60 32 T120 27 T180 30 T240 25 T300 22 V70 H0Z" fill="#2da3ff55" stroke="#56efff" stroke-width="2"/></svg></section><section class="panel"><b id="connection-title">Connections (8)</b><div class="blocks"><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div><div class="block"></div></div><p>Sample connection visualization</p></section></div><footer><span class="status" id="status">Ready to test input</span><button onclick="document.getElementById('status').textContent='Pause clicked';chrome.webview.postMessage('pause')">Pause</button><button onclick="document.getElementById('status').textContent='Cancel clicked'">Cancel</button></footer></div></div><script>
 function reportPanels(){const nodes=[document.querySelector('.details'),...document.querySelectorAll('.grid>.panel')];if(nodes.length!==3)return;const d=window.devicePixelRatio||1;const vals=nodes.flatMap(n=>{const r=n.getBoundingClientRect();return [r.x*d,r.y*d,r.width*d,r.height*d]});chrome.webview.postMessage('panels:'+vals.join(','));}
 const samples=[];
 const units=n=>n==null?'Unknown':n>=1073741824?(n/1073741824).toFixed(2)+' GB':n>=1048576?(n/1048576).toFixed(1)+' MB':n>=1024?(n/1024).toFixed(1)+' KB':n+' B';
 function field(name,value){const el=document.querySelector('[data-field="'+name+'"]');if(!el)return;const label=el.querySelector('strong');el.replaceChildren(label,document.createTextNode(' '+value));}
 window.applyLive=msg=>{if(!msg||!msg.download)return;const d=msg.download,v=msg.visual||{};field('url',d.url||'Unavailable');field('Status',d.status||'Unknown');field('File size',units(d.size));const pct=d.size>0?Math.min(100,Math.max(0,100*d.downloaded/d.size)):null;field('Downloaded',units(d.downloaded)+(pct==null?'':' ('+pct.toFixed(2)+'%)'));field('Transfer rate',units(d.speed)+'/s');const seconds=d.speed>0&&d.size?Math.max(0,Math.round((d.size-d.downloaded)/d.speed)):null;field('Time left',seconds==null?'Unknown':seconds+' s');field('Resume',v.resumable===true?'Yes':v.resumable===false?'No':'Unknown');const server=v.server||{};field('Server',(server.place?.name||server.hostname||'Unknown')+(server.rtt_ms!=null?' · about '+server.rtt_ms+' ms':''));document.querySelector('.fill').style.width=(pct??0)+'%';document.getElementById('overall-label').textContent=pct==null?'Unknown':pct.toFixed(1)+'%';
 const connections=(v.connections||[]).filter(c=>c.state!=='Retired'&&c.state!=='Failed'&&!(c.state==='Finished'&&c.downloaded===0)).sort((a,b)=>a.id-b.id);const blocks=document.querySelector('.blocks');blocks.replaceChildren();document.getElementById('connection-title').textContent='Connections ('+connections.length+')';for(const c of connections){const ranges=(v.segments||[]).filter(r=>(r.worker===c.id||(r.worker==null&&r.last_worker===c.id))&&r.end>r.start&&r.cursor>=r.start&&r.cursor<=r.end);let total=0,received=0;for(const r of ranges){total+=r.end-r.start;received+=r.cursor-r.start}const block=document.createElement('div');block.className='block';const progress=total?Math.max(0,Math.min(100,100*received/total)):0;block.style.background=total?'linear-gradient(90deg,#087cff,#932cff '+progress+'%,#294a58 '+progress+'%)':'#294a58';block.title='Connection '+c.id+' · '+c.state+' · '+units(c.downloaded)+(total?' · '+progress.toFixed(1)+'%':' · range unknown');blocks.appendChild(block)}
 samples.push(d.speed||0);if(samples.length>40)samples.shift();const max=Math.max(1,...samples),pts=samples.map((n,i)=>(samples.length===1?0:i*300/(samples.length-1))+','+(68-60*n/max));document.querySelector('svg path').setAttribute('d','M '+pts.join(' L ')+' L 300,70 L 0,70 Z');document.querySelector('.grid p').textContent='Transfer speed · '+units(d.speed)+'/s';chrome.webview.postMessage('live-applied:'+JSON.stringify({percent:document.getElementById('overall-label').textContent,status:d.status,workers:connections.length,actionsDisabled:[...document.querySelectorAll('footer button')].every(b=>b.disabled)}));};
 window.addEventListener('load',()=>{if(window.liveMode){document.querySelector('.note').textContent='Live engine telemetry · experimental host';document.querySelectorAll('footer button').forEach(b=>{b.disabled=true;b.title='Transfer actions are not connected in this experiment'});document.querySelector('.blocks').replaceChildren();document.querySelector('.fill').style.width='0';document.getElementById('overall-label').textContent='Waiting…';for(const name of ['url','Status','File size','Downloaded','Transfer rate','Time left','Resume','Server'])field(name,'Waiting…');}const o=new ResizeObserver(reportPanels);document.querySelectorAll('.details,.grid>.panel').forEach(n=>o.observe(n));reportPanels()});window.addEventListener('resize',reportPanels);
 </script></body></html>)HTML";
void resize(HWND h){
 RECT r{};GetClientRect(h,&r);float w=float(r.right),v=float(r.bottom);
 if(root)root.Size({w,v});if(backdrop)backdrop.Size({w,v});if(materialVisual)materialVisual.Size({w,v});if(material.swap && w>0 && v>0 && FAILED(material.draw(unsigned(w),unsigned(v))))SetWindowTextW(h,L"D3D material render failed");if(waterShape)waterShape.Size({w,v});if(webVisual)webVisual.Size({w,v});if(controller)controller->put_Bounds(r);
 if(!root||!bubble||w<100||v<100)return;
 // The same actual Direct2D path drives the rendered material and the
 // Composition visual clip. No screen capture or overlapping HWND region.
 winrt::com_ptr<ID2D1PathGeometry> path;check_hresult(d2dFactory->CreatePathGeometry(path.put()));
 winrt::com_ptr<ID2D1GeometrySink> sink;check_hresult(path->Open(sink.put()));
 if(materialStyle==0 || materialStyle==3 || materialStyle==4){
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
 }else if(materialStyle==1 || materialStyle==5){
 sink->BeginFigure({42,8},D2D1_FIGURE_BEGIN_FILLED);
 sink->AddLine({w-50,8});sink->AddLine({w-12,45});sink->AddLine({w-12,v-48});
 sink->AddLine({w-48,v-10});sink->AddLine({46,v-10});sink->AddLine({12,v-45});sink->AddLine({12,46});
 }else{
 sink->BeginFigure({34,12},D2D1_FIGURE_BEGIN_FILLED);
 sink->AddLine({w-32,12});sink->AddLine({w-12,34});sink->AddLine({w-12,v-35});
 sink->AddLine({w-34,v-12});sink->AddLine({35,v-12});sink->AddLine({12,v-35});sink->AddLine({12,35});
 }
 sink->EndFigure(D2D1_FIGURE_END_CLOSED);check_hresult(sink->Close());
 CompositionPath source(winrt::make<GeometrySource>(path.as<ID2D1Geometry>()));
 auto geometry=compositor.CreatePathGeometry(source);bubble.Geometry(geometry);
 root.Clip(compositor.CreateGeometricClip(geometry));

}
void fail(HWND h,const wchar_t* message){SetWindowTextW(h,message);}
void attach(HWND h){BOOL enable=TRUE;check_hresult(DwmSetWindowAttribute(h,DWMWA_USE_HOSTBACKDROPBRUSH,&enable,sizeof(enable)));auto interop=compositor.as<ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop>();check_hresult(interop->CreateDesktopWindowTarget(h,TRUE,reinterpret_cast<ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget**>(put_abi(target))));root=compositor.CreateContainerVisual();backdrop=compositor.CreateSpriteVisual();backdrop.Brush(compositor.CreateHostBackdropBrush());material.materialStyle=materialStyle;check_hresult(material.init());auto ci=compositor.as<ABI::Windows::UI::Composition::ICompositorInterop>();
 check_hresult(ci->CreateCompositionSurfaceForSwapChain(material.swap.Get(),reinterpret_cast<ABI::Windows::UI::Composition::ICompositionSurface**>(put_abi(materialSurface))));
 materialVisual=compositor.CreateSpriteVisual();materialVisual.Brush(compositor.CreateSurfaceBrush(materialSurface));waterShape=compositor.CreateShapeVisual();bubble=compositor.CreateSpriteShape();
 bubble.StrokeBrush(compositor.CreateColorBrush({240,162,247,255}));bubble.StrokeThickness(4.0f);
 waterShape.Shapes().Append(bubble);webVisual=compositor.CreateContainerVisual();root.Children().InsertAtTop(backdrop);root.Children().InsertAtTop(materialVisual);root.Children().InsertAtTop(waterShape);root.Children().InsertAtTop(webVisual);target.Root(root);resize(h);
 HRESULT hr=CreateCoreWebView2EnvironmentWithOptions(nullptr,nullptr,nullptr,Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>([h](HRESULT result,ICoreWebView2Environment* env)->HRESULT{if(FAILED(result)||!env){fail(h,L"WebView2 environment failed");return result;}ComPtr<ICoreWebView2Environment3> env3;if(FAILED(env->QueryInterface(IID_PPV_ARGS(&env3)))){fail(h,L"WebView2 composition unavailable");return E_FAIL;}return env3->CreateCoreWebView2CompositionController(h,Callback<ICoreWebView2CreateCoreWebView2CompositionControllerCompletedHandler>([h](HRESULT result,ICoreWebView2CompositionController* visual)->HRESULT{if(FAILED(result)||!visual){fail(h,L"WebView2 composition controller failed");return result;}compositionController=visual;compositionController.As(&controller);ComPtr<ICoreWebView2Controller2> c2;if(SUCCEEDED(controller.As(&c2))){COREWEBVIEW2_COLOR transparent{0,0,0,0};c2->put_DefaultBackgroundColor(transparent);}compositionController->put_RootVisualTarget(reinterpret_cast<IUnknown*>(get_abi(webVisual)));resize(h);ComPtr<ICoreWebView2> web;controller->get_CoreWebView2(&web);EventRegistrationToken token{};
 web->add_WebMessageReceived(Callback<ICoreWebView2WebMessageReceivedEventHandler>([h](ICoreWebView2*,ICoreWebView2WebMessageReceivedEventArgs* args)->HRESULT{
  LPWSTR value=nullptr;if(FAILED(args->TryGetWebMessageAsString(&value))||!value)return S_OK;
  std::wstring action(value);CoTaskMemFree(value);
  if(action.rfind(L"live-applied:",0)==0){SetWindowTextW(h,(L"MDM-LAB-VERIFY:"+action.substr(13)).c_str());return S_OK;}
  if(action.rfind(L"panels:",0)==0){float p[12]{};int count=std::swscanf(action.c_str()+7,L"%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f,%f",&p[0],&p[1],&p[2],&p[3],&p[4],&p[5],&p[6],&p[7],&p[8],&p[9],&p[10],&p[11]);
   if(count==12){for(int i=0;i<12;i++)material.panelRects[i]=p[i];if(material.width&&material.height)material.draw(material.width,material.height);}return S_OK;}
  if(action==L"pause")SetWindowTextW(h,L"Water Bubble composition lab - Pause input OK");
  else if(action==L"ice-style-ok")SetWindowTextW(h,L"Water Bubble composition lab - Ice style OK");
  else if(action==L"ice-style-bad")SetWindowTextW(h,L"Water Bubble composition lab - Ice style BAD");
  else if(action==L"layout-ok")SetWindowTextW(h,L"Water Bubble composition lab - Layout OK");
  else if(action==L"layout-bad")SetWindowTextW(h,L"Water Bubble composition lab - Layout OVERLAP");
  else if(action==L"minimize")ShowWindow(h,SW_MINIMIZE);
  else if(action==L"maximize")ShowWindow(h,IsZoomed(h)?SW_RESTORE:SW_MAXIMIZE);
  else if(action==L"close")PostMessageW(h,WM_CLOSE,0,0);
  return S_OK;}).Get(),&token);std::wstring page(html);if(materialStyle){auto pos=page.find(L"<body>");bool light=materialStyle==1||materialStyle==3||materialStyle==5;if(pos!=std::wstring::npos)page.replace(pos,6,light?L"<body class=\"ice\">":L"<body class=\"smoked\">");auto name=page.find(L"Water Bubble Glass");const wchar_t* labels[]={L"Water Bubble Glass",L"Ice Edge Glass",L"Smoked Crystal",L"Frosted Layers",L"Aero Gloss",L"Prismatic Glass"};if(name!=std::wstring::npos)page.replace(name,18,labels[materialStyle]);}if(liveMode){auto pos=page.find(L"<script>");if(pos!=std::wstring::npos)page.insert(pos,L"<script>window.liveMode=true;</script>");}web->NavigateToString(page.c_str());controller->put_IsVisible(TRUE);SetWindowTextW(h,L"Water Bubble composition lab — sample data");return S_OK;}).Get());}).Get());if(FAILED(hr))fail(h,L"WebView2 startup failed");}
LRESULT CALLBACK proc(HWND h,UINT m,WPARAM w,LPARAM l){switch(m){case WM_APP+3:{std::unique_ptr<std::string> payload(reinterpret_cast<std::string*>(l));if(controller&&payload){int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,payload->data(),int(payload->size()),nullptr,0);if(n>0){std::wstring wide(n,L'\0');MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,payload->data(),int(payload->size()),wide.data(),n);ComPtr<ICoreWebView2> web;controller->get_CoreWebView2(&web);if(web){std::wstring js=L"window.applyLive("+wide+L")";web->ExecuteScript(js.c_str(),nullptr);}}}return 0;}
 case WM_APP+2:{if(controller){ComPtr<ICoreWebView2> web;controller->get_CoreWebView2(&web);if(web)web->ExecuteScript(L"(()=>{const e=document.querySelector('.block');const ok=document.body.classList.contains('ice')&&e&&getComputedStyle(e).backgroundImage.includes('gradient');chrome.webview.postMessage(ok?'ice-style-ok':'ice-style-bad')})()",nullptr);}return 0;}
 case WM_APP+1:{if(material.panelRects[2]<=1||material.panelRects[6]<=1||material.panelRects[10]<=1){SetWindowTextW(h,L"Water Bubble composition lab - GPU panels missing");return 0;}if(controller){ComPtr<ICoreWebView2> web;controller->get_CoreWebView2(&web);if(web)web->ExecuteScript(L"(()=>{const f=document.querySelector('footer').getBoundingClientRect();const panels=[...document.querySelectorAll('.grid>.panel')];chrome.webview.postMessage(panels.every(p=>p.getBoundingClientRect().bottom<=f.top+1)?'layout-ok':'layout-bad')})()",nullptr);}return 0;}
 case WM_NCCALCSIZE:if(w)return 0;break;
 case WM_NCHITTEST:{POINT p{GET_X_LPARAM(l),GET_Y_LPARAM(l)};ScreenToClient(h,&p);RECT r{};GetClientRect(h,&r);const int edge=12;
  if(!IsZoomed(h)){bool left=p.x<edge,right=p.x>=r.right-edge,top=p.y<edge,bottom=p.y>=r.bottom-edge;
   if(top&&left)return HTTOPLEFT;if(top&&right)return HTTOPRIGHT;if(bottom&&left)return HTBOTTOMLEFT;if(bottom&&right)return HTBOTTOMRIGHT;
   if(left)return HTLEFT;if(right)return HTRIGHT;if(top)return HTTOP;if(bottom)return HTBOTTOM;}
  if(p.y>=20&&p.y<68&&p.x<r.right-185&&p.x>38)return HTCAPTION;return HTCLIENT;}
 case WM_SIZE:resize(h);return 0;case WM_SETFOCUS:if(controller)controller->MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC);break;case WM_MOUSEMOVE:case WM_LBUTTONDOWN:case WM_LBUTTONUP:case WM_RBUTTONDOWN:case WM_RBUTTONUP:case WM_MOUSEWHEEL:if(compositionController){POINT p{GET_X_LPARAM(l),GET_Y_LPARAM(l)};if(m==WM_MOUSEWHEEL)ScreenToClient(h,&p);auto k=static_cast<COREWEBVIEW2_MOUSE_EVENT_KIND>(m);auto keys=static_cast<COREWEBVIEW2_MOUSE_EVENT_VIRTUAL_KEYS>(GET_KEYSTATE_WPARAM(w));UINT data=m==WM_MOUSEWHEEL?GET_WHEEL_DELTA_WPARAM(w):0;if(m==WM_LBUTTONDOWN){SetFocus(h);SetCapture(h);}if(m==WM_LBUTTONUP)ReleaseCapture();compositionController->SendMouseInput(k,keys,data,p);return 0;}break;case WM_DESTROY:if(controller)controller->Close();compositionController.Reset();controller.Reset();target=nullptr;PostQuitMessage(0);return 0;}return DefWindowProcW(h,m,w,l);}
int WINAPI wWinMain(HINSTANCE instance,HINSTANCE,LPWSTR command,int show){try{std::wstring args(command);liveMode=args.find(L"--live")!=std::wstring::npos;materialStyle=args.find(L"--ice")!=std::wstring::npos?1:args.find(L"--smoked")!=std::wstring::npos?2:args.find(L"--frost")!=std::wstring::npos?3:args.find(L"--aero")!=std::wstring::npos?4:args.find(L"--prism")!=std::wstring::npos?5:0;init_apartment(apartment_type::single_threaded);DispatcherQueueOptions options{sizeof(DispatcherQueueOptions),DQTYPE_THREAD_CURRENT,DQTAT_COM_STA};check_hresult(CreateDispatcherQueueController(options,reinterpret_cast<ABI::Windows::System::IDispatcherQueueController**>(put_abi(queue))));compositor=Compositor();check_hresult(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,d2dFactory.put()));WNDCLASSW cls{};cls.hInstance=instance;cls.lpfnWndProc=proc;cls.lpszClassName=L"MHGCompositionWaterLab";cls.hCursor=LoadCursor(nullptr,IDC_ARROW);RegisterClassW(&cls);HWND h=CreateWindowExW(WS_EX_NOREDIRECTIONBITMAP,cls.lpszClassName,L"Starting composition lab",WS_POPUP|WS_THICKFRAME|WS_MINIMIZEBOX|WS_MAXIMIZEBOX,CW_USEDEFAULT,CW_USEDEFAULT,900,600,nullptr,nullptr,instance,nullptr);if(!h)return 2;attach(h);ShowWindow(h,show);if(liveMode)std::thread([h](){std::string line;while(std::getline(std::cin,line)){if(line.size()>1024*1024)continue;auto payload=new std::string(std::move(line));if(!PostMessageW(h,WM_APP+3,0,reinterpret_cast<LPARAM>(payload))){delete payload;break;}}}).detach();MSG msg{};while(GetMessageW(&msg,nullptr,0,0)>0){TranslateMessage(&msg);DispatchMessageW(&msg);}return 0;}catch(hresult_error const&){return 3;}}
