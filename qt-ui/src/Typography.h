#pragma once

#include <QFont>
#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QVariant>

class Typography final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QFont interfaceFont READ interfaceFont NOTIFY fontChanged)
    Q_PROPERTY(QVariantList englishFontOptions READ englishFontOptions NOTIFY fontOptionsChanged)
    Q_PROPERTY(QVariantList arabicFontOptions READ arabicFontOptions NOTIFY fontOptionsChanged)
    Q_PROPERTY(QString englishFamily READ englishFamily NOTIFY fontChanged)
    Q_PROPERTY(QString arabicFamily READ arabicFamily NOTIFY fontChanged)
    Q_PROPERTY(int fontSizePercent READ fontSizePercent NOTIFY fontChanged)
    Q_PROPERTY(int interfaceScalePercent READ interfaceScalePercent NOTIFY interfaceScaleChanged)
    Q_PROPERTY(int activeInterfaceScalePercent READ activeInterfaceScalePercent CONSTANT)
    Q_PROPERTY(int fontSizeMinimum READ fontSizeMinimum CONSTANT)
    Q_PROPERTY(int fontSizeMaximum READ fontSizeMaximum CONSTANT)
    Q_PROPERTY(int interfaceScaleMinimum READ interfaceScaleMinimum CONSTANT)
    Q_PROPERTY(int interfaceScaleMaximum READ interfaceScaleMaximum CONSTANT)

public:
    explicit Typography(int activeInterfaceScalePercent = 100, QObject *parent = nullptr);
    static int applyStartupInterfaceScale();

    QFont interfaceFont() const;
    QVariantList englishFontOptions() const { return m_englishFontOptions; }
    QVariantList arabicFontOptions() const { return m_arabicFontOptions; }
    QString englishFamily() const { return m_englishFamily; }
    QString arabicFamily() const { return m_arabicFamily; }
    int fontSizePercent() const { return m_fontSizePercent; }
    int interfaceScalePercent() const { return m_interfaceScalePercent; }
    int activeInterfaceScalePercent() const { return m_activeInterfaceScalePercent; }
    int fontSizeMinimum() const;
    int fontSizeMaximum() const;
    int interfaceScaleMinimum() const;
    int interfaceScaleMaximum() const;

    Q_INVOKABLE bool applyFontPreferences(const QString &englishFamily, const QString &arabicFamily, int sizePercent);
    Q_INVOKABLE bool setInterfaceScalePercent(int percent);
    Q_INVOKABLE QFont fontForText(const QString &text) const;
    Q_INVOKABLE QFont previewFont(const QString &family) const;
    Q_INVOKABLE QString importFont(const QUrl &file);

signals:
    void fontChanged();
    void fontOptionsChanged();
    void interfaceScaleChanged();

private:
    QFont fontWithFamily(const QString &family) const;
    void applyInterfaceFont() const;
    void refreshFontOptions();

    const QFont m_systemFont;
    const QStringList m_latinFallbacks;
    const QStringList m_arabicFallbacks;
    QVariantList m_englishFontOptions;
    QVariantList m_arabicFontOptions;
    QString m_preferredEnglishFamily;
    QString m_preferredArabicFamily;
    QString m_englishFamily;
    QString m_arabicFamily;
    int m_fontSizePercent;
    int m_interfaceScalePercent;
    const int m_activeInterfaceScalePercent;
};
