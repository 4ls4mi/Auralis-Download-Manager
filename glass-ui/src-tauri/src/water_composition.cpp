// Experimental Windows 11 host backdrop + Direct3D surface composition.
// The compositor samples the desktop; this code does not capture or read pixels.
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <dwmapi.h>
#include <DispatcherQueue.h>
#include <dxgi1_2.h>
#include <windows.ui.composition.interop.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.UI.Composition.Desktop.h>
#include <new>
using namespace winrt;
using namespace Windows::UI::Composition;
using namespace Windows::UI::Composition::Desktop;
namespace {
// The controller must outlive the compositor objects and belong to the HWND thread.
thread_local Windows::System::DispatcherQueueController ownedQueue{nullptr};
thread_local bool apartmentReady=false;
struct Composition {
 HWND hwnd=nullptr;
 Compositor compositor{nullptr};
 DesktopWindowTarget target{nullptr};
 ContainerVisual root{nullptr};
 SpriteVisual backdrop{nullptr},material{nullptr};
 ICompositionSurface surface{nullptr};
};
void set_size(Composition& c,unsigned w,unsigned h){
 c.root.Size({static_cast<float>(w),static_cast<float>(h)});
 c.backdrop.Size({static_cast<float>(w),static_cast<float>(h)});
 c.material.Size({static_cast<float>(w),static_cast<float>(h)});
}
}
extern "C" void* mhg_water_composition_create(HWND hwnd,IDXGISwapChain1* swap,unsigned w,unsigned h){
 Composition* c=nullptr;bool backdropEnabled=false;
 try{
  if(!apartmentReady){init_apartment(apartment_type::single_threaded);apartmentReady=true;}
  if(!Windows::System::DispatcherQueue::GetForCurrentThread()){
   DispatcherQueueOptions options{sizeof(DispatcherQueueOptions),DQTYPE_THREAD_CURRENT,DQTAT_COM_STA};
   check_hresult(CreateDispatcherQueueController(options,reinterpret_cast<ABI::Windows::System::IDispatcherQueueController**>(put_abi(ownedQueue))));
  }
  BOOL enabled=TRUE;check_hresult(DwmSetWindowAttribute(hwnd,DWMWA_USE_HOSTBACKDROPBRUSH,&enabled,sizeof(enabled)));backdropEnabled=true;
  c=new(std::nothrow) Composition{};if(!c){enabled=FALSE;DwmSetWindowAttribute(hwnd,DWMWA_USE_HOSTBACKDROPBRUSH,&enabled,sizeof(enabled));return nullptr;}c->hwnd=hwnd;
  c->compositor=Compositor();
  auto desktop=c->compositor.as<ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop>();
  // The lower visual tree must remain behind the WebView2 child window.
  check_hresult(desktop->CreateDesktopWindowTarget(hwnd,false,reinterpret_cast<ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget**>(put_abi(c->target))));
  auto interop=c->compositor.as<ABI::Windows::UI::Composition::ICompositorInterop>();
  check_hresult(interop->CreateCompositionSurfaceForSwapChain(swap,reinterpret_cast<ABI::Windows::UI::Composition::ICompositionSurface**>(put_abi(c->surface))));
  c->root=c->compositor.CreateContainerVisual();c->backdrop=c->compositor.CreateSpriteVisual();c->material=c->compositor.CreateSpriteVisual();
  c->backdrop.Brush(c->compositor.CreateHostBackdropBrush());c->material.Brush(c->compositor.CreateSurfaceBrush(c->surface));
  c->root.Children().InsertAtTop(c->backdrop);c->root.Children().InsertAtTop(c->material);set_size(*c,w,h);c->target.Root(c->root);
  return c;
 }catch(...){delete c;if(backdropEnabled&&IsWindow(hwnd)){BOOL disabled=FALSE;DwmSetWindowAttribute(hwnd,DWMWA_USE_HOSTBACKDROPBRUSH,&disabled,sizeof(disabled));}return nullptr;}
}
extern "C" int mhg_water_composition_resize(void* value,unsigned w,unsigned h){
 try{if(!value)return 0;set_size(*reinterpret_cast<Composition*>(value),w,h);return 1;}catch(...){return 0;}
}
extern "C" void mhg_water_composition_destroy(void* value){
 auto* c=reinterpret_cast<Composition*>(value);if(!c)return;HWND hwnd=c->hwnd;
 try{if(c->target)c->target.Root(nullptr);}catch(...){}
 delete c;if(IsWindow(hwnd)){BOOL disabled=FALSE;DwmSetWindowAttribute(hwnd,DWMWA_USE_HOSTBACKDROPBRUSH,&disabled,sizeof(disabled));}
}
