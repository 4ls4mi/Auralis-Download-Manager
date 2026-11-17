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
 unsigned width=0,height=0;
 static constexpr const char* source=R"HLSL(
 cbuffer Params:register(b0){float2 size;float2 pad;};
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
   float3 dark=float3(.004,.038,.065), teal=float3(.01,.23,.29);
   float3 color=lerp(dark,teal,.18+.45*(1-uv.y));
   color+=float3(.03,.12,.15)*exp(-length((uv-float2(.12,.08))*float2(2.2,3.0))*2.0);
   color+=float3(.07,.25,.30)*(edge*(.28+dir*.85)+nearEdge*.20);
   float streak=exp(-pow((uv.y-(.04+.018*sin(uv.x*8)))*42,2))*(.20+.8*exp(-pow((uv.x-.22)*3.5,2)));
   float low=exp(-pow((uv.y-(.96+.014*sin(uv.x*8)))*48,2))*(.25+.75*exp(-pow((uv.x-.77)*3,2)));
   float glint=spec(uv,float2(.11,.055),float2(7,34),3)+spec(uv,float2(.82,.96),float2(8,35),3);
   color+=float3(.35,.75,.82)*(streak*.32+low*.26+glint*.45);
   // Gentle interior caustic waves stay behind text; no extra DOM overlay.
   float caustic=exp(-pow((uv.y-(.90+.018*sin(uv.x*7)))*28,2));
   color+=float3(.01,.07,.09)*caustic;
   float a=.78;return float4(saturate(color)*a,a);
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
  D3D11_BUFFER_DESC bd{};bd.ByteWidth=16;bd.Usage=D3D11_USAGE_DEFAULT;bd.BindFlags=D3D11_BIND_CONSTANT_BUFFER;if(FAILED(hr=device->CreateBuffer(&bd,nullptr,&constants)))return hr;
  D3D11_RASTERIZER_DESC rd{};rd.FillMode=D3D11_FILL_SOLID;rd.CullMode=D3D11_CULL_NONE;rd.DepthClipEnable=TRUE;return device->CreateRasterizerState(&rd,&raster);
 }
 HRESULT draw(unsigned w,unsigned h){
  if(!w||!h)return S_OK;HRESULT hr=S_OK;if(w!=width||h!=height||!target){context->OMSetRenderTargets(0,nullptr,nullptr);target.Reset();if(FAILED(hr=swap->ResizeBuffers(0,w,h,DXGI_FORMAT_UNKNOWN,0)))return hr;
   Microsoft::WRL::ComPtr<ID3D11Texture2D> back;if(FAILED(hr=swap->GetBuffer(0,IID_PPV_ARGS(&back))))return hr;if(FAILED(hr=device->CreateRenderTargetView(back.Get(),nullptr,&target)))return hr;width=w;height=h;}
  float data[4]={float(w),float(h),0,0};context->UpdateSubresource(constants.Get(),0,nullptr,data,0,0);auto rt=target.Get();auto cb=constants.Get();context->OMSetRenderTargets(1,&rt,nullptr);D3D11_VIEWPORT vp{0,0,float(w),float(h),0,1};context->RSSetViewports(1,&vp);context->RSSetState(raster.Get());context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);context->VSSetShader(vertex.Get(),nullptr,0);context->PSSetShader(pixel.Get(),nullptr,0);context->PSSetConstantBuffers(0,1,&cb);context->Draw(3,0);return swap->Present(1,0);
 }
};
