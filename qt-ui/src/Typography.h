#pragma once

#include <QFont>
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

public:
    explicit Typography(QObject *parent = nullptr);

    QFont interfaceFont() const;
    QStringList englishFonts() const { return m_englishFonts; }
    QStringList arabicFonts() const { return m_arabicFonts; }
    QString englishFamily() const { return m_englishFamily; }
    QString arabicFamily() const { return m_arabicFamily; }

    Q_INVOKABLE bool setEnglishFamily(const QString &family);
    Q_INVOKABLE bool setArabicFamily(const QString &family);
    Q_INVOKABLE QFont fontForText(const QString &text) const;

signals:
    void fontChanged();

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
};
