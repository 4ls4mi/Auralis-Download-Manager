#pragma once
// Standalone proof: D3D11 surface for the composition-hosted lab.
// Host backdrop stays in Windows Composition; this shader does not read it.
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi1_2.h>
#include <wrl/client.h>
#include <algorithm>
#pragma comment(lib,"d3d11.lib")
#pragma comment(lib,"dxgi.lib")
#pragma comment(lib,"d3dcompiler.lib")
struct LabMaterial {
 Microsoft::WRL::ComPtr<ID3D11Device> device;
 Microsoft::WRL::ComPtr<ID3D11DeviceContext> context;
 Microsoft::WRL::ComPtr<IDXGISwapChain1> swap;
 Microsoft::WRL::ComPtr<ID3D11RenderTargetView> target;
 Microsoft::WRL::ComPtr<ID3D11VertexShader> vertex;
 Microsoft::WRL::ComPtr<ID3D11PixelShader> pixel;
 Microsoft::WRL::ComPtr<ID3D11Buffer> constants;
 Microsoft::WRL::ComPtr<ID3D11RasterizerState> raster;
 unsigned width=0,height=0; int materialStyle=0; float panelRects[12]{};
 static constexpr const char* source=R"HLSL(
 cbuffer Params:register(b0){float2 size;float style;float pad;float4 panels[3];};
 struct V{float4 position:SV_Position;};
 V vs(uint i:SV_VertexID){float2 a[3]={float2(-1,-1),float2(-1,3),float2(3,-1)};V o;o.position=float4(a[i],0,1);return o;}
 float spec(float2 uv,float2 at,float2 scale,float power){return pow(saturate(1-length((uv-at)*scale)),power);}
 float4 ps(V input):SV_Target{
   float2 uv=input.position.xy/size;
   // Procedural, approximate relief. These reflections are authored lighting,
   // not refraction of screen pixels or a captured desktop.
   float wave=.008*sin(uv.x*11)+.004*sin(uv.x*23);
   float2 p=uv*2-1;p.y+=wave;
   float2 q=abs(p)-float2(.88,.84);
   float d=length(max(q,0))+min(max(q.x,q.y),0)-.13;
   float2 n=normalize(float2(ddx(d)*size.x,ddy(d)*size.y)+.00001);
   float edge=exp(-abs(d)*64);
   float nearEdge=exp(-abs(d+.028)*40);
   float dir=pow(saturate(dot(n,normalize(float2(-.7,-.7)))),3);
   float3 dark=float3(.015,.075,.105), teal=float3(.025,.31,.35);
   float3 color=lerp(dark,teal,.25+.48*(1-uv.y));
   color+=float3(.03,.12,.15)*exp(-length((uv-float2(.12,.08))*float2(2.2,3.0))*2.0);
   color+=float3(.22,.60,.65)*(edge*(.38+dir*1.35)+nearEdge*.28);
   float streak=exp(-pow((uv.y-(.04+.018*sin(uv.x*8)))*42,2))*(.20+.8*exp(-pow((uv.x-.22)*3.5,2)));
   float low=exp(-pow((uv.y-(.96+.014*sin(uv.x*8)))*48,2))*(.25+.75*exp(-pow((uv.x-.77)*3,2)));
   float glint=spec(uv,float2(.11,.055),float2(7,34),3)+spec(uv,float2(.82,.96),float2(8,35),3);
   color+=float3(.35,.75,.82)*(streak*.32+low*.26+glint*.45);
   // Gentle interior caustic waves stay behind text; no extra DOM overlay.
   float caustic=exp(-pow((uv.y-(.90+.018*sin(uv.x*7)))*28,2));
   color+=float3(.01,.07,.09)*caustic;
   if(style>.5 && style<1.5){
     // Ice uses a pale crystalline surface with angular facet lighting.
     // It is an authored effect; desktop pixels are not sampled here.
     float facet=abs(frac(uv.x*3.7+uv.y*2.6)-.5);
     float shard=pow(saturate(1-abs(frac(uv.x*2.7-uv.y*3.1)-.5)*2),6);
     color=float3(.56,.76,.87)+float3(.12,.17,.19)*(1-uv.y)+float3(.10,.12,.15)*shard;
     color-=float3(.045,.035,.025)*step(.31,facet);
     color+=float3(.20,.22,.24)*edge;
   }
   if(style>1.5){
     // Smoked Crystal: dark glass and narrow diagonal crystalline planes.
     float plane=step(.5,frac(uv.x*2.9+uv.y*2.15));
     float bevel=pow(saturate(1-abs(frac(uv.x*3.3-uv.y*2.1)-.5)*2),12);
     color=float3(.025,.035,.075)+float3(.04,.06,.11)*(1-uv.y)+plane*float3(.012,.015,.03);
     color+=float3(.16,.24,.43)*bevel*.35+float3(.22,.32,.52)*edge;
   }
   if(style==3){
     // Frosted Layers: a soft pale field with curved, translucent strata.
     float strata=.5+.5*cos(uv.x*5+uv.y*11);
     color=float3(.58,.70,.85)+float3(.10,.11,.12)*(1-uv.y)+strata*float3(.025,.035,.05)+edge*float3(.16,.17,.19);
   }
   if(style==4){
     // Aero Gloss: a blue glass volume with a strong curved upper sheen.
     float sweep=exp(-pow((uv.y-(.12+.17*pow(uv.x-.5,2)))*10,2));
     color=float3(.015,.08,.20)+float3(.02,.16,.35)*(1-uv.y)+sweep*float3(.07,.18,.28)+edge*float3(.16,.33,.50);
   }
   if(style==5){
     // Prismatic: angular rainbow highlights on a pale crystal base.
     float2 cell=frac(uv*float2(4,3));float shard=step(cell.x,cell.y);
     float rainbow=pow(saturate(1-abs(frac(uv.x*3-uv.y*2)-.5)*2),8);
     color=float3(.58,.70,.85)+shard*float3(.07,.07,.08)+rainbow*float3(.22,.12,.30)+edge*float3(.20,.21,.24);
   }
   // Panels use the WebView's measured rectangles, but their material is
   // drawn here in the same pass as the outer glass.
   [unroll] for(int i=0;i<3;i++){
     float4 rect=panels[i];if(rect.z>1 && rect.w>1){
       float2 halfSize=rect.zw*.5;float radius=min(32.0,min(halfSize.x,halfSize.y)*.33);
       float2 local=input.position.xy-(rect.xy+halfSize);
       float2 b=abs(local)-halfSize+radius;
       float dist=length(max(b,0))+min(max(b.x,b.y),0)-radius;
       if(style==1 || style==2 || style==5){float2 c=abs(local)-halfSize;dist=max(max(c.x,c.y),(c.x+c.y+min(halfSize.x,halfSize.y)*.25)*.7071);}
       float inside=1-smoothstep(-1.2,1.2,dist);
       float2 normal=normalize(float2(ddx(dist),ddy(dist))+.0001);
       float angle=pow(saturate(dot(normal,normalize(float2(-.55,-.83)))),2);
       float rim=exp(-abs(dist)*.40);
       float inner=exp(-abs(dist+5)*.23);
       float vertical=saturate((local.y+halfSize.y)/max(rect.w,1));
       float3 panel=lerp(float3(.035,.21,.25),float3(.009,.075,.10),vertical);
       if(style>.5 && style<1.5)panel=lerp(float3(.81,.91,.96),float3(.62,.79,.88),vertical);
       if(style==2)panel=lerp(float3(.11,.15,.25),float3(.025,.035,.075),vertical);
       if(style==3 || style==5)panel=lerp(float3(.83,.89,.96),float3(.65,.76,.88),vertical);
       if(style==4)panel=lerp(float3(.04,.19,.38),float3(.01,.045,.12),vertical);
       color=lerp(color,panel,inside*.60);
       color+=float3(.45,.75,.78)*(rim*(.18+.85*angle)+inner*.12);
       float highlight=inside*exp(-pow((local.y+halfSize.y-5)/12,2));
       color+=float3(.35,.70,.72)*highlight*.30;
     }
   }
   float a=(style==1||style==3||style==5)?.94:.78;return float4(saturate(color)*a,a);
 }
 )HLSL";
 HRESULT init(){
  D3D_FEATURE_LEVEL level{};HRESULT hr=D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_HARDWARE,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,&device,&level,&context);
  if(FAILED(hr))hr=D3D11CreateDevice(nullptr,D3D_DRIVER_TYPE_WARP,nullptr,D3D11_CREATE_DEVICE_BGRA_SUPPORT,nullptr,0,D3D11_SDK_VERSION,&device,&level,&context);if(FAILED(hr))return hr;
  Microsoft::WRL::ComPtr<IDXGIDevice> dxgi;Microsoft::WRL::ComPtr<IDXGIAdapter> adapter;Microsoft::WRL::ComPtr<IDXGIFactory2> factory;
  if(FAILED(hr=device.As(&dxgi)))return hr;if(FAILED(hr=dxgi->GetAdapter(&adapter)))return hr;if(FAILED(hr=adapter->GetParent(IID_PPV_ARGS(&factory))))return hr;
  DXGI_SWAP_CHAIN_DESC1 d{};d.Width=1;d.Height=1;d.Format=DXGI_FORMAT_B8G8R8A8_UNORM;d.SampleDesc.Count=1;d.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;d.BufferCount=2;d.Scaling=DXGI_SCALING_STRETCH;d.SwapEffect=DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;d.AlphaMode=DXGI_ALPHA_MODE_PREMULTIPLIED;
  if(FAILED(hr=factory->CreateSwapChainForComposition(device.Get(),&d,nullptr,&swap)))return hr;
  Microsoft::WRL::ComPtr<ID3DBlob> code,error;if(FAILED(hr=D3DCompile(source,strlen(source),nullptr,nullptr,nullptr,"vs","vs_4_0",0,0,&code,&error)))return hr;
  if(FAILED(hr=device->CreateVertexShader(code->GetBufferPointer(),code->GetBufferSize(),nullptr,&vertex)))return hr;code.Reset();error.Reset();
  if(FAILED(hr=D3DCompile(source,strlen(source),nullptr,nullptr,nullptr,"ps","ps_4_0",0,0,&code,&error)))return hr;
  if(FAILED(hr=device->CreatePixelShader(code->GetBufferPointer(),code->GetBufferSize(),nullptr,&pixel)))return hr;
  D3D11_BUFFER_DESC bd{};bd.ByteWidth=64;bd.Usage=D3D11_USAGE_DEFAULT;bd.BindFlags=D3D11_BIND_CONSTANT_BUFFER;if(FAILED(hr=device->CreateBuffer(&bd,nullptr,&constants)))return hr;
  D3D11_RASTERIZER_DESC rd{};rd.FillMode=D3D11_FILL_SOLID;rd.CullMode=D3D11_CULL_NONE;rd.DepthClipEnable=TRUE;return device->CreateRasterizerState(&rd,&raster);
 }
 HRESULT draw(unsigned w,unsigned h){
  if(!w||!h)return S_OK;HRESULT hr=S_OK;if(w!=width||h!=height||!target){context->OMSetRenderTargets(0,nullptr,nullptr);target.Reset();if(FAILED(hr=swap->ResizeBuffers(0,w,h,DXGI_FORMAT_UNKNOWN,0)))return hr;
   Microsoft::WRL::ComPtr<ID3D11Texture2D> back;if(FAILED(hr=swap->GetBuffer(0,IID_PPV_ARGS(&back))))return hr;if(FAILED(hr=device->CreateRenderTargetView(back.Get(),nullptr,&target)))return hr;width=w;height=h;}
  float data[16]={float(w),float(h),float(materialStyle),0};for(int i=0;i<12;i++)data[i+4]=panelRects[i];context->UpdateSubresource(constants.Get(),0,nullptr,data,0,0);auto rt=target.Get();auto cb=constants.Get();context->OMSetRenderTargets(1,&rt,nullptr);D3D11_VIEWPORT vp{0,0,float(w),float(h),0,1};context->RSSetViewports(1,&vp);context->RSSetState(raster.Get());context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);context->VSSetShader(vertex.Get(),nullptr,0);context->PSSetShader(pixel.Get(),nullptr,0);context->PSSetConstantBuffers(0,1,&cb);context->Draw(3,0);return swap->Present(1,0);
 }
};
