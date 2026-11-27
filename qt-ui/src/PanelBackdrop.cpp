#include "PanelBackdrop.h"
#include "WindowShadow.h"

#include <QByteArray>
#include <QJSValue>
#include <QPlatformSurfaceEvent>
#include <QPolygon>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRegion>
#include <QTransform>
#include <QWindow>
#include <QtMath>
#include <qt_windows.h>

#include <cstddef>
#include <limits>
#include <utility>
#include <dwmapi.h>

namespace {
constexpr auto observerName = "auralisPanelBackdrop";
constexpr DWORD darkMode = 20;
constexpr DWORD backdropType = 38;
constexpr DWORD borderColor = 34;
constexpr DWORD cornerPreference = 33;
constexpr int noBackdrop = 1;
constexpr int doNotRound = 1;
constexpr COLORREF noBorder = 0xfffffffe;
constexpr COLORREF defaultBorder = 0xffffffff;

struct PanelShape {
    QRect clip;
    QPolygon polygon;

    bool operator==(const PanelShape &) const = default;
};

struct PanelGeometry {
    const QQuickItem *item;
    QRect clip;
    QTransform toScene;
    QVariant outline;

    bool operator==(const PanelGeometry &other) const
    {
        if (item != other.item || clip != other.clip || toScene != other.toScene
            || outline.metaType() != other.outline.metaType())
            return false;
        if (outline.metaType() == QMetaType::fromType<QJSValue>())
            return outline.value<QJSValue>().strictlyEquals(other.outline.value<QJSValue>());
        return outline == other.outline;
    }
};

QRegion shadowMask(HRGN region)
{
    const DWORD bytes = GetRegionData(region, 0, nullptr);
    constexpr auto headerBytes = offsetof(RGNDATA, Buffer);
    if (bytes < headerBytes)
        return {};
    QByteArray storage(bytes, Qt::Uninitialized);
    auto *data = reinterpret_cast<RGNDATA *>(storage.data());
    if (GetRegionData(region, bytes, data) != bytes || data->rdh.iType != RDH_RECTANGLES
        || data->rdh.nCount > (bytes - headerBytes) / sizeof(RECT)
        || data->rdh.nCount > std::numeric_limits<int>::max())
        return {};

    // GDI lists non-overlapping rectangles from top to bottom, then left to right.
    const auto *rects = reinterpret_cast<const RECT *>(data->Buffer);
    QList<QRect> boxes;
    boxes.reserve(data->rdh.nCount);
    for (DWORD i = 0; i < data->rdh.nCount; ++i) {
        const auto &rect = rects[i];
        boxes.append(QRect(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top));
    }
    QRegion result;
    result.setRects(boxes.constData(), int(boxes.size()));
    return result;
}

class Backdrop final : public QObject
{
public:
    explicit Backdrop(QWindow *window) : QObject(window), m_window(window)
    {
        setObjectName(QString::fromLatin1(observerName));
        window->installEventFilter(this);
    }

    bool update(const QVariantList &panels, bool enabled)
    {
        if (!enabled || !m_window->handle() || !m_window->isVisible()
            || m_window->windowStates().testFlag(Qt::WindowMinimized)) {
            reset();
            return false;
        }
        const auto hwnd = reinterpret_cast<HWND>(m_window->winId());
        if (hwnd != m_hwnd) {
            reset();
            m_hwnd = hwnd;
        }
        const qreal scale = m_window->devicePixelRatio();
        RECT frame{};
        if (!GetWindowRect(hwnd, &frame))
            return m_regionSet;
        const QRect windowBounds(0, 0, frame.right - frame.left, frame.bottom - frame.top);
        const auto pixelRect = [scale](const QRectF &rect) {
            return QRect(qRound(rect.left() * scale), qRound(rect.top() * scale),
                         qRound(rect.right() * scale) - qRound(rect.left() * scale),
                         qRound(rect.bottom() * scale) - qRound(rect.top() * scale));
        };
        QList<PanelGeometry> geometry;
        geometry.reserve(panels.size());
        for (const QVariant &entry : panels) {
            auto *item = qobject_cast<QQuickItem *>(entry.value<QObject *>());
            if (!item || item->window() != m_window || !item->isVisible() || item->width() <= 0 || item->height() <= 0)
                continue;
            bool mapped = false;
            const QTransform toScene = item->itemTransform(nullptr, &mapped);
            if (!mapped)
                continue;
            const QRect rect = pixelRect(toScene.mapRect(item->boundingRect()));
            QRect clip = windowBounds;
            for (auto *parent = item->parentItem(); parent; parent = parent->parentItem()) {
                if (parent->clip())
                    clip &= pixelRect(parent->mapRectToScene(parent->boundingRect()));
            }
            if (!clip.intersects(rect))
                continue;
            geometry.append({item, clip, toScene, item->property("panelVertices")});
        }

        const bool sameFrame = m_regionSet && m_scale == scale && m_framePixels == windowBounds.size();
        // The QML panel publishes a fresh outline array whenever its shape changes.
        // A transfer animation alone need not unpack, copy or transform those vertices.
        if (sameFrame && m_geometry == geometry)
            return true;

        QList<PanelShape> shapes;
        shapes.reserve(geometry.size());
        for (const auto &panel : geometry) {
            const auto &data = panel.outline;
            const QVariantList vertices = data.metaType() == QMetaType::fromType<QJSValue>()
                ? data.value<QJSValue>().toVariant().toList() : data.toList();
            QPolygon polygon;
            polygon.reserve(vertices.size());
            for (const auto &vertex : vertices) {
                if (!vertex.canConvert<QPointF>())
                    continue;
                const QPointF point = panel.toScene.map(vertex.toPointF());
                if (qIsFinite(point.x()) && qIsFinite(point.y()))
                    polygon.append(QPoint(qRound(point.x() * scale), qRound(point.y() * scale)));
            }
            if (polygon.size() >= 3)
                shapes.append({panel.clip, std::move(polygon)});
        }

        if (shapes.isEmpty()) {
            reset();
            return false;
        }
        if (sameFrame && m_shapes == shapes) {
            m_geometry = std::move(geometry);
            return true;
        }

        const auto region = CreateRectRgn(0, 0, 0, 0);
        if (!region)
            return m_regionSet;
        bool nonempty = false;
        for (const auto &shape : shapes) {
            QList<POINT> points;
            points.reserve(shape.polygon.size());
            for (const auto &point : shape.polygon)
                points.append({point.x(), point.y()});
            const QRect clip = shape.clip;
            const auto polygon = CreatePolygonRgn(points.constData(), int(points.size()), WINDING);
            const auto clipping = CreateRectRgn(clip.left(), clip.top(), clip.right() + 1, clip.bottom() + 1);
            if (polygon && clipping && CombineRgn(polygon, polygon, clipping, RGN_AND) > NULLREGION)
                nonempty |= CombineRgn(region, region, polygon, RGN_OR) > NULLREGION;
            if (clipping)
                DeleteObject(clipping);
            if (polygon)
                DeleteObject(polygon);
        }

        if (!nonempty) {
            DeleteObject(region);
            reset();
            return false;
        }

        // Read the final mask before SetWindowRgn transfers its ownership to Windows.
        const QRegion mask = shadowMask(region);
        if (!SetWindowRgn(hwnd, region, TRUE)) {
            DeleteObject(region);
            reset();
            return false;
        }
        if (!m_regionSet) {
            DwmGetWindowAttribute(hwnd, darkMode, &m_previousDarkMode, sizeof(m_previousDarkMode));
            DwmGetWindowAttribute(hwnd, borderColor, &m_previousBorder, sizeof(m_previousBorder));
            DwmGetWindowAttribute(hwnd, cornerPreference, &m_previousCorners, sizeof(m_previousCorners));
            // A system material covers the full HWND bounds even when its window region has gaps.
            const MARGINS noExtension{0, 0, 0, 0};
            DwmSetWindowAttribute(hwnd, backdropType, &noBackdrop, sizeof(noBackdrop));
            DwmExtendFrameIntoClientArea(hwnd, &noExtension);
            const BOOL dark = TRUE;
            DwmSetWindowAttribute(hwnd, darkMode, &dark, sizeof(dark));
            DwmSetWindowAttribute(hwnd, borderColor, &noBorder, sizeof(noBorder));
            DwmSetWindowAttribute(hwnd, cornerPreference, &doNotRound, sizeof(doNotRound));
            m_regionSet = true; // Windows owns the region after SetWindowRgn succeeds.
        }

        WindowShadow::updatePanels(m_window, windowBounds.size(), mask, scale);
        m_geometry = std::move(geometry);
        m_shapes = std::move(shapes);
        m_framePixels = windowBounds.size();
        m_scale = scale;
        return m_regionSet;
    }

protected:
    bool eventFilter(QObject *object, QEvent *event) override
    {
        if (event->type() == QEvent::Hide || (event->type() == QEvent::PlatformSurface
            && static_cast<QPlatformSurfaceEvent *>(event)->surfaceEventType() == QPlatformSurfaceEvent::SurfaceAboutToBeDestroyed))
            reset();
        return QObject::eventFilter(object, event);
    }

private:
    void reset()
    {
        if (m_regionSet) {
            WindowShadow::clearPanels(m_window);
            DwmSetWindowAttribute(m_hwnd, borderColor, &m_previousBorder, sizeof(m_previousBorder));
            DwmSetWindowAttribute(m_hwnd, cornerPreference, &m_previousCorners, sizeof(m_previousCorners));
            DwmSetWindowAttribute(m_hwnd, darkMode, &m_previousDarkMode, sizeof(m_previousDarkMode));
            SetWindowRgn(m_hwnd, nullptr, TRUE);
        }
        m_hwnd = nullptr;
        m_regionSet = false;
        m_geometry.clear();
        m_shapes.clear();
        m_framePixels = {};
    }

    QWindow *m_window;
    HWND m_hwnd = nullptr;
    QList<PanelGeometry> m_geometry;
    QList<PanelShape> m_shapes;
    QSize m_framePixels;
    qreal m_scale = 0;
    BOOL m_previousDarkMode = FALSE;
    COLORREF m_previousBorder = defaultBorder;
    int m_previousCorners = 0;
    bool m_regionSet = false;
};
}

bool PanelBackdrop::update(QWindow *window, const QVariantList &panels, bool enabled)
{
    if (!window)
        return false;
    auto *backdrop = static_cast<Backdrop *>(window->findChild<QObject *>(QString::fromLatin1(observerName),
                                                                          Qt::FindDirectChildrenOnly));
    if (!backdrop && enabled)
        backdrop = new Backdrop(window);
    return backdrop && backdrop->update(panels, enabled);
}
