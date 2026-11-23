#include "Typography.h"

#include <QApplication>
#include <QFontDatabase>
#include <QLocale>
#include <QSettings>

#include <cmath>

namespace {
const auto EnglishFontKey = QStringLiteral("Typography/englishFamily");
const auto ArabicFontKey = QStringLiteral("Typography/arabicFamily");
const auto FontSizeKey = QStringLiteral("Typography/fontSizePercent");
const auto FontPreferencesKey = QStringLiteral("Typography/fontPreferences");
const auto InterfaceScaleKey = QStringLiteral("Typography/interfaceScalePercent");
const QList<int> FontSizeChoices{85, 90, 100, 110, 120, 130};
const QList<int> InterfaceScaleChoices{85, 90, 100, 110, 125, 150};
constexpr int DefaultPercent = 100;

int savedPercent(const QVariant &value, const QList<int> &choices)
{
    bool valid = false;
    const int percent = value.toString().toInt(&valid);
    return valid && choices.contains(percent) ? percent : DefaultPercent;
}

bool savePreference(const QString &key, const QVariant &value)
{
    QSettings settings;
    if (settings.value(key) == value)
        return settings.status() == QSettings::NoError;
    settings.setValue(key, value);
    settings.sync();
    return settings.status() == QSettings::NoError;
}

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

int Typography::applyStartupInterfaceScale()
{
    const int percent = savedPercent(QSettings().value(InterfaceScaleKey), InterfaceScaleChoices);
    if (percent == DefaultPercent)
        return percent;

    bool valid = false;
    const double externalScale = qgetenv("QT_SCALE_FACTOR").toDouble(&valid);
    const double baseScale = valid && std::isfinite(externalScale) && externalScale > 0
        ? externalScale : 1.0;
    const double scale = baseScale * (percent / 100.0);
    if (!std::isfinite(scale) || scale <= 0
        || !qputenv("QT_SCALE_FACTOR", QByteArray::number(scale, 'g', 12))) {
        return DefaultPercent;
    }
    return percent;
}

Typography::Typography(int activeInterfaceScalePercent, QObject *parent)
    : QObject(parent),
      m_systemFont(QApplication::font()),
      m_latinFallbacks(QFontDatabase::applicationFallbackFontFamilies(QChar::Script_Latin)),
      m_arabicFallbacks(QFontDatabase::applicationFallbackFontFamilies(QChar::Script_Arabic)),
      m_englishFonts(installedFamilies(QFontDatabase::Latin)),
      m_arabicFonts(installedFamilies(QFontDatabase::Arabic)),
      m_fontSizePercent(DefaultPercent),
      m_interfaceScalePercent(DefaultPercent),
      m_activeInterfaceScalePercent(activeInterfaceScalePercent)
{
    const QSettings settings;
    const auto fonts = settings.value(FontPreferencesKey).toMap();
    // Preserve an unavailable preference on disk so it can apply after the font is reinstalled.
    m_preferredEnglishFamily = fonts.value(QStringLiteral("englishFamily"), settings.value(EnglishFontKey)).toString();
    m_preferredArabicFamily = fonts.value(QStringLiteral("arabicFamily"), settings.value(ArabicFontKey)).toString();
    m_englishFamily = installedFamily(m_preferredEnglishFamily, m_englishFonts);
    m_arabicFamily = installedFamily(m_preferredArabicFamily, m_arabicFonts);
    m_fontSizePercent = savedPercent(fonts.value(QStringLiteral("sizePercent"), settings.value(FontSizeKey)),
                                     FontSizeChoices);
    m_interfaceScalePercent = savedPercent(settings.value(InterfaceScaleKey), InterfaceScaleChoices);
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
    if (m_fontSizePercent != DefaultPercent) {
        const double factor = m_fontSizePercent / 100.0;
        if (font.pixelSize() > 0)
            font.setPixelSize(qMax(1, qRound(font.pixelSize() * factor)));
        else if (font.pointSizeF() > 0)
            font.setPointSizeF(font.pointSizeF() * factor);
    }
    return font;
}

QFont Typography::previewFont(const QString &family) const
{
    const auto latin = installedFamily(family, m_englishFonts);
    return fontWithFamily(latin.isEmpty() ? installedFamily(family, m_arabicFonts) : latin);
}

QList<int> Typography::fontSizeChoices() const
{
    return FontSizeChoices;
}

QList<int> Typography::interfaceScaleChoices() const
{
    return InterfaceScaleChoices;
}

bool Typography::applyFontPreferences(const QString &englishFamily, const QString &arabicFamily, int sizePercent)
{
    const auto english = installedFamily(englishFamily, m_englishFonts);
    const auto arabic = installedFamily(arabicFamily, m_arabicFonts);
    if ((!englishFamily.isEmpty() && english.isEmpty())
        || (!arabicFamily.isEmpty() && arabic.isEmpty())
        || !FontSizeChoices.contains(sizePercent))
        return false;

    if (english == m_englishFamily && arabic == m_arabicFamily && sizePercent == m_fontSizePercent)
        return true;

    const auto preferredEnglish = english.isEmpty() && m_englishFamily.isEmpty() ? m_preferredEnglishFamily : english;
    const auto preferredArabic = arabic.isEmpty() && m_arabicFamily.isEmpty() ? m_preferredArabicFamily : arabic;
    const QVariantMap fonts{{QStringLiteral("englishFamily"), preferredEnglish},
                            {QStringLiteral("arabicFamily"), preferredArabic},
                            {QStringLiteral("sizePercent"), sizePercent}};
    if (!savePreference(FontPreferencesKey, fonts))
        return false;

    m_preferredEnglishFamily = preferredEnglish;
    m_preferredArabicFamily = preferredArabic;
    m_englishFamily = english;
    m_arabicFamily = arabic;
    m_fontSizePercent = sizePercent;
    applyInterfaceFont();
    emit fontChanged();
    return true;
}

bool Typography::setInterfaceScalePercent(int percent)
{
    if (!InterfaceScaleChoices.contains(percent) || !savePreference(InterfaceScaleKey, percent))
        return false;
    if (m_interfaceScalePercent != percent) {
        m_interfaceScalePercent = percent;
        emit interfaceScaleChanged();
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
