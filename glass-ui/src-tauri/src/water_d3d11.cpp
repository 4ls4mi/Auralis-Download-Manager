// Development-only Direct3D 11 shader renderer for the progress HWND.
// No desktop capture. Hardware is preferred; Windows WARP is a fallback.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <commctrl.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>
#include <algorithm>
#include <new>
using Microsoft::WRL::ComPtr;
extern "C" int mhg_water_clip(HWND hwnd);
namespace {
constexpr UINT_PTR kSubclass=0x4d484744;
struct Uniforms { float width,height,light,pad; float r,g,b,a; };
struct Renderer {
 ComPtr<ID3D11Device> device;
 ComPtr<ID3D11DeviceContext> context;
 ComPtr<IDXGISwapChain> swap;
 ComPtr<ID3D11RenderTargetView> target;
 ComPtr<ID3D11VertexShader> vertex;
 ComPtr<ID3D11PixelShader> pixel;
 ComPtr<ID3D11Buffer> uniforms;
 ComPtr<ID3D11RasterizerState> rasterizer;
 UINT width=0,height=0,clipWidth=0,clipHeight=0;
 float r=0,g=0,b=0;bool light=false;
};
const char shader[]=R"HLSL(
cbuffer Parameters : register(b0) { float2 size; float light; float unused; float4 accent; };
struct Vertex { float4 position:SV_Position; };
Vertex vs(uint id:SV_VertexID) {
 float2 p[3]={float2(-1,-1),float2(-1,3),float2(3,-1)};
 Vertex o;o.position=float4(p[id],0,1);return o;
}
float4 ps(Vertex i):SV_Target {
 float2 uv=i.position.xy/size;
 float2 p=uv*2-1;
 float wave=.015*sin(uv.x*12)+.008*sin(uv.x*23);
 p.y+=wave;
 float2 q=abs(p)-float2(.96,.88);
 float edge=length(max(q,0))+min(max(q.x,q.y),0)-.08;
 float rim=exp(-abs(edge)*55);
 float top=pow(saturate(1-abs(uv.y-(.10+.02*sin(uv.x*5)))*12),3);
 float lower=pow(saturate(1-abs(uv.y-(.90+.018*sin(uv.x*8)))*20),4);
 float gleam=pow(saturate(1-length((uv-float2(.78,.12))*float2(2.2,7))),3);
 float3 dark=float3(.015,.045,.085), bright=float3(.72,.84,.9);
 float3 base=lerp(dark,bright,light);
 base=lerp(base,accent.rgb,light>.5?.13:.23);
 base*=.83+.17*(1-uv.y);
 base+=float3(.33,.51,.59)*(top*.22+lower*.14+gleam*.5);
 base+=lerp(float3(.16,.54,.67),float3(.42,.64,.7),light)*rim*.35;
 return float4(saturate(base),1);
}
)HLSL";
HRESULT create(HWND hwnd,Renderer& s){
 DXGI_SWAP_CHAIN_DESC desc{};desc.BufferCount=2;desc.BufferDesc.Format=DXGI_FORMAT_B8G8R8A8_UNORM;
 desc.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;desc.OutputWindow=hwnd;desc.SampleDesc.Count=1;desc.Windowed=TRUE;desc.SwapEffect=DXGI_SWAP_EFFECT_DISCARD;
 D3D_FEATURE_LEVEL level{};
 HRESULT hr=D3D11CreateDeviceAndSwapChain(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,&desc,&s.swap,&s.device,&level,&s.context);
 if(FAILED(hr)){s.swap.Reset();s.device.Reset();s.context.Reset();hr=D3D11CreateDeviceAndSwapChain(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,&desc,&s.swap,&s.device,&level,&s.context);}
 if(FAILED(hr))return hr;
 ComPtr<ID3DBlob> code,error;hr=D3DCompile(shader,sizeof(shader)-1,nullptr,nullptr,nullptr,"vs","vs_4_0",D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&code,&error);if(FAILED(hr))return hr;
 hr=s.device->CreateVertexShader(code->GetBufferPointer(),code->GetBufferSize(),nullptr,&s.vertex);if(FAILED(hr))return hr;
 code.Reset();error.Reset();hr=D3DCompile(shader,sizeof(shader)-1,nullptr,nullptr,nullptr,"ps","ps_4_0",D3DCOMPILE_OPTIMIZATION_LEVEL3,0,&code,&error);if(FAILED(hr))return hr;
 hr=s.device->CreatePixelShader(code->GetBufferPointer(),code->GetBufferSize(),nullptr,&s.pixel);if(FAILED(hr))return hr;
 D3D11_RASTERIZER_DESC raster{};raster.FillMode=D3D11_FILL_SOLID;raster.CullMode=D3D11_CULL_NONE;raster.DepthClipEnable=TRUE;
 hr=s.device->CreateRasterizerState(&raster,&s.rasterizer);if(FAILED(hr))return hr;
 D3D11_BUFFER_DESC buffer{};buffer.ByteWidth=sizeof(Uniforms);buffer.Usage=D3D11_USAGE_DEFAULT;buffer.BindFlags=D3D11_BIND_CONSTANT_BUFFER;
 return s.device->CreateBuffer(&buffer,nullptr,&s.uniforms);
}
HRESULT render(HWND hwnd,Renderer& s){
 RECT rc{};if(!GetClientRect(hwnd,&rc))return E_FAIL;
 UINT w=static_cast<UINT>(std::max(1L,rc.right-rc.left)),h=static_cast<UINT>(std::max(1L,rc.bottom-rc.top));
 if(!s.swap){HRESULT hr=create(hwnd,s);if(FAILED(hr))return hr;}
 if(w!=s.width||h!=s.height||!s.target){
  s.context->OMSetRenderTargets(0,nullptr,nullptr);s.target.Reset();
  HRESULT hr=s.swap->ResizeBuffers(0,w,h,DXGI_FORMAT_UNKNOWN,0);if(FAILED(hr))return hr;
  ComPtr<ID3D11Texture2D> back;hr=s.swap->GetBuffer(0,__uuidof(ID3D11Texture2D),reinterpret_cast<void**>(back.GetAddressOf()));if(FAILED(hr))return hr;
  hr=s.device->CreateRenderTargetView(back.Get(),nullptr,&s.target);if(FAILED(hr))return hr;s.width=w;s.height=h;
 }
 Uniforms u{static_cast<float>(w),static_cast<float>(h),s.light?1.f:0.f,0,s.r,s.g,s.b,1};
 s.context->UpdateSubresource(s.uniforms.Get(),0,nullptr,&u,0,0);ID3D11Buffer* buffer=s.uniforms.Get();ID3D11RenderTargetView* target=s.target.Get();
 s.context->OMSetRenderTargets(1,&target,nullptr);D3D11_VIEWPORT viewport{0,0,static_cast<float>(w),static_cast<float>(h),0,1};s.context->RSSetViewports(1,&viewport);s.context->RSSetState(s.rasterizer.Get());
 s.context->IASetInputLayout(nullptr);s.context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
 s.context->VSSetShader(s.vertex.Get(),nullptr,0);s.context->PSSetShader(s.pixel.Get(),nullptr,0);s.context->PSSetConstantBuffers(0,1,&buffer);s.context->Draw(3,0);
 return s.swap->Present(1,0);
}
bool clip(HWND hwnd,Renderer& s){RECT rc{};if(!GetClientRect(hwnd,&rc))return false;UINT w=rc.right-rc.left,h=rc.bottom-rc.top;if(w==s.clipWidth&&h==s.clipHeight)return true;s.clipWidth=w;s.clipHeight=h;if(!mhg_water_clip(hwnd)){s.clipWidth=s.clipHeight=0;return false;}return true;}
LRESULT CALLBACK proc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp,UINT_PTR id,DWORD_PTR data){
 auto *s=reinterpret_cast<Renderer*>(data);
 if(msg==WM_PAINT){PAINTSTRUCT ps{};BeginPaint(hwnd,&ps);render(hwnd,*s);EndPaint(hwnd,&ps);return 0;}
 if(msg==WM_ERASEBKGND)return 1;
 if(msg==WM_SIZE){clip(hwnd,*s);InvalidateRect(hwnd,nullptr,FALSE);}
 if(msg==WM_NCDESTROY){RemoveWindowSubclass(hwnd,proc,id);delete s;}
 return DefSubclassProc(hwnd,msg,wp,lp);
}
}
extern "C" void mhg_d3d11_water_remove(HWND hwnd){DWORD_PTR data=0;if(GetWindowSubclass(hwnd,proc,kSubclass,&data)){RemoveWindowSubclass(hwnd,proc,kSubclass);delete reinterpret_cast<Renderer*>(data);SetWindowRgn(hwnd,nullptr,TRUE);InvalidateRect(hwnd,nullptr,TRUE);}}
extern "C" int mhg_d3d11_water_surface(HWND hwnd,unsigned rgb,int light){
 if(!IsWindow(hwnd))return 0;DWORD_PTR data=0;Renderer *s=nullptr;
 if(GetWindowSubclass(hwnd,proc,kSubclass,&data))s=reinterpret_cast<Renderer*>(data);
 else{s=new(std::nothrow) Renderer{};if(!s)return 0;if(!SetWindowSubclass(hwnd,proc,kSubclass,reinterpret_cast<DWORD_PTR>(s))){delete s;return 0;}}
 s->r=((rgb>>16)&255)/255.f;s->g=((rgb>>8)&255)/255.f;s->b=(rgb&255)/255.f;s->light=light!=0;
 if(FAILED(render(hwnd,*s))||!clip(hwnd,*s)){mhg_d3d11_water_remove(hwnd);return 0;}
 InvalidateRect(hwnd,nullptr,FALSE);return 1;
}
