#include "Typography.h"

#include <QApplication>
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QLocale>
#include <QRawFont>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>

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
      m_fontSizePercent(DefaultPercent),
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
    m_interfaceScalePercent = savedPercent(settings.value(InterfaceScaleKey), MaximumInterfacePercent);
    applyInterfaceFont();
}

void Typography::refreshFontOptions()
{
    m_englishFontOptions = fontOptions(EnglishFonts, QFontDatabase::Latin);
    m_arabicFontOptions = fontOptions(ArabicFonts, QFontDatabase::Arabic);
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

    const QRawFont face(bytes, 16);
    const auto saveFont = [&]() -> QString {
        for (const auto script : {QFontDatabase::Latin, QFontDatabase::Arabic}) {
            const bool arabic = script == QFontDatabase::Arabic;
            const auto &catalog = arabic ? ArabicFonts : EnglishFonts;
            const auto &existing = arabic ? m_arabicFontOptions : m_englishFontOptions;
            for (const auto &font : catalog) {
                if (verifiedFontFamily(id, font, face, script).isEmpty())
                    continue;
                if (!installedFamily(font.name, existing).isEmpty())
                    return tr("This font is already available in Auralis.");
                const auto folder = privateFontFolder();
                if (folder.isEmpty() || QFileInfo(folder).isSymLink() || !QDir().mkpath(folder))
                    return tr("Could not save the font for Auralis.");
                const auto destination = privateFontPath(folder, font);
                if (QFileInfo(destination).isSymLink())
                    return tr("Could not save the font for Auralis.");
                QSaveFile copy(destination);
                if (!copy.open(QIODevice::WriteOnly) || copy.write(bytes) != bytes.size() || !copy.commit())
                    return tr("Could not save the font for Auralis.");
                return {};
            }
        }
        return tr("The file does not match a listed interface font or does not support its language.");
    };
    const auto problem = saveFont();
    if (!problem.isEmpty()) {
        QFontDatabase::removeApplicationFont(id);
        return problem;
    }
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
