#include "WindowOutline.h"

#include <QMatrix4x4>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSGGeometryNode>
#include <QSGMaterial>
#include <QSGMaterialShader>

#include <cstring>

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

    void updateShape(const QSizeF &size, const QSizeF &reach)
    {
        if (size == QSizeF(width(), height()) && reach == m_reach && isVisible())
            return;
        setSize(size);
        m_reach = reach;
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
};
}

bool WindowOutline::configureAntialiasing(QWindow *window, const QSizeF &reach)
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
    item->updateShape(window->size(), reach);
    return true;
}
