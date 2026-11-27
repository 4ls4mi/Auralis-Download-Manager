#include "Typography.h"

#include <QApplication>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QLocale>
#include <QPainterPath>
#include <QRawFont>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>

#include <algorithm>
#include <cmath>

namespace {
const auto EnglishFontKey = QStringLiteral("Typography/englishFamily");
const auto ArabicFontKey = QStringLiteral("Typography/arabicFamily");
const auto FontSizeKey = QStringLiteral("Typography/fontSizePercent");
const auto FontPreferencesKey = QStringLiteral("Typography/fontPreferences");
const auto InterfaceScaleKey = QStringLiteral("Typography/interfaceScalePercent");
struct FontSource
{
    QString name;
    QString fileStem;
    QStringList aliases;
};

// The archive names and family names in the supplied files are recorded in
// assets/fonts/SOURCES.md. Keep preferred typographic names before style aliases.
const QList<FontSource> EnglishFonts{
    {QStringLiteral("Arial"), {}, {}},
    {QStringLiteral("Segoe UI"), {}, {}},
    {QStringLiteral("Aptos"), {}, {}},
    {QStringLiteral("Calibri"), {}, {}},
    {QStringLiteral("Tahoma"), {}, {}},
    {QStringLiteral("Verdana"), {}, {}},
    {QStringLiteral("Georgia"), {}, {}},
    {QStringLiteral("Trebuchet MS"), {}, {}},
    {QStringLiteral("Talina"), QStringLiteral("talina-demo"), {QStringLiteral("Talina DEMO")}},
    {QStringLiteral("Milkyway"), QStringLiteral("milkyway"), {}},
    {QStringLiteral("Mochi Boom"), QStringLiteral("mochi-boom-demo"),
        {QStringLiteral("Mochi Boom DEMO"), QStringLiteral("Mochi Boom DEMO Extrude")}},
    {QStringLiteral("Qilka"), QStringLiteral("qilka"), {}},
    {QStringLiteral("Qurova"), QStringLiteral("qurova-demo"),
        {QStringLiteral("Qurova DEMO"), QStringLiteral("Qurova DEMO Light"),
         QStringLiteral("Qurova DEMO Med"), QStringLiteral("Qurova DEMO SemBd")}},
};
const QList<FontSource> ArabicFonts{
    {QStringLiteral("Arial"), {}, {}},
    {QStringLiteral("Segoe UI"), {}, {}},
    {QStringLiteral("Tahoma"), {}, {}},
    {QStringLiteral("Aptos"), {}, {}},
    {QStringLiteral("Noto Naskh Arabic"), {}, {}},
    {QStringLiteral("Times New Roman"), {}, {}},
    {QStringLiteral("Kidzhood Arabic"), QStringLiteral("kidzhood-arabic-demo"),
        {QStringLiteral("Kidzhood Arabic DEMO"), QStringLiteral("Kidzhood Arabic DEMO Light")}},
    {QStringLiteral("Tinta Arabic"), QStringLiteral("tinta-arabic"),
        {QStringLiteral("Tinta Arabic Light")}},
    {QStringLiteral("Madani Arabic"), QStringLiteral("madani-arabic-demo"),
        {QStringLiteral("Madani Arabic DEMO"), QStringLiteral("Madani Arabic DEMO Black"),
         QStringLiteral("Madani Arabic DEMO Thin")}},
    {QStringLiteral("Mahameru Arabic"), QStringLiteral("mahameru-arabic-demo"),
        {QStringLiteral("Mahameru Arabic DEMO"), QStringLiteral("Mahameru Arabic DEMO Black"),
         QStringLiteral("Mahameru Arabic DEMO Thin")}},
    {QStringLiteral("Gumela Arabic"), QStringLiteral("gumela-arabic-demo"),
        {QStringLiteral("Gumela Arabic DEMO"), QStringLiteral("Gumela Arabic Light")}},
    {QStringLiteral("Tufuli Arabic"), QStringLiteral("tufuli-arabic-demo"),
        {QStringLiteral("Tufuli Arabic DEMO")}},
    {QStringLiteral("Lutfey Arabic"), QStringLiteral("lutfey-arabic-demo"),
        {QStringLiteral("Lutfey Arabic DEMO"), QStringLiteral("Lutfey Arabic DEMO Outline")}},
};
constexpr int MinimumPercent = 85;
constexpr int DefaultPercent = 100;
constexpr int MaximumFontPercent = 130;
constexpr int MaximumInterfacePercent = 150;
constexpr qint64 MaximumFontBytes = 16 * 1024 * 1024;
constexpr std::array NumeralStarts{0x0030, 0x0660, 0x06f0};

int numeralRange(QChar character)
{
    for (size_t index = 0; index < NumeralStarts.size(); ++index) {
        const int digit = character.unicode() - NumeralStarts[index];
        if (digit >= 0 && digit < 10)
            return int(index);
    }
    return -1;
}

QRawFont numeralFace(const QString &family)
{
    QFont font(family);
    font.setPixelSize(24);
    font.setStyleStrategy(QFont::NoFontMerging);
    return QRawFont::fromFont(font);
}

bool supportsNumeralRange(const QRawFont &face, int first)
{
    if (!face.isValid())
        return false;
    QString digits;
    for (int index = 0; index < 10; ++index)
        digits.append(QChar(ushort(first + index)));
    const auto glyphs = face.glyphIndexesForString(digits);
    if (glyphs.size() != 10)
        return false;
    QList<QPainterPath> outlines;
    for (const auto glyph : glyphs) {
        if (glyph == 0)
            return false;
        auto outline = face.pathForGlyph(glyph);
        // Some demo faces map each digit to a different glyph ID that draws
        // the same placeholder. Coverage alone would count those as usable.
        if (outline.isEmpty() || outlines.contains(outline))
            return false;
        outlines.append(std::move(outline));
    }
    return true;
}

std::array<QString, 3> numeralFallbacks(const QFont &system)
{
    auto candidates = system.families() + QFontDatabase::systemFont(QFontDatabase::GeneralFont).families();
    candidates += {QStringLiteral("Segoe UI"), QStringLiteral("Arial"), QStringLiteral("Tahoma"),
                   QStringLiteral("Geeza Pro"), QStringLiteral("Noto Sans Arabic"),
                   QStringLiteral("DejaVu Sans")};
    candidates += QFontDatabase::families(QFontDatabase::Arabic);
    candidates += QFontDatabase::families(QFontDatabase::Latin);
    candidates.removeDuplicates();
    std::array<QString, 3> fallbacks;
    for (const auto &candidate : candidates) {
        if (candidate.isEmpty() || !QFontDatabase::hasFamily(candidate))
            continue;
        const auto face = numeralFace(candidate);
        for (size_t index = 0; index < fallbacks.size(); ++index) {
            if (fallbacks[index].isEmpty() && supportsNumeralRange(face, NumeralStarts[index]))
                fallbacks[index] = face.familyName();
        }
        if (!fallbacks[0].isEmpty() && !fallbacks[1].isEmpty() && !fallbacks[2].isEmpty())
            break;
    }
    return fallbacks;
}

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

QString recognizedFamily(const FontSource &font, const QStringList &families)
{
    const auto names = QStringList{font.name} + font.aliases;
    for (const auto &name : names) {
        const auto key = familyKey(name);
        for (const auto &family : families) {
            if (familyKey(family) == key)
                return family;
        }
    }
    return {};
}

bool supportsScript(const QRawFont &font, QFontDatabase::WritingSystem script)
{
    if (!font.isValid())
        return false;
    const auto sample = script == QFontDatabase::Arabic ? QStringView(u"العربية") : QStringView(u"AZaz");
    for (const auto character : sample) {
        if (!font.supportsCharacter(character))
            return false;
    }
    return true;
}

QVariantList fontOptions(const QList<FontSource> &catalog, QFontDatabase::WritingSystem script)
{
    const auto installed = QFontDatabase::families();
    QVariantList options;
    for (const auto &font : catalog) {
        auto family = recognizedFamily(font, installed);
        if (!family.isEmpty()) {
            const auto face = QRawFont::fromFont(QFont(family));
            if (recognizedFamily(font, {face.familyName()}).isEmpty() || !supportsScript(face, script))
                family.clear();
        }
        options.append(QVariantMap{
            {QStringLiteral("label"), font.name},
            {QStringLiteral("available"), !family.isEmpty()},
            {QStringLiteral("bundled"), !font.fileStem.isEmpty()},
            {QStringLiteral("value"), family.isEmpty() ? font.name : family}});
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
        if (option.value(QStringLiteral("available")).toBool()
            && (familyKey(family) == key || familyKey(option.value(QStringLiteral("label")).toString()) == key))
            return family;
    }
    return {};
}

QString privateFontFolder()
{
    const auto profile = qEnvironmentVariable("MDM_DATA_DIR");
    if (!profile.isEmpty())
        return QDir::isAbsolutePath(profile) ? QDir(profile).filePath(QStringLiteral("qt-fonts")) : QString();
    const auto root = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    return root.isEmpty() ? QString() : QDir(root).filePath(QStringLiteral("fonts"));
}

QString privateFontPath(const QString &directory, const FontSource &font)
{
    return QDir(directory).filePath(font.fileStem + QStringLiteral(".font"));
}

QByteArray readFontFile(const QString &path)
{
    const QFileInfo info(path);
    if (!info.isFile() || info.size() > MaximumFontBytes)
        return {};
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    const auto bytes = file.read(MaximumFontBytes + 1);
    const bool sfnt = bytes.startsWith("OTTO") || bytes.startsWith(QByteArrayLiteral("\0\x01\0\0"));
    return file.error() == QFileDevice::NoError && bytes.size() <= MaximumFontBytes && sfnt
        ? bytes : QByteArray();
}

QString verifiedFontFamily(int id, const FontSource &font, const QRawFont &face,
                           QFontDatabase::WritingSystem script)
{
    const auto family = recognizedFamily(font, QFontDatabase::applicationFontFamilies(id));
    return !family.isEmpty() && supportsScript(face, script) ? family : QString();
}

void loadFonts(const QStringList &directories, const QList<FontSource> &catalog,
               QFontDatabase::WritingSystem script)
{
    for (const auto &font : catalog) {
        if (font.fileStem.isEmpty())
            continue;
        for (const auto &directory : directories) {
            const auto path = privateFontPath(directory, font);
            if (QFileInfo(path).isSymLink())
                continue;
            const auto bytes = readFontFile(path);
            if (bytes.isEmpty())
                continue;
            const int id = QFontDatabase::addApplicationFontFromData(bytes);
            if (id < 0)
                continue;
            if (!verifiedFontFamily(id, font, QRawFont(bytes, 16), script).isEmpty())
                break;
            QFontDatabase::removeApplicationFont(id);
        }
    }
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
    return savedPercent(QSettings().value(InterfaceScaleKey), MaximumInterfacePercent);
}

Typography::Typography(int activeInterfaceScalePercent, QObject *parent)
    : QObject(parent),
      m_systemFont(QApplication::font()),
      m_latinFallbacks(QFontDatabase::applicationFallbackFontFamilies(QChar::Script_Latin)),
      m_arabicFallbacks(QFontDatabase::applicationFallbackFontFamilies(QChar::Script_Arabic)),
      m_numeralFamilies(numeralFallbacks(m_systemFont)),
      m_fontSizePercent(DefaultPercent),
      m_defaultWeight(QFont::Normal),
      m_interfaceScalePercent(DefaultPercent),
      m_activeInterfaceScalePercent(activeInterfaceScalePercent)
{
    const auto bundled = QDir(QCoreApplication::applicationDirPath()).filePath(QStringLiteral("interface-fonts"));
    QStringList fontDirectories{privateFontFolder(), bundled};
    fontDirectories.removeIf([](const QString &folder) {
        return folder.isEmpty() || !QFileInfo(folder).isDir() || QFileInfo(folder).isSymLink();
    });
    loadFonts(fontDirectories, EnglishFonts, QFontDatabase::Latin);
    loadFonts(fontDirectories, ArabicFonts, QFontDatabase::Arabic);
    loadImportedFonts();
    refreshFontOptions();
    const QSettings settings;
    const auto fonts = settings.value(FontPreferencesKey).toMap();
    // Preserve an unavailable preference on disk so it can apply after the font is reinstalled.
    m_preferredEnglishFamily = fonts.value(QStringLiteral("englishFamily"), settings.value(EnglishFontKey)).toString();
    m_preferredArabicFamily = fonts.value(QStringLiteral("arabicFamily"), settings.value(ArabicFontKey)).toString();
    m_englishFamily = installedFamily(m_preferredEnglishFamily, m_englishFontOptions);
    m_arabicFamily = installedFamily(m_preferredArabicFamily, m_arabicFontOptions);
    m_fontSizePercent = savedPercent(fonts.value(QStringLiteral("sizePercent"), settings.value(FontSizeKey)),
                                     MaximumFontPercent);
    const int savedWeight = fonts.value(QStringLiteral("weight"), QFont::Normal).toInt();
    m_defaultWeight = savedWeight >= QFont::Thin && savedWeight <= QFont::Black
        ? savedWeight : QFont::Normal;
    m_interfaceScalePercent = savedPercent(settings.value(InterfaceScaleKey), MaximumInterfacePercent);
    applyInterfaceFont();
}

void Typography::refreshFontOptions()
{
    m_numeralCoverage.clear();
    m_englishFontOptions = fontOptions(EnglishFonts, QFontDatabase::Latin);
    m_arabicFontOptions = fontOptions(ArabicFonts, QFontDatabase::Arabic);
    const auto appendImported = [this](QVariantList &options) {
        for (const auto &family : m_importedFamilies) {
            const auto key = familyKey(family);
            const bool listed = std::any_of(options.cbegin(), options.cend(), [&key](const QVariant &entry) {
                const auto option = entry.toMap();
                return option.value(QStringLiteral("available")).toBool()
                    && familyKey(option.value(QStringLiteral("value")).toString()) == key;
            });
            if (!listed)
                options.append(QVariantMap{{QStringLiteral("label"), family},
                                           {QStringLiteral("available"), true},
                                           {QStringLiteral("value"), family}});
        }
    };
    appendImported(m_englishFontOptions);
    appendImported(m_arabicFontOptions);
}

void Typography::loadImportedFonts()
{
    const auto folder = privateFontFolder();
    if (folder.isEmpty() || QFileInfo(folder).isSymLink())
        return;
    const QDir directory(folder);
    const auto files = directory.entryInfoList({QStringLiteral("*.font")},
                                                QDir::Files | QDir::NoSymLinks, QDir::Name);
    for (const auto &entry : files) {
        const auto bytes = readFontFile(entry.absoluteFilePath());
        if (bytes.isEmpty())
            continue;
        const int id = QFontDatabase::addApplicationFontFromData(bytes);
        if (id < 0)
            continue;
        const auto families = QFontDatabase::applicationFontFamilies(id);
        const auto family = families.isEmpty() ? QString() : families.constFirst();
        if (family.isEmpty()) {
            QFontDatabase::removeApplicationFont(id);
            continue;
        }
        const auto key = familyKey(family);
        if (std::none_of(m_importedFamilies.cbegin(), m_importedFamilies.cend(), [&key](const QString &known) {
                return familyKey(known) == key;
            }))
            m_importedFamilies.append(family);
    }
}

QString Typography::importFont(const QUrl &file)
{
    const auto path = file.toLocalFile();
    const auto suffix = QFileInfo(path).suffix().toLower();
    if (!file.isLocalFile() || (suffix != QStringLiteral("ttf") && suffix != QStringLiteral("otf")))
        return tr("Choose a local TTF or OTF font file.");
    const auto bytes = readFontFile(path);
    if (bytes.isEmpty())
        return tr("Could not read this font. Choose a valid TTF or OTF file up to 16 MB.");
    const int id = QFontDatabase::addApplicationFontFromData(bytes);
    if (id < 0)
        return tr("Could not load the selected font file.");

    const auto families = QFontDatabase::applicationFontFamilies(id);
    const auto family = families.isEmpty() ? QString() : families.constFirst();
    if (family.isEmpty()) {
        QFontDatabase::removeApplicationFont(id);
        return tr("Could not find a usable font family in this file.");
    }
    const auto key = familyKey(family);
    if (std::any_of(m_importedFamilies.cbegin(), m_importedFamilies.cend(), [&key](const QString &known) {
            return familyKey(known) == key;
        })) {
        QFontDatabase::removeApplicationFont(id);
        return tr("This font is already available in Auralis.");
    }
    const auto folder = privateFontFolder();
    if (folder.isEmpty() || QFileInfo(folder).isSymLink() || !QDir().mkpath(folder)) {
        QFontDatabase::removeApplicationFont(id);
        return tr("Could not save the font for Auralis.");
    }
    const auto filename = QString::fromLatin1(QCryptographicHash::hash(bytes, QCryptographicHash::Sha256).toHex())
        + QStringLiteral(".font");
    const auto destination = QDir(folder).filePath(filename);
    if (QFileInfo(destination).isSymLink()) {
        QFontDatabase::removeApplicationFont(id);
        return tr("Could not save the font for Auralis.");
    }
    QSaveFile copy(destination);
    if (!copy.open(QIODevice::WriteOnly) || copy.write(bytes) != bytes.size() || !copy.commit()) {
        QFontDatabase::removeApplicationFont(id);
        return tr("Could not save the font for Auralis.");
    }
    m_importedFamilies.append(family);
    refreshFontOptions();
    emit fontOptionsChanged();
    return {};
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
    font.setWeight(static_cast<QFont::Weight>(m_defaultWeight));
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

uint Typography::numeralCoverage(const QString &family) const
{
    const auto effective = family.isEmpty() ? m_systemFont.family() : family;
    const auto existing = m_numeralCoverage.constFind(effective);
    if (existing != m_numeralCoverage.constEnd())
        return existing.value();
    const auto face = numeralFace(effective);
    uint mask = 0;
    for (size_t index = 0; index < NumeralStarts.size(); ++index) {
        if (supportsNumeralRange(face, NumeralStarts[index]))
            mask |= 1u << index;
    }
    m_numeralCoverage.insert(effective, mask);
    return mask;
}

QString Typography::numeralMarkup(const QString &text, const QString &family) const
{
    QString markup;
    qsizetype start = 0;
    QString currentFallback;
    uint coverage = 0;
    bool coverageKnown = false;
    bool substituted = false;
    const auto append = [&](qsizetype end) {
        const auto part = text.mid(start, end - start).toHtmlEscaped();
        if (currentFallback.isEmpty()) {
            markup += part;
        } else {
            markup += QStringLiteral("<font face=\"%1\">%2</font>")
                .arg(currentFallback.toHtmlEscaped(), part);
            substituted = true;
        }
        start = end;
    };

    for (qsizetype position = 0; position < text.size(); ++position) {
        QString fallback;
        const int range = numeralRange(text[position]);
        if (range >= 0) {
            if (!coverageKnown) {
                coverage = numeralCoverage(family);
                coverageKnown = true;
            }
            if ((coverage & (1u << range)) == 0)
                fallback = m_numeralFamilies[range];
        }
        if (fallback != currentFallback) {
            append(position);
            currentFallback = fallback;
        }
    }
    if (!substituted && currentFallback.isEmpty())
        return {};
    append(text.size());
    return QStringLiteral("<div style=\"white-space:pre-wrap;margin:0\">%1</div>").arg(markup);
}

QString Typography::numeralInputFamily(const QString &family) const
{
    const auto zero = QLocale().zeroDigit();
    const int range = zero.isEmpty() ? 0 : qMax(0, numeralRange(zero.front()));
    const uint needed = 1u | (1u << range);
    if ((numeralCoverage(family) & needed) == needed)
        return family;
    for (const auto &fallback : m_numeralFamilies) {
        if (!fallback.isEmpty() && (numeralCoverage(fallback) & needed) == needed)
            return fallback;
    }
    return m_numeralFamilies[range].isEmpty() ? family : m_numeralFamilies[range];
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
                            {QStringLiteral("sizePercent"), sizePercent},
                            {QStringLiteral("weight"), m_defaultWeight}};
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
    if (percent < MinimumPercent || percent > MaximumInterfacePercent)
        return false;
    if (m_interfaceScalePercent == percent)
        return true;
    if (!savePreference(InterfaceScaleKey, percent))
        return false;

    m_interfaceScalePercent = percent;
    emit interfaceScaleChanged();
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
