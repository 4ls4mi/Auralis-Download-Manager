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
const QStringList EnglishFonts{
    QStringLiteral("Talina"), QStringLiteral("Milkyway"), QStringLiteral("Mochi Boom"),
    QStringLiteral("Qilka"), QStringLiteral("Qurova")};
const QStringList ArabicFonts{
    QStringLiteral("Kidzhood Arabic"), QStringLiteral("Tinta Arabic"), QStringLiteral("Madani Arabic"),
    QStringLiteral("Mahameru Arabic"), QStringLiteral("Gumela Arabic"), QStringLiteral("Tufuli Arabic"),
    QStringLiteral("Lutfey Arabic")};
constexpr int MinimumPercent = 85;
constexpr int DefaultPercent = 100;
constexpr int MaximumFontPercent = 130;
constexpr int MaximumInterfacePercent = 150;

int savedPercent(const QVariant &value, int maximum)
{
    bool valid = false;
    const int percent = value.toString().toInt(&valid);
    return valid && percent >= MinimumPercent && percent <= maximum ? percent : DefaultPercent;
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

QString familyKey(QString name)
{
    name.remove(QLatin1Char(' '));
    name.remove(QLatin1Char('-'));
    name.remove(QLatin1Char('_'));
    return name.toCaseFolded();
}

QVariantList fontOptions(const QStringList &catalog, QFontDatabase::WritingSystem script)
{
    const auto installed = QFontDatabase::families(script);
    QVariantList options;
    for (const auto &name : catalog) {
        QString family;
        const auto key = familyKey(name);
        for (const auto &candidate : installed) {
            if (candidate.compare(name, Qt::CaseInsensitive) == 0) {
                family = candidate;
                break;
            }
            if (family.isEmpty() && familyKey(candidate) == key)
                family = candidate;
        }
        options.append(QVariantMap{{QStringLiteral("label"), name}, {QStringLiteral("available"), !family.isEmpty()},
                                   {QStringLiteral("value"), family.isEmpty() ? name : family}});
    }
    return options;
}

QString installedFamily(const QString &requested, const QVariantList &options)
{
    if (requested.isEmpty())
        return {};
    const auto key = familyKey(requested);
    for (const auto &value : options) {
        const auto option = value.toMap();
        const auto family = option.value(QStringLiteral("value")).toString();
        if (option.value(QStringLiteral("available")).toBool() && familyKey(family) == key)
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
    const int percent = savedPercent(QSettings().value(InterfaceScaleKey), MaximumInterfacePercent);
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
      m_englishFontOptions(fontOptions(EnglishFonts, QFontDatabase::Latin)),
      m_arabicFontOptions(fontOptions(ArabicFonts, QFontDatabase::Arabic)),
      m_fontSizePercent(DefaultPercent),
      m_interfaceScalePercent(DefaultPercent),
      m_activeInterfaceScalePercent(activeInterfaceScalePercent)
{
    const QSettings settings;
    const auto fonts = settings.value(FontPreferencesKey).toMap();
    // Preserve an unavailable preference on disk so it can apply after the font is reinstalled.
    m_preferredEnglishFamily = fonts.value(QStringLiteral("englishFamily"), settings.value(EnglishFontKey)).toString();
    m_preferredArabicFamily = fonts.value(QStringLiteral("arabicFamily"), settings.value(ArabicFontKey)).toString();
    m_englishFamily = installedFamily(m_preferredEnglishFamily, m_englishFontOptions);
    m_arabicFamily = installedFamily(m_preferredArabicFamily, m_arabicFontOptions);
    m_fontSizePercent = savedPercent(fonts.value(QStringLiteral("sizePercent"), settings.value(FontSizeKey)),
                                     MaximumFontPercent);
    m_interfaceScalePercent = savedPercent(settings.value(InterfaceScaleKey), MaximumInterfacePercent);
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
    const auto latin = installedFamily(family, m_englishFontOptions);
    return fontWithFamily(latin.isEmpty() ? installedFamily(family, m_arabicFontOptions) : latin);
}

int Typography::fontSizeMinimum() const { return MinimumPercent; }
int Typography::fontSizeMaximum() const { return MaximumFontPercent; }
int Typography::interfaceScaleMinimum() const { return MinimumPercent; }
int Typography::interfaceScaleMaximum() const { return MaximumInterfacePercent; }

bool Typography::applyFontPreferences(const QString &englishFamily, const QString &arabicFamily, int sizePercent)
{
    const auto english = installedFamily(englishFamily, m_englishFontOptions);
    const auto arabic = installedFamily(arabicFamily, m_arabicFontOptions);
    if ((!englishFamily.isEmpty() && english.isEmpty())
        || (!arabicFamily.isEmpty() && arabic.isEmpty())
        || sizePercent < MinimumPercent || sizePercent > MaximumFontPercent)
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
    if (percent < MinimumPercent || percent > MaximumInterfacePercent
        || !savePreference(InterfaceScaleKey, percent))
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
