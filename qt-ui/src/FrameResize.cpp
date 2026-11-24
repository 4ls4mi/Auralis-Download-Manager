#include "FrameResize.h"

#include <QMouseEvent>
#include <QPointer>
#include <QVariant>
#include <QWindow>

#ifdef Q_OS_WIN
#include <windows.h>
#include <windowsx.h>
#include <commctrl.h>
#endif

namespace {
QRect dragGeometry(QRect start, const QPoint &delta, Qt::Edges edges,
                   const QSize &minimum, const QSize &maximum)
{
    QRect next = start;
    if (edges & (Qt::LeftEdge | Qt::RightEdge)) {
        const bool fromLeft = edges.testFlag(Qt::LeftEdge);
        const int width = qBound(minimum.width(), start.width() + (fromLeft ? -delta.x() : delta.x()),
                                 qMax(minimum.width(), maximum.width()));
        next.setWidth(width);
        if (fromLeft)
            next.moveLeft(start.x() + start.width() - width);
    }
    if (edges & (Qt::TopEdge | Qt::BottomEdge)) {
        const bool fromTop = edges.testFlag(Qt::TopEdge);
        const int height = qBound(minimum.height(), start.height() + (fromTop ? -delta.y() : delta.y()),
                                  qMax(minimum.height(), maximum.height()));
        next.setHeight(height);
        if (fromTop)
            next.moveTop(start.y() + start.height() - height);
    }
    return next;
}

#ifdef Q_OS_WIN
Qt::Edges nativeEdges(WPARAM hit)
{
    switch (hit) {
    case HTLEFT: return Qt::LeftEdge;
    case HTRIGHT: return Qt::RightEdge;
    case HTTOP: return Qt::TopEdge;
    case HTBOTTOM: return Qt::BottomEdge;
    case HTTOPLEFT: return Qt::TopEdge | Qt::LeftEdge;
    case HTTOPRIGHT: return Qt::TopEdge | Qt::RightEdge;
    case HTBOTTOMLEFT: return Qt::BottomEdge | Qt::LeftEdge;
    case HTBOTTOMRIGHT: return Qt::BottomEdge | Qt::RightEdge;
    default: return {};
    }
}

LRESULT nativeHit(Qt::Edges edges)
{
    if (edges.testFlag(Qt::TopEdge))
        return edges.testFlag(Qt::LeftEdge) ? HTTOPLEFT : edges.testFlag(Qt::RightEdge) ? HTTOPRIGHT : HTTOP;
    if (edges.testFlag(Qt::BottomEdge))
        return edges.testFlag(Qt::LeftEdge) ? HTBOTTOMLEFT : edges.testFlag(Qt::RightEdge) ? HTBOTTOMRIGHT : HTBOTTOM;
    return edges.testFlag(Qt::LeftEdge) ? HTLEFT : edges.testFlag(Qt::RightEdge) ? HTRIGHT : HTCLIENT;
}
#endif
class ResizeFilter final : public QObject
{
public:
    ResizeFilter(QWindow *window, int borderSize, int cornerSize)
        : QObject(window), m_window(window), m_borderSize(qMax(1, borderSize)),
          m_cornerSize(qMax(m_borderSize, cornerSize))
    {
        setObjectName(QStringLiteral("auralisInteractiveResize"));
#ifdef Q_OS_WIN
        queueNativeAttach();
#endif
    }

    ~ResizeFilter() override
    {
#ifdef Q_OS_WIN
        detachNative();
#endif
    }

private:
    bool eventFilter(QObject *, QEvent *event) override
    {
        switch (event->type()) {
#ifdef Q_OS_WIN
        case QEvent::PlatformSurface:
            if (static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType() == QPlatformSurfaceEvent::SurfaceCreated)
                queueNativeAttach();
            else
                detachNative();
            return false;
        case QEvent::Show:
        case QEvent::Expose:
            queueNativeAttach();
            return false;
#endif
        case QEvent::MouseButtonPress:
        case QEvent::MouseButtonDblClick: {
            const auto *mouse = static_cast<QMouseEvent *>(event);
            if (mouse->button() != Qt::LeftButton)
                return false;
            finish();
            if (m_window->visibility() != QWindow::Windowed)
                return false;
            const Qt::Edges edges = edgesAt(mouse->position(), m_window->size());
            if (!edges)
                return false;
            m_grabbed = m_window->setMouseGrabEnabled(true);
#ifdef Q_OS_WIN
            if (!m_grabbed)
                return false; // Let the Qt Quick grip try its implicit mouse grab.
#endif

            // QWindow's event positions stay global even while resizing the
            // leading edge changes the positions of the window and its items.
            m_origin = mouse->globalPosition();
            m_geometry = m_window->geometry();
            m_edges = edges;
            return true;
        }
        case QEvent::MouseMove: {
            if (!m_edges)
                return false;
            const auto *mouse = static_cast<QMouseEvent *>(event);
            if (!mouse->buttons().testFlag(Qt::LeftButton)) {
                finish();
                return false;
            }
            resizeTo(mouse->globalPosition());
            return true;
        }
        case QEvent::MouseButtonRelease: {
            const auto *mouse = static_cast<QMouseEvent *>(event);
            if (!m_edges || mouse->button() != Qt::LeftButton)
                return false;
            resizeTo(mouse->globalPosition());
            finish();
            return true;
        }
        case QEvent::UngrabMouse:
            m_grabbed = false;
            finish();
            return false;
        case QEvent::Hide:
        case QEvent::Close:
#ifdef Q_OS_WIN
            detachNative();
#endif
            finish();
            return false;
        case QEvent::WindowDeactivate:
        case QEvent::WindowStateChange:
            finish();
            return false;
        default:
            return false;
        }
    }

    Qt::Edges edgesAt(const QPointF &position, const QSizeF &size) const
    {
        const qreal x = position.x();
        const qreal y = position.y();
        const qreal right = size.width() - x;
        const qreal bottom = size.height() - y;
        if (x < 0 || right <= 0 || y < 0 || bottom <= 0)
            return {};

        const auto offset = qMax(0, m_window->property("frameResizeInset").toInt());
        const qreal cornerSize = qMin(qreal(m_cornerSize + offset), qreal(qMin(size.width(), size.height())) / 2);
        const bool atCorner = qMin(x, right) <= cornerSize && qMin(y, bottom) <= cornerSize;
        const qreal margin = atCorner ? cornerSize : m_borderSize;
        Qt::Edges edges;
        if (m_window->minimumWidth() < m_window->maximumWidth()) {
            if (x < margin)
                edges |= Qt::LeftEdge;
            else if (right <= margin)
                edges |= Qt::RightEdge;
        }
        if (m_window->minimumHeight() < m_window->maximumHeight()) {
            if (y < margin)
                edges |= Qt::TopEdge;
            else if (bottom <= margin)
                edges |= Qt::BottomEdge;
        }
        return edges;
    }

    void resizeTo(const QPointF &position)
    {
        const QRect next = dragGeometry(m_geometry, (position - m_origin).toPoint(), m_edges,
                                        m_window->minimumSize(), m_window->maximumSize());
        if (next != m_window->geometry())
            m_window->setGeometry(next);
    }

#ifdef Q_OS_WIN
    // Non-client hit testing lets Windows reach the frame directly, before a
    // scroll view or a Qt Quick pointer grab can consume its mouse events.
    static LRESULT CALLBACK nativeProcedure(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam,
                                            UINT_PTR, DWORD_PTR reference)
    {
        auto *self = reinterpret_cast<ResizeFilter *>(reference);
        switch (message) {
        case WM_NCHITTEST:
            if (const auto edges = self->hitWindowsFrame(lParam))
                return nativeHit(edges);
            break;
        case WM_SETCURSOR:
            if (const auto edges = nativeEdges(LOWORD(lParam))) {
                const auto type = nativeHit(edges);
                const auto cursor = (type == HTTOPLEFT || type == HTBOTTOMRIGHT) ? IDC_SIZENWSE
                    : (type == HTTOPRIGHT || type == HTBOTTOMLEFT) ? IDC_SIZENESW
                    : (type == HTLEFT || type == HTRIGHT) ? IDC_SIZEWE : IDC_SIZENS;
                SetCursor(LoadCursor(nullptr, cursor));
                return TRUE;
            }
            break;
        case WM_NCLBUTTONDOWN:
            if (const auto edges = nativeEdges(wParam); edges && self->beginNative(edges))
                return 0;
            break;
        case WM_MOUSEMOVE:
            if (self->m_nativeEdges) {
                if (wParam & MK_LBUTTON)
                    self->resizeNative();
                else
                    self->finishNative();
                return 0;
            }
            break;
        case WM_LBUTTONUP:
        case WM_NCLBUTTONUP:
            if (self->m_nativeEdges) {
                // SetWindowPos can synchronously deliver a resize that closes this window.
                const QPointer<ResizeFilter> alive(self);
                self->resizeNative();
                if (alive)
                    alive->finishNative();
                return 0;
            }
            break;
        case WM_CAPTURECHANGED:
            self->m_nativeEdges = {};
            break;
        case WM_CANCELMODE:
            self->finishNative();
            break;
        case WM_ACTIVATE:
            if (LOWORD(wParam) == WA_INACTIVE)
                self->finishNative();
            break;
        case WM_SHOWWINDOW:
            if (!wParam)
                self->finishNative();
            break;
        case WM_NCDESTROY:
            self->detachNative();
            break;
        }
        return DefSubclassProc(hwnd, message, wParam, lParam);
    }

    void queueNativeAttach()
    {
        if (m_hwnd || m_attachQueued)
            return;
        m_attachQueued = true;
        QMetaObject::invokeMethod(this, [this] {
            m_attachQueued = false;
            // Win32 subclass registration belongs after Qt finishes creating
            // and exposing the native window, not in its platform-surface callback.
            if (m_hwnd || !m_window->isExposed() || !m_window->handle())
                return;
            const auto hwnd = reinterpret_cast<HWND>(m_window->winId());
            if (!hwnd)
                return;
            m_hwnd = hwnd;
            if (!SetWindowSubclass(hwnd, nativeProcedure, 1, reinterpret_cast<DWORD_PTR>(this)))
                m_hwnd = nullptr;
        }, Qt::QueuedConnection);
    }

    void detachNative()
    {
        if (!m_hwnd)
            return;
        const auto hwnd = m_hwnd;
        const bool release = m_nativeEdges && GetCapture() == hwnd;
        m_hwnd = nullptr;
        m_nativeEdges = {};
        // ReleaseCapture delivers another native message synchronously.
        RemoveWindowSubclass(hwnd, nativeProcedure, 1);
        if (release)
            ReleaseCapture();
    }

    Qt::Edges hitWindowsFrame(LPARAM position) const
    {
        RECT bounds{};
        if (!IsWindowEnabled(m_hwnd) || IsZoomed(m_hwnd) || IsIconic(m_hwnd)
            || m_window->visibility() != QWindow::Windowed || !GetWindowRect(m_hwnd, &bounds))
            return {};
        const qreal scale = m_window->devicePixelRatio();
        return edgesAt(QPointF(GET_X_LPARAM(position) - bounds.left, GET_Y_LPARAM(position) - bounds.top) / scale,
                       QSizeF(bounds.right - bounds.left, bounds.bottom - bounds.top) / scale);
    }

    bool beginNative(Qt::Edges edges)
    {
        POINT position{};
        RECT bounds{};
        if (!GetCursorPos(&position) || !GetWindowRect(m_hwnd, &bounds))
            return false;

        const auto hwnd = m_hwnd;
        const QPointer<ResizeFilter> alive(this);
        SetCapture(hwnd);
        if (!alive || alive->m_hwnd != hwnd || GetCapture() != hwnd)
            return false;

        m_nativeEdges = edges;
        m_nativeScale = m_window->devicePixelRatio();
        m_nativeOrigin = QPoint(position.x, position.y);
        m_nativeGeometry = QRect(bounds.left, bounds.top, bounds.right - bounds.left, bounds.bottom - bounds.top);
        return true;
    }

    void resizeNative()
    {
        POINT position{};
        RECT bounds{};
        if (!GetCursorPos(&position) || !GetWindowRect(m_hwnd, &bounds))
            return;
        const QRect next = dragGeometry(m_nativeGeometry, QPoint(position.x, position.y) - m_nativeOrigin, m_nativeEdges,
            m_window->minimumSize() * m_nativeScale, m_window->maximumSize() * m_nativeScale);
        if (next != QRect(bounds.left, bounds.top, bounds.right - bounds.left, bounds.bottom - bounds.top)) {
            SetWindowPos(m_hwnd, nullptr, next.x(), next.y(), next.width(), next.height(),
                         SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOOWNERZORDER);
        }
    }

    void finishNative()
    {
        if (!m_nativeEdges)
            return;
        m_nativeEdges = {};
        if (GetCapture() == m_hwnd)
            ReleaseCapture();
    }

    HWND m_hwnd = nullptr;
    bool m_attachQueued = false;
    Qt::Edges m_nativeEdges;
    qreal m_nativeScale = 1;
    QPoint m_nativeOrigin;
    QRect m_nativeGeometry;
#endif

    void finish()
    {
        m_edges = {};
        if (m_grabbed) {
            m_grabbed = false;
            m_window->setMouseGrabEnabled(false);
        }
    }

    QWindow *const m_window;
    const int m_borderSize;
    const int m_cornerSize;
    Qt::Edges m_edges;
    QPointF m_origin;
    QRect m_geometry;
    bool m_grabbed = false;
};
}

void FrameResize::install(QWindow *window, int borderSize, int cornerSize)
{
    if (!window || window->findChild<QObject *>(QStringLiteral("auralisInteractiveResize"), Qt::FindDirectChildrenOnly))
        return;
    window->installEventFilter(new ResizeFilter(window, borderSize, cornerSize));
}
