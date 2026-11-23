#pragma once

#include <QFont>
#include <QList>
#include <QObject>
#include <QStringList>

class Typography final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QFont interfaceFont READ interfaceFont NOTIFY fontChanged)
    Q_PROPERTY(QStringList englishFonts READ englishFonts CONSTANT)
    Q_PROPERTY(QStringList arabicFonts READ arabicFonts CONSTANT)
    Q_PROPERTY(QString englishFamily READ englishFamily NOTIFY fontChanged)
    Q_PROPERTY(QString arabicFamily READ arabicFamily NOTIFY fontChanged)
    Q_PROPERTY(int fontSizePercent READ fontSizePercent NOTIFY fontChanged)
    Q_PROPERTY(int interfaceScalePercent READ interfaceScalePercent NOTIFY interfaceScaleChanged)
    Q_PROPERTY(int activeInterfaceScalePercent READ activeInterfaceScalePercent CONSTANT)
    Q_PROPERTY(QList<int> fontSizeChoices READ fontSizeChoices CONSTANT)
    Q_PROPERTY(QList<int> interfaceScaleChoices READ interfaceScaleChoices CONSTANT)

public:
    explicit Typography(int activeInterfaceScalePercent = 100, QObject *parent = nullptr);
    static int applyStartupInterfaceScale();

    QFont interfaceFont() const;
    QStringList englishFonts() const { return m_englishFonts; }
    QStringList arabicFonts() const { return m_arabicFonts; }
    QString englishFamily() const { return m_englishFamily; }
    QString arabicFamily() const { return m_arabicFamily; }
    int fontSizePercent() const { return m_fontSizePercent; }
    int interfaceScalePercent() const { return m_interfaceScalePercent; }
    int activeInterfaceScalePercent() const { return m_activeInterfaceScalePercent; }
    QList<int> fontSizeChoices() const;
    QList<int> interfaceScaleChoices() const;

    Q_INVOKABLE bool setEnglishFamily(const QString &family);
    Q_INVOKABLE bool setArabicFamily(const QString &family);
    Q_INVOKABLE bool setFontSizePercent(int percent);
    Q_INVOKABLE bool setInterfaceScalePercent(int percent);
    Q_INVOKABLE QFont fontForText(const QString &text) const;
    Q_INVOKABLE QFont previewFont(const QString &family) const;

signals:
    void fontChanged();
    void interfaceScaleChanged();

private:
    QFont fontWithFamily(const QString &family) const;
    bool setFamily(const QString &key, const QString &family,
                   const QStringList &installed, QString &selected);
    void applyInterfaceFont() const;

    const QFont m_systemFont;
    const QStringList m_latinFallbacks;
    const QStringList m_arabicFallbacks;
    const QStringList m_englishFonts;
    const QStringList m_arabicFonts;
    QString m_englishFamily;
    QString m_arabicFamily;
    int m_fontSizePercent;
    int m_interfaceScalePercent;
    const int m_activeInterfaceScalePercent;
};
