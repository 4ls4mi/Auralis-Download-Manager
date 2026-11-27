#include "WindowShadow.h"
#include "WindowOutline.h"

#include <QImage>
#include <QPainter>
#include <QPlatformSurfaceEvent>
#include <QRegion>
#include <QTimer>
#include <QWindow>
#include <QtMath>

#include <cstring>
#include <utility>
#include <windows.h>
#include <dwmapi.h>

namespace {
constexpr wchar_t shadowClass[] = L"AuralisDropShadow";
constexpr wchar_t observerProperty[] = L"AuralisDropShadowObserver";
constexpr auto observerName = "auralisDropShadow";
constexpr int shadowPadding = 20;
constexpr int resizeDelay = 75;
constexpr qint64 maximumShadowPixels = 48'000'000;

class Shadow final : public QObject
{
public:
    explicit Shadow(QWindow *owner) : QObject(owner), m_owner(owner)
    {
        setObjectName(QString::fromLatin1(observerName));
        m_resizeTimer.setSingleShot(true);
        m_resizeTimer.setInterval(resizeDelay);
        connect(&m_resizeTimer, &QTimer::timeout, this, [this] { refresh(false); });
        owner->installEventFilter(this);
    }

    ~Shadow() override
    {
        releaseWindows();
    }

    void setShape(const QSizeF &reach, int corners)
    {
        m_frameEnabled = true;
        m_reach = reach.isValid() ? reach : QSizeF(0, 0);
        m_corners = corners & 15;
        scheduleRefresh();
    }

    void clearFrame()
    {
        m_frameEnabled = false;
        if (m_panels.isEmpty())
            releaseWindows();
    }

    void setPanels(const QSize &framePixels, const QRegion &panels, qreal scale)
    {
        if (m_panels == panels && m_panelFrame == framePixels && m_panelScale == scale)
            return;
        m_panels = panels;
        m_panelFrame = framePixels;
        m_panelScale = scale;
        ++m_panelRevision;
        scheduleRefresh();
    }

    void clearPanels()
    {
        if (m_panels.isEmpty())
            return;
        m_panels = {};
        hide();
        if (m_frameEnabled)
            scheduleRefresh();
        else
            releaseWindows();
    }

protected:
    bool eventFilter(QObject *object, QEvent *event) override
    {
        switch (event->type()) {
        case QEvent::PlatformSurface: {
            const auto *surface = static_cast<QPlatformSurfaceEvent *>(event);
            if (surface->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed)
                releaseWindows();
            else
                scheduleRefresh();
            break;
        }
        case QEvent::Hide:
            hide();
            break;
        case QEvent::Move:
        case QEvent::Resize:
        case QEvent::WindowStateChange:
        case QEvent::DevicePixelRatioChange:
            refresh(true);
            scheduleRefresh();
            break;
        case QEvent::Show:
        case QEvent::Expose:
            scheduleRefresh();
            break;
        default:
            break;
        }
        return QObject::eventFilter(object, event);
    }

private:
    static LRESULT CALLBACK windowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
    {
        switch (message) {
        case WM_NCCREATE: {
            const auto *create = reinterpret_cast<const CREATESTRUCTW *>(lparam);
            SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create->lpCreateParams));
            break;
        }
        case WM_NCDESTROY: {
            auto *shadow = reinterpret_cast<Shadow *>(GetWindowLongPtrW(window, GWLP_USERDATA));
            if (shadow && shadow->m_shadow == window)
                shadow->m_shadow = nullptr;
            break;
        }
        case WM_NCHITTEST:
            return HTTRANSPARENT;
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        }
        return DefWindowProcW(window, message, wparam, lparam);
    }

    static void CALLBACK cloakChanged(HWINEVENTHOOK hook, DWORD, HWND window, LONG object, LONG child, DWORD, DWORD)
    {
        if (!window || object != OBJID_WINDOW || child != CHILDID_SELF)
            return;
        auto *shadow = reinterpret_cast<Shadow *>(GetPropW(window, observerProperty));
        if (shadow && shadow->m_cloakHook == hook)
            shadow->scheduleRefresh();
    }

    bool createShadow(HWND owner)
    {
        if (m_shadow)
            return true;
        const auto instance = GetModuleHandleW(nullptr);
        static const auto registered = [instance] {
            WNDCLASSW details{};
            details.lpfnWndProc = windowProc;
            details.hInstance = instance;
            details.lpszClassName = shadowClass;
            return RegisterClassW(&details) != 0;
        }();
        if (!registered)
            return false;

        // An owned popup stays with its owner and is absent from the taskbar and Alt+Tab.
        m_shadow = CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
                                   shadowClass, L"", WS_POPUP, 0, 0, 0, 0,
                                   owner, nullptr, instance, this);
        return m_shadow != nullptr;
    }

    void observeOwner(HWND owner)
    {
        if (owner == m_nativeOwner)
            return;
        releaseWindows();
        m_nativeOwner = owner;
        if (SetPropW(owner, observerProperty, reinterpret_cast<HANDLE>(this))) {
            m_cloakHook = SetWinEventHook(EVENT_OBJECT_CLOAKED, EVENT_OBJECT_UNCLOAKED, nullptr,
                                         cloakChanged, GetCurrentProcessId(), 0, WINEVENT_OUTOFCONTEXT);
        }
    }

    void scheduleRefresh()
    {
        if (m_refreshQueued)
            return;
        m_refreshQueued = true;
        QTimer::singleShot(0, this, [this] {
            m_refreshQueued = false;
            refresh(true);
        });
    }

    void hide()
    {
        m_resizeTimer.stop();
        if (m_shadow && IsWindowVisible(m_shadow))
            ShowWindow(m_shadow, SW_HIDE);
    }

    void releaseWindows()
    {
        m_resizeTimer.stop();
        if (m_cloakHook)
            UnhookWinEvent(m_cloakHook);
        m_cloakHook = nullptr;
        if (m_nativeOwner && GetPropW(m_nativeOwner, observerProperty) == reinterpret_cast<HANDLE>(this))
            RemovePropW(m_nativeOwner, observerProperty);
        m_nativeOwner = nullptr;
        if (m_shadow)
            DestroyWindow(m_shadow);
        m_shadow = nullptr;
        m_framePixels = {};
    }

    static bool upload(HWND target, const QImage &image, const QPoint &origin)
    {
        if (image.isNull() || image.format() != QImage::Format_ARGB32_Premultiplied
            || image.bytesPerLine() != image.width() * 4)
            return false;
        BITMAPINFO bitmapInfo{};
        bitmapInfo.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bitmapInfo.bmiHeader.biWidth = image.width();
        bitmapInfo.bmiHeader.biHeight = -image.height();
        bitmapInfo.bmiHeader.biPlanes = 1;
        bitmapInfo.bmiHeader.biBitCount = 32;
        bitmapInfo.bmiHeader.biCompression = BI_RGB;
        void *pixels = nullptr;
        const auto bitmap = CreateDIBSection(nullptr, &bitmapInfo, DIB_RGB_COLORS, &pixels, nullptr, 0);
        if (!bitmap)
            return false;

        const auto dc = CreateCompatibleDC(nullptr);
        bool success = false;
        if (dc) {
            const auto old = SelectObject(dc, bitmap);
            if (old && old != HGDI_ERROR) {
                std::memcpy(pixels, image.constBits(), image.sizeInBytes());
                POINT destination{origin.x(), origin.y()};
                SIZE size{image.width(), image.height()};
                POINT source{0, 0};
                BLENDFUNCTION blend{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
                success = UpdateLayeredWindow(target, nullptr, &destination, &size, dc, &source, 0, &blend,
                                              ULW_ALPHA);
                SelectObject(dc, old);
            }
            DeleteDC(dc);
        }
        DeleteObject(bitmap);
        return success;
    }

    void refresh(bool debounce)
    {
        const bool panels = !m_panels.isEmpty();
        const auto states = m_owner->windowStates();
        if ((!m_frameEnabled && !panels) || !m_owner->isVisible() || !m_owner->handle()
            || states.testAnyFlags(Qt::WindowMinimized | Qt::WindowFullScreen)
            || (!panels && states.testFlag(Qt::WindowMaximized)) || !(m_owner->flags() & Qt::FramelessWindowHint)) {
            hide();
            return;
        }

        const auto nativeOwner = reinterpret_cast<HWND>(m_owner->winId());
        observeOwner(nativeOwner);
        RECT rect{};
        DWORD cloaked = 0;
        if (!IsWindowVisible(nativeOwner) || IsIconic(nativeOwner) || (!panels && IsZoomed(nativeOwner))
            || !GetWindowRect(nativeOwner, &rect)
            || (SUCCEEDED(DwmGetWindowAttribute(nativeOwner, DWMWA_CLOAKED, &cloaked, sizeof cloaked)) && cloaked)) {
            hide();
            return;
        }

        const QSize framePixels(rect.right - rect.left, rect.bottom - rect.top);
        const qreal scale = m_owner->devicePixelRatio();
        const QSizeF reachPixels = m_reach * scale;
        const int padding = qCeil(shadowPadding * scale);
        const QSize imageSize = framePixels + QSize(2 * padding, 2 * padding);
        if (framePixels.isEmpty() || padding <= 0
            || qint64(imageSize.width()) * imageSize.height() > maximumShadowPixels
            || (panels && (m_panelFrame != framePixels || m_panelScale != scale))) {
            hide();
            return;
        }

        const QPoint origin(rect.left - padding, rect.top - padding);
        const bool changed = m_framePixels != framePixels || m_renderedScale != scale || m_renderedPanels != panels
            || (panels ? m_renderedPanelRevision != m_panelRevision
                       : m_renderedReach != reachPixels || m_renderedCorners != m_corners);
        if (changed && debounce && m_shadow && m_framePixels.isValid()) {
            // The old image no longer matches the transparent interior of the owner.
            hide();
            m_resizeTimer.start();
            return;
        }
        if (!m_shadow || changed) {
            if (!createShadow(nativeOwner))
                return;
            const auto image = panels ? panelImage(imageSize, scale, padding)
                                      : WindowOutline::shadowImage(framePixels, reachPixels, m_corners, scale, padding);
            if (!upload(m_shadow, image, origin)) {
                hide();
                return;
            }
            m_framePixels = framePixels;
            m_renderedReach = reachPixels;
            m_renderedScale = scale;
            m_renderedCorners = m_corners;
            m_renderedPanels = panels;
            m_renderedPanelRevision = m_panelRevision;
            m_origin = origin;
        }

        m_resizeTimer.stop();
        if (m_origin != origin || !IsWindowVisible(m_shadow)) {
            if (SetWindowPos(m_shadow, nullptr, origin.x(), origin.y(), 0, 0,
                             SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW))
                m_origin = origin;
        }
    }

    QImage panelImage(const QSize &size, qreal scale, int padding) const
    {
        QImage mask(size, QImage::Format_ARGB32_Premultiplied);
        if (mask.isNull())
            return mask;
        mask.fill(Qt::transparent);
        {
            QPainter painter(&mask);
            painter.translate(padding, padding);
            painter.setClipRegion(m_panels);
            painter.fillRect(QRect(QPoint(), m_panelFrame), Qt::white);
        }
        const QPoint cast(qRound(2.5 * scale), qRound(6.5 * scale));
        return WindowOutline::blurShadowMask(std::move(mask), scale, padding, cast, 192);
    }

    QWindow *m_owner;
    HWND m_nativeOwner = nullptr;
    HWND m_shadow = nullptr;
    HWINEVENTHOOK m_cloakHook = nullptr;
    QTimer m_resizeTimer;
    bool m_refreshQueued = false;
    bool m_frameEnabled = false;
    QSizeF m_reach;
    int m_corners = 0;
    QRegion m_panels;
    QSize m_panelFrame;
    qreal m_panelScale = 0;
    quint64 m_panelRevision = 0;
    QSize m_framePixels;
    QSizeF m_renderedReach;
    qreal m_renderedScale = 0;
    int m_renderedCorners = 0;
    bool m_renderedPanels = false;
    quint64 m_renderedPanelRevision = 0;
    QPoint m_origin;
};

Shadow *shadowFor(QWindow *owner, bool create = false)
{
    if (!owner)
        return nullptr;
    auto *shadow = static_cast<Shadow *>(owner->findChild<QObject *>(QString::fromLatin1(observerName),
                                                                   Qt::FindDirectChildrenOnly));
    return !shadow && create ? new Shadow(owner) : shadow;
}
}

void WindowShadow::clearFrame(QWindow *owner)
{
    if (auto *shadow = shadowFor(owner))
        shadow->clearFrame();
}

void WindowShadow::clearPanels(QWindow *owner)
{
    if (auto *shadow = shadowFor(owner))
        shadow->clearPanels();
}

void WindowShadow::update(QWindow *owner, const QSizeF &reach, int corners)
{
    if (auto *shadow = shadowFor(owner, true))
        shadow->setShape(reach, corners);
}

void WindowShadow::updatePanels(QWindow *owner, const QSize &framePixels, const QRegion &panels, qreal scale)
{
    if (panels.isEmpty()) {
        clearPanels(owner);
    } else if (auto *shadow = shadowFor(owner, true)) {
        shadow->setPanels(framePixels, panels, scale);
    }
}
