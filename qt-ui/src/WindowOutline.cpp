#include "WindowOutline.h"

#include <QByteArray>
#include <QImage>
#include <QMatrix4x4>
#include <QPainter>
#include <QPolygonF>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>

#include <array>
#include <cmath>
#include <cstring>
#include <numbers>

namespace {
class OutlineShader final : public QSGMaterialShader
{
public:
    OutlineShader()
    {
        setShaderFileName(VertexStage, QStringLiteral(":/auralis/shaders/window-outline.vert.qsb"));
        setShaderFileName(FragmentStage, QStringLiteral(":/auralis/shaders/window-outline.frag.qsb"));
        setFlag(UpdatesGraphicsPipelineState);
    }

    bool updateUniformData(RenderState &state, QSGMaterial *material, QSGMaterial *) override;

    bool updateGraphicsPipelineState(RenderState &, GraphicsPipelineState *state, QSGMaterial *,
                                     QSGMaterial *) override
    {
        // Apply the analytic coverage to the rendered scene's premultiplied color and alpha.
        state->blendEnable = true;
        state->srcColor = GraphicsPipelineState::Zero;
        state->dstColor = GraphicsPipelineState::SrcAlpha;
        state->separateBlendFactors = true;
        state->srcAlpha = GraphicsPipelineState::Zero;
        state->dstAlpha = GraphicsPipelineState::SrcAlpha;
        return true;
    }
};

class OutlineMaterial final : public QSGMaterial
{
public:
    OutlineMaterial()
    {
        setFlag(Blending);
        setFlag(NoBatching);
    }

    QSGMaterialType *type() const override
    {
        static QSGMaterialType type;
        return &type;
    }

    QSGMaterialShader *createShader(QSGRendererInterface::RenderMode) const override
    {
        return new OutlineShader;
    }

    QSizeF reach;
};

bool OutlineShader::updateUniformData(RenderState &state, QSGMaterial *material, QSGMaterial *)
{
    const auto matrix = state.combinedMatrix();
    const auto reach = static_cast<OutlineMaterial *>(material)->reach;
    const float limits[] = {float(reach.width()), float(reach.height())};
    auto *data = state.uniformData();
    constexpr qsizetype matrixSize = 16 * sizeof(float);
    std::memcpy(data->data(), matrix.constData(), matrixSize);
    std::memcpy(data->data() + matrixSize, limits, sizeof limits);
    return true;
}

class OutlineItem final : public QQuickItem
{
public:
    explicit OutlineItem(QQuickItem *parent) : QQuickItem(parent)
    {
        setObjectName(QStringLiteral("auralisWindowOutline"));
        setFlag(ItemHasContents);
        // The application window's wallpaper, chrome, content and popup overlay are siblings.
        setZ(1000000);
    }

    void updateShape(const QSizeF &size, const QSizeF &reach, int corners)
    {
        if (size == QSizeF(width(), height()) && reach == m_reach && corners == m_corners && isVisible())
            return;
        setSize(size);
        m_reach = reach;
        m_corners = corners;
        setVisible(true);
        update();
    }

protected:
    QSGNode *updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *) override
    {
        auto *node = static_cast<QSGGeometryNode *>(oldNode);
        if (!node) {
            node = new QSGGeometryNode;
            auto *geometry = new QSGGeometry(QSGGeometry::defaultAttributes_TexturedPoint2D(), 16, 24);
            geometry->setDrawingMode(QSGGeometry::DrawTriangles);
            auto *indices = geometry->indexDataAsUShort();
            for (int corner = 0; corner < 4; ++corner) {
                const quint16 first = corner * 4;
                const quint16 quad[] = {first, quint16(first + 1), quint16(first + 2),
                                        quint16(first + 2), quint16(first + 1), quint16(first + 3)};
                std::memcpy(indices + corner * 6, quad, sizeof quad);
            }
            node->setGeometry(geometry);
            node->setFlag(QSGNode::OwnsGeometry);
            node->setMaterial(new OutlineMaterial);
            node->setFlag(QSGNode::OwnsMaterial);
        }

        const float windowWidth = float(width());
        const float windowHeight = float(height());
        const float cornerWidth = qMin(float(m_reach.width()) + 1.0f, windowWidth / 2.0f);
        const float cornerHeight = qMin(float(m_reach.height()) + 1.0f, windowHeight / 2.0f);
        auto *vertices = node->geometry()->vertexDataAsTexturedPoint2D();
        for (int corner = 0; corner < 4; ++corner) {
            const bool right = corner % 2;
            const bool bottom = corner >= 2;
            const float edgeX = right ? windowWidth : 0;
            const float edgeY = bottom ? windowHeight : 0;
            if (!(m_corners & (1 << corner))) {
                for (int point = 0; point < 4; ++point)
                    vertices[corner * 4 + point].set(edgeX, edgeY, 0, 0);
                continue;
            }
            const float innerX = right ? edgeX - cornerWidth : cornerWidth;
            const float innerY = bottom ? edgeY - cornerHeight : cornerHeight;
            vertices[corner * 4].set(edgeX, edgeY, 0, 0);
            vertices[corner * 4 + 1].set(innerX, edgeY, cornerWidth, 0);
            vertices[corner * 4 + 2].set(edgeX, innerY, 0, cornerHeight);
            vertices[corner * 4 + 3].set(innerX, innerY, cornerWidth, cornerHeight);
        }
        static_cast<OutlineMaterial *>(node->material())->reach = m_reach;
        node->markDirty(QSGNode::DirtyGeometry | QSGNode::DirtyMaterial);
        return node;
    }

private:
    QSizeF m_reach;
    int m_corners = 15;
};
}

bool WindowOutline::configureAntialiasing(QWindow *window, const QSizeF &reach, int corners)
{
    auto *quickWindow = qobject_cast<QQuickWindow *>(window);
    if (!quickWindow)
        return false;

    auto *content = quickWindow->contentItem();
    auto *item = static_cast<OutlineItem *>(content->findChild<QQuickItem *>(
        QStringLiteral("auralisWindowOutline"), Qt::FindDirectChildrenOnly));
    if (reach.isEmpty() || !quickWindow->rendererInterface()->isApiRhiBased(
                               quickWindow->rendererInterface()->graphicsApi())) {
        if (item)
            item->setVisible(false);
        return false;
    }
    if (!item)
        item = new OutlineItem(content);
    item->updateShape(window->size(), reach, corners);
    return true;
}

QPolygonF WindowOutline::framePolygon(const QRectF &frame, const QSizeF &reach, int corners, qreal fringe)
{
    constexpr int segments = 48;
    static const auto quarter = [] {
        std::array<QPointF, segments + 1> points;
        points.front() = QPointF(1, 0);
        points.back() = QPointF(0, 1);
        for (int i = 1; i < segments; ++i) {
            const qreal angle = (std::numbers::pi_v<qreal> / 2) * i / segments;
            points[i] = QPointF(std::pow(std::cos(angle), 2.0 / 3.05),
                                std::pow(std::sin(angle), 2.0 / 3.05));
        }
        return points;
    }();

    QPolygonF polygon;
    polygon.reserve(qsizetype(quarter.size()) * 4);
    for (const int corner : {1, 3, 2, 0}) {
        const bool right = corner % 2;
        const bool bottom = corner >= 2;
        const qreal edgeX = right ? frame.right() : frame.left();
        const qreal edgeY = bottom ? frame.bottom() : frame.top();
        if (!(corners & (1 << corner)) || reach.isEmpty()) {
            polygon << QPointF(edgeX, edgeY);
            continue;
        }
        for (const auto &point : quarter) {
            const qreal x = qMax(0.0, reach.width() * (1 - (right == bottom ? point.x() : point.y())) - fringe);
            const qreal y = qMax(0.0, reach.height() * (1 - (right == bottom ? point.y() : point.x())) - fringe);
            polygon << QPointF(right ? edgeX - x : edgeX + x, bottom ? edgeY - y : edgeY + y);
        }
    }
    return polygon;
}

namespace {
// A separable moving average keeps all three blur passes linear in the image size.
void boxBlur(const QByteArray &input, QByteArray &output, const QSize &size, int radius, bool horizontal)
{
    const int lineCount = horizontal ? size.height() : size.width();
    const int lineLength = horizontal ? size.width() : size.height();
    const int stride = horizontal ? 1 : size.width();
    const int lineStep = horizontal ? size.width() : 1;
    const int divisor = 2 * radius + 1;
    const auto *source = reinterpret_cast<const uchar *>(input.constData());
    auto *target = reinterpret_cast<uchar *>(output.data());
    for (int line = 0; line < lineCount; ++line) {
        int sum = 0;
        for (int pos = 0; pos < qMin(radius + 1, lineLength); ++pos)
            sum += source[pos * stride];
        for (int pos = 0; pos < lineLength; ++pos) {
            target[pos * stride] = uchar((sum + divisor / 2) / divisor);
            if (pos >= radius)
                sum -= source[(pos - radius) * stride];
            if (pos + radius + 1 < lineLength)
                sum += source[(pos + radius + 1) * stride];
        }
        source += lineStep;
        target += lineStep;
    }
}
}

QImage WindowOutline::shadowImage(const QSize &framePixels, const QSizeF &reachPixels,
                                  int corners, qreal scale, int padding)
{
    const QSize size = framePixels + QSize(2 * padding, 2 * padding);
    if (framePixels.isEmpty() || padding <= 0 || scale <= 0 || size.isEmpty()
        || qint64(size.width()) * size.height() > 32 * 1024 * 1024)
        return {};

    QImage image(size, QImage::Format_ARGB32_Premultiplied);
    if (image.isNull())
        return image;
    image.fill(Qt::transparent);
    {
        QPainter painter(&image);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.setPen(Qt::NoPen);
        painter.setBrush(Qt::white);
        painter.drawPolygon(framePolygon(QRectF(QPointF(padding, padding), framePixels), reachPixels, corners));
    }

    const int width = size.width();
    const int height = size.height();
    const qsizetype pixelCount = qsizetype(width) * height;
    QByteArray blurred(pixelCount, Qt::Uninitialized);
    QByteArray scratch(pixelCount, Qt::Uninitialized);
    auto *buffer = reinterpret_cast<uchar *>(blurred.data());
    for (int y = 0; y < height; ++y) {
        const auto *row = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        auto *target = buffer + qsizetype(y) * width;
        for (int x = 0; x < width; ++x)
            target[x] = uchar(qAlpha(row[x]));
    }
    for (const qreal logicalRadius : {1.0, 2.0, 3.0}) {
        const int radius = qBound(1, qRound(logicalRadius * scale), padding);
        boxBlur(blurred, scratch, size, radius, true);
        boxBlur(scratch, blurred, size, radius, false);
    }

    // Center the shadow around all edges. Erase the original silhouette so
    // the layered popup cannot darken the owner's translucent interior.
    constexpr int offsetX = 0;
    constexpr int offsetY = 0;
    constexpr int shadowStrength = 132;
    for (int y = 0; y < height; ++y) {
        auto *row = reinterpret_cast<QRgb *>(image.scanLine(y));
        const auto *shadow = y >= offsetY
            ? reinterpret_cast<const uchar *>(blurred.constData() + qsizetype(y - offsetY) * width) : nullptr;
        for (int x = 0; x < width; ++x) {
            const int outside = 255 - qAlpha(row[x]);
            const int alpha = shadow && x >= offsetX
                ? (outside * shadow[x - offsetX] * shadowStrength + 32512) / 65025 : 0;
            row[x] = qRgba(0, 0, 0, alpha);
        }
    }
    return image;
}
