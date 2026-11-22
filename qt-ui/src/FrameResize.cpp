#include "FrameResize.h"

#include <QMouseEvent>
#include <QWindow>

namespace {
class ResizeFilter final : public QObject
{
public:
    ResizeFilter(QWindow *window, int borderSize, int cornerSize)
        : QObject(window), m_window(window), m_borderSize(qMax(1, borderSize)),
          m_cornerSize(qMax(m_borderSize, cornerSize))
    {
        setObjectName(QStringLiteral("auralisInteractiveResize"));
    }

private:
    bool eventFilter(QObject *, QEvent *event) override
    {
        switch (event->type()) {
        case QEvent::MouseButtonPress:
        case QEvent::MouseButtonDblClick: {
            const auto *mouse = static_cast<QMouseEvent *>(event);
            if (mouse->button() != Qt::LeftButton)
                return false;
            finish();
            if (m_window->visibility() != QWindow::Windowed)
                return false;
            const Qt::Edges edges = edgesAt(mouse->position());
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
        case QEvent::WindowDeactivate:
        case QEvent::WindowStateChange:
            finish();
            return false;
        default:
            return false;
        }
    }

    Qt::Edges edgesAt(const QPointF &position) const
    {
        const qreal x = position.x();
        const qreal y = position.y();
        const qreal right = m_window->width() - x;
        const qreal bottom = m_window->height() - y;
        if (x < 0 || right <= 0 || y < 0 || bottom <= 0)
            return {};

        const bool atCorner = qMin(x, right) <= m_cornerSize && qMin(y, bottom) <= m_cornerSize;
        const int margin = atCorner ? m_cornerSize : m_borderSize;
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
        const QPoint delta = (position - m_origin).toPoint();
        QRect next = m_geometry;
        if (m_edges.testFlag(Qt::LeftEdge) || m_edges.testFlag(Qt::RightEdge)) {
            const bool fromLeft = m_edges.testFlag(Qt::LeftEdge);
            const int width = qBound(m_window->minimumWidth(),
                m_geometry.width() + (fromLeft ? -delta.x() : delta.x()), m_window->maximumWidth());
            next.setWidth(width);
            if (fromLeft)
                next.moveLeft(m_geometry.x() + m_geometry.width() - width);
        }
        if (m_edges.testFlag(Qt::TopEdge) || m_edges.testFlag(Qt::BottomEdge)) {
            const bool fromTop = m_edges.testFlag(Qt::TopEdge);
            const int height = qBound(m_window->minimumHeight(),
                m_geometry.height() + (fromTop ? -delta.y() : delta.y()), m_window->maximumHeight());
            next.setHeight(height);
            if (fromTop)
                next.moveTop(m_geometry.y() + m_geometry.height() - height);
        }
        if (next != m_window->geometry())
            m_window->setGeometry(next);
    }

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
