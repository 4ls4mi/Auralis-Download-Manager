#include "LocalFiles.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QTemporaryFile>
#include <QUrl>

namespace {
constexpr qsizetype MaxPreferencesBytes = 4 * 1024 * 1024;

QVariantMap success(const QVariant &value)
{
    return {{QStringLiteral("result"), value}, {QStringLiteral("error"), QString()}};
}

QVariantMap failure(const QString &message)
{
    return {{QStringLiteral("result"), QVariant()}, {QStringLiteral("error"), message}};
}

QString localPath(const QVariant &value)
{
    if (value.typeId() == QMetaType::QUrl) {
        const auto url = value.toUrl();
        return url.isLocalFile() ? QDir::toNativeSeparators(url.toLocalFile()) : QString();
    }
    const auto text = value.toString();
    if (text.startsWith(QStringLiteral("file:"))) {
        const auto url = QUrl(text);
        return url.isLocalFile() ? QDir::toNativeSeparators(url.toLocalFile()) : QString();
    }
    return QDir::isAbsolutePath(text) ? QDir::toNativeSeparators(text) : QString();
}

QVariantMap readShareFile(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return failure(file.errorString());
    const auto bytes = file.read(MaxPreferencesBytes + 1);
    if (file.error() != QFileDevice::NoError)
        return failure(file.errorString());
    if (bytes.size() > MaxPreferencesBytes)
        return failure(QStringLiteral("The settings file exceeds 4 MB."));
    QJsonParseError error;
    const auto document = QJsonDocument::fromJson(bytes, &error);
    if (!document.isObject())
        return failure(QStringLiteral("Choose a valid Auralis JSON file."));
    return success(document.object().toVariantMap());
}

QVariantMap writeShareFile(const QString &path, const QVariant &value)
{
    const auto document = QJsonDocument::fromVariant(value);
    if (!document.isObject())
        return failure(QStringLiteral("The settings to export are invalid."));
    const auto bytes = document.toJson();
    if (bytes.size() > MaxPreferencesBytes)
        return failure(QStringLiteral("The settings file exceeds 4 MB."));
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit())
        return failure(file.errorString());
    return success(QVariantMap{{QStringLiteral("path"), path}});
}

QVariantMap prepareFullBackup(const QVariantMap &command, const QDir &profile)
{
    const auto appearance = command.value(QStringLiteral("appearance")).toMap();
    const auto startup = command.value(QStringLiteral("startup")).toMap();
    const auto mode = startup.value(QStringLiteral("mode")).toString();
    if (mode != QStringLiteral("window") && mode != QStringLiteral("minimized"))
        return failure(QStringLiteral("The Windows startup settings are unavailable."));
    if (!profile.mkpath(QStringLiteral("backup-ui")))
        return failure(QStringLiteral("Could not prepare the private backup folder."));
    const auto document = QJsonDocument::fromVariant(QVariantMap{
        {QStringLiteral("appearance"), appearance},
        {QStringLiteral("startup"), startup},
    });
    const auto bytes = document.toJson(QJsonDocument::Compact);
    if (bytes.size() > MaxPreferencesBytes)
        return failure(QStringLiteral("The settings file exceeds 4 MB."));
    QTemporaryFile manifest(profile.filePath(QStringLiteral("backup-ui/auralis-qt-backup-XXXXXX.json")));
    if (!manifest.open() || manifest.write(bytes) != bytes.size() || !manifest.flush())
        return failure(manifest.errorString());
    manifest.setAutoRemove(false);
    return success(QVariantMap{{QStringLiteral("path"), QDir::toNativeSeparators(manifest.fileName())}});
}

QVariantMap discardBackupManifest(const QString &path, const QDir &profile)
{
    const QFileInfo file(path);
    const auto folder = QDir::cleanPath(profile.filePath(QStringLiteral("backup-ui")));
    if (QDir::cleanPath(file.absolutePath()) != folder || file.isSymLink()
        || !file.fileName().startsWith(QStringLiteral("auralis-qt-backup-"))
        || file.suffix() != QStringLiteral("json"))
        return failure(QStringLiteral("The temporary backup file is invalid."));
    if (!file.exists())
        return success(true);
    QFile manifest(path);
    return manifest.remove() ? success(true) : failure(manifest.errorString());
}
}

QVariantMap requestLocalFile(const QVariantMap &command, const QString &dataDirectory)
{
    const auto action = command.value(QStringLiteral("local")).toString();
    const auto path = localPath(command.value(QStringLiteral("file")));
    const QDir profile(dataDirectory);

    if (action == QStringLiteral("prepareFullBackup"))
        return prepareFullBackup(command, profile);
    if (path.isEmpty())
        return failure(QStringLiteral("Choose a local file or folder."));
    if (action == QStringLiteral("discardBackupManifest"))
        return discardBackupManifest(path, profile);
    if (action == QStringLiteral("readShareFile"))
        return readShareFile(path);
    if (action == QStringLiteral("writeShareFile"))
        return writeShareFile(path, command.value(QStringLiteral("data")));
    if (action == QStringLiteral("chooseRestoreTarget")) {
        if (!QFileInfo(path).isDir())
            return failure(QStringLiteral("Choose an existing folder for the restored downloads."));
        const QDir folder(path);
        const auto base = QStringLiteral("Auralis Restored Downloads");
        for (int index = 1; index <= 10000; ++index) {
            const auto name = index == 1 ? base : QStringLiteral("%1 (%2)").arg(base).arg(index);
            const auto target = folder.filePath(name);
            const QFileInfo candidate(target);
            if (!candidate.exists() && !candidate.isSymLink())
                return success(QVariantMap{{QStringLiteral("path"), QDir::toNativeSeparators(target)}});
        }
        return failure(QStringLiteral("Could not choose a free location for the restored downloads."));
    }
    return failure(QStringLiteral("Unsupported local files operation."));
}
