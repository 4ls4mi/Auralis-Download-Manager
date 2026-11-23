#include "Typography.h"

#include <QApplication>
#include <QFontDatabase>
#include <QLocale>
#include <QSettings>

namespace {
const auto EnglishFontKey = QStringLiteral("Typography/englishFamily");
const auto ArabicFontKey = QStringLiteral("Typography/arabicFamily");

QStringList installedFamilies(QFontDatabase::WritingSystem script)
{
    QStringList families = QFontDatabase::families(script);
    families.removeDuplicates();
    families.sort(Qt::CaseInsensitive);
    return families;
}

QString installedFamily(const QString &requested, const QStringList &installed)
{
    const auto index = installed.indexOf(requested);
    if (index >= 0)
        return installed.at(index);
    for (const auto &family : installed) {
        if (family.compare(requested, Qt::CaseInsensitive) == 0)
            return family;
    }
    return {};
}

QStringList withPreferredFamily(QStringList families, const QString &family)
{
    if (!family.isEmpty()) {
        families.removeAll(family);
        families.prepend(family);
    }
    return families;
}

void applyScriptFallback(QChar::Script script, const QStringList &inherited,
                         const QString &selected)
{
    const auto families = withPreferredFamily(inherited, selected);
    if (QFontDatabase::applicationFallbackFontFamilies(script) != families)
        QFontDatabase::setApplicationFallbackFontFamilies(script, families);
}
}

Typography::Typography(QObject *parent)
    : QObject(parent),
      m_systemFont(QApplication::font()),
      m_latinFallbacks(QFontDatabase::applicationFallbackFontFamilies(QChar::Script_Latin)),
      m_arabicFallbacks(QFontDatabase::applicationFallbackFontFamilies(QChar::Script_Arabic)),
      m_englishFonts(installedFamilies(QFontDatabase::Latin)),
      m_arabicFonts(installedFamilies(QFontDatabase::Arabic))
{
    const QSettings settings;
    // Preserve an unavailable preference on disk so it can apply after the font is reinstalled.
    m_englishFamily = installedFamily(settings.value(EnglishFontKey).toString(), m_englishFonts);
    m_arabicFamily = installedFamily(settings.value(ArabicFontKey).toString(), m_arabicFonts);
    applyInterfaceFont();
}

QFont Typography::interfaceFont() const
{
    return fontWithFamily(QLocale().script() == QLocale::ArabicScript
                          ? m_arabicFamily : m_englishFamily);
}

QFont Typography::fontForText(const QString &text) const
{
    if (text.isEmpty())
        return interfaceFont();
    for (const auto codepoint : text.toUcs4()) {
        if (QChar::script(codepoint) == QChar::Script_Arabic)
            return fontWithFamily(m_arabicFamily);
    }
    return fontWithFamily(m_englishFamily);
}

QFont Typography::fontWithFamily(const QString &family) const
{
    QFont font = m_systemFont;
    if (!family.isEmpty())
        font.setFamilies(withPreferredFamily(font.families(), family));
    return font;
}

bool Typography::setEnglishFamily(const QString &family)
{
    return setFamily(EnglishFontKey, family, m_englishFonts, m_englishFamily);
}

bool Typography::setArabicFamily(const QString &family)
{
    return setFamily(ArabicFontKey, family, m_arabicFonts, m_arabicFamily);
}

bool Typography::setFamily(const QString &key, const QString &family,
                           const QStringList &installed, QString &selected)
{
    const QString available = installedFamily(family, installed);
    if (!family.isEmpty() && available.isEmpty())
        return false;

    QSettings settings;
    if (settings.value(key).toString() != available) {
        settings.setValue(key, available);
        settings.sync();
        if (settings.status() != QSettings::NoError)
            return false;
    }
    if (selected != available) {
        selected = available;
        applyInterfaceFont();
        emit fontChanged();
    }
    return true;
}

void Typography::applyInterfaceFont() const
{
    applyScriptFallback(QChar::Script_Latin, m_latinFallbacks, m_englishFamily);
    applyScriptFallback(QChar::Script_Arabic, m_arabicFallbacks, m_arabicFamily);

    const QFont font = interfaceFont();
    if (QApplication::font() != font)
        QApplication::setFont(font);
}
