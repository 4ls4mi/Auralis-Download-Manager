#include "Engine.h"
#include "Smoke.h"

#include <QAction>
#include <QApplication>
#include <QCryptographicHash>
#include <QCursor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLockFile>
#include <QMenu>
#include <QMessageBox>
#include <QMutex>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QSystemTrayIcon>

#include <cstring>
#include <memory>
#include <optional>

namespace {
void writeSmokeLog(QtMsgType, const QMessageLogContext &, const QString &message)
{
    static QMutex mutex;
    QMutexLocker lock(&mutex);
    const auto profile = qEnvironmentVariable("MDM_DATA_DIR");
    if (!profile.isEmpty() && QDir::isAbsolutePath(profile)) {
        QFile log(QDir(profile).filePath(QStringLiteral("qt-smoke-console.log")));
        if (log.open(QIODevice::WriteOnly | QIODevice::Append))
            log.write(message.toUtf8() + '\n');
    }
}

bool forwardToInstance(const QString &serverName, const QByteArray &message)
{
    QLocalSocket socket;
    socket.connectToServer(serverName, QIODevice::WriteOnly);
    if (!socket.waitForConnected(400))
        return false;
    socket.write(message);
    return socket.waitForBytesWritten(800);
}

void addBundledTools()
{
    const auto dir = QCoreApplication::applicationDirPath();
    if (QFileInfo::exists(QDir(dir).filePath(QStringLiteral("deno.exe"))))
        qputenv("PATH", QDir::toNativeSeparators(dir).toUtf8() + QDir::listSeparator().toLatin1() + qgetenv("PATH"));
}
}

int main(int argc, char **argv)
{
    for (int index = 1; index < argc; ++index) {
        if (std::strcmp(argv[index], "--engine-smoke") == 0) {
            qInstallMessageHandler(writeSmokeLog);
            qInfo("Smoke: constructing the Qt application.");
            break;
        }
    }
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Auralis Download Manager"));
    app.setOrganizationName(QStringLiteral("Auralis"));
    app.setApplicationVersion(QStringLiteral(AURALIS_VERSION));
    QIcon appIcon(QStringLiteral(":/auralis/auralis.ico"));
    if (appIcon.availableSizes().isEmpty())
        appIcon = QIcon(QStringLiteral(":/auralis/auralis.png"));
    app.setWindowIcon(appIcon);
    app.setQuitOnLastWindowClosed(false);

    const QStringList arguments = app.arguments();
    const bool smoke = arguments.contains(QStringLiteral("--engine-smoke"));
    if (smoke) {
        qInfo("Smoke: Qt platform initialized.");
        const QString profile = qEnvironmentVariable("MDM_DATA_DIR");
        if (profile.isEmpty() || !QDir::isAbsolutePath(profile)) {
            qCritical("Set an isolated, absolute MDM_DATA_DIR before running the engine smoke test.");
            return 2;
        }
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope,
                           QDir(profile).filePath(QStringLiteral("qt-settings")));
    }
    const bool exitRequest = arguments.contains(QStringLiteral("--exit")) || arguments.contains(QStringLiteral("/exit"));
    const bool startHidden = arguments.contains(QStringLiteral("--auralis-startup-minimized"));

    addBundledTools();
    // Qt's Direct3D 11 backend keeps transparent Windows swapchains stable.
    // Qt still accepts QSG_RHI_BACKEND=d3d12 for explicitly selected devices.
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QQuickWindow::setDefaultAlphaBuffer(true);

    // QML bindings must be destroyed before their native context object.
    std::optional<Engine> engineLifetime;
    QQmlApplicationEngine qml;
    Engine &engine = engineLifetime.emplace(&qml, startHidden, smoke);
    if (engine.dataDirectory().isEmpty()) {
        if (!smoke && !exitRequest)
            QMessageBox::critical(nullptr, app.applicationName(), QObject::tr("The bundled Rust downloader could not be opened. Reinstall Auralis."));
        return exitRequest ? 0 : 1;
    }

    const auto profileHash = QCryptographicHash::hash(QDir::cleanPath(engine.dataDirectory()).toUtf8(),
                                                       QCryptographicHash::Sha256).toHex().left(24);
    const QString serverName = QStringLiteral("AuralisQt-") + QString::fromLatin1(profileHash);
    const QString lockFile = QDir(QStandardPaths::writableLocation(QStandardPaths::TempLocation))
                                 .filePath(serverName + QStringLiteral(".lock"));
    QLockFile lock(lockFile);
    lock.setStaleLockTime(0);
    if (!lock.tryLock(300)) {
        const bool forwarded = forwardToInstance(serverName, exitRequest ? QByteArrayLiteral("exit\n")
                                                                         : QByteArrayLiteral("activate\n"));
        return forwarded ? 0 : 1;
    }
    if (exitRequest)
        return 0;

    QLocalServer local;
    local.setSocketOptions(QLocalServer::UserAccessOption);
    QLocalServer::removeServer(serverName);
    if (!local.listen(serverName))
        return 1;

    qml.rootContext()->setContextProperty(QStringLiteral("engine"), &engine);
    if (smoke) qInfo("Smoke: loading the Qt interface.");
    qml.loadFromModule(QStringLiteral("Auralis"), QStringLiteral("Main"));
    if (qml.rootObjects().isEmpty())
        return 1;
    if (smoke) qInfo("Smoke: Qt interface loaded.");
    auto *root = qml.rootObjects().first();
    auto *window = qobject_cast<QWindow *>(root);
    if (!window)
        return 1;

    const auto activate = [window] {
        if (!window->isVisible() || window->visibility() == QWindow::Minimized)
            window->showNormal();
        window->raise();
        window->requestActivate();
    };
    QObject::connect(&local, &QLocalServer::newConnection, &app, [&local, &engine, activate] {
        while (auto *socket = local.nextPendingConnection()) {
            QObject::connect(socket, &QLocalSocket::disconnected, socket, &QLocalSocket::deleteLater);
            const auto handle = [socket, &engine, activate] {
                if (!socket->canReadLine()) {
                    if (socket->bytesAvailable() > 64)
                        socket->disconnectFromServer();
                    return;
                }
                const auto command = socket->readLine(64).trimmed();
                if (command == "exit")
                    engine.requestQuit();
                else if (command == "activate")
                    activate();
                socket->disconnectFromServer();
            };
            QObject::connect(socket, &QLocalSocket::readyRead, socket, handle);
            handle();
        }
    });

    QObject::connect(&engine, &Engine::browserWindowRequested, root, [root, activate](const QString &target) {
        if (target == QStringLiteral("main")) {
            activate();
        } else if (target.startsWith(QStringLiteral("options:"))) {
            if (!QMetaObject::invokeMethod(root, "showBrowserSettings"))
                QMetaObject::invokeMethod(root, "showSettings");
        }
    });

    QMenu trayMenu;
    QSystemTrayIcon tray(app.windowIcon());
    QSystemTrayIcon progressTray(QIcon(QStringLiteral(":/auralis/auralis-progress.png")));
    QHash<qulonglong, QAction *> progressActions;
    if (engine.trayAvailable()) {
        tray.setToolTip(app.applicationName());
        QObject::connect(trayMenu.addAction(QObject::tr("Open Auralis")), &QAction::triggered, &app, activate);
        QObject::connect(trayMenu.addAction(QObject::tr("Add download")), &QAction::triggered, root,
            [root, activate] { activate(); QMetaObject::invokeMethod(root, "addDownload"); });
        QObject::connect(trayMenu.addAction(QObject::tr("Settings")), &QAction::triggered, root,
            [root] { QMetaObject::invokeMethod(root, "showSettings"); });
        auto *progressMenu = trayMenu.addMenu(QObject::tr("Hidden download windows"));
        progressMenu->menuAction()->setVisible(false);
        progressMenu->setToolTipsVisible(true);
        progressTray.setContextMenu(progressMenu);
        QObject::connect(&engine, &Engine::progressTrayItemsChanged, progressMenu,
            [root, progressMenu, &progressTray, &progressActions](const QVariantList &items) {
                QSet<qulonglong> currentIds;
                for (const auto &value : items) {
                    const auto item = value.toMap();
                    bool valid = false;
                    const auto id = item.value(QStringLiteral("id")).toULongLong(&valid);
                    if (!valid || !id || currentIds.contains(id))
                        continue;
                    currentIds.insert(id);
                    auto *action = progressActions.value(id);
                    if (!action) {
                        action = progressMenu->addAction(QString());
                        QObject::connect(action, &QAction::triggered, root, [root, id] {
                            QMetaObject::invokeMethod(root, "showDownload", Q_ARG(QVariant, QVariant::fromValue(id)));
                        });
                        progressActions.insert(id, action);
                    }
                    auto file = item.value(QStringLiteral("name")).toString();
                    const QString fullName = file;
                    if (file.size() > 70)
                        file = file.left(68) + QStringLiteral("…");
                    file.replace(QLatin1Char('&'), QStringLiteral("&&"));
                    const QString summary = item.value(QStringLiteral("summary")).toString();
                    action->setText(QObject::tr("%1 — %2").arg(file, summary));
                    action->setToolTip(QObject::tr("%1\n%2").arg(fullName, item.value(QStringLiteral("details")).toString()));
                }
                for (auto entry = progressActions.begin(); entry != progressActions.end();) {
                    if (currentIds.contains(entry.key())) {
                        ++entry;
                        continue;
                    }
                    auto *action = entry.value();
                    progressMenu->removeAction(action);
                    action->deleteLater();
                    entry = progressActions.erase(entry);
                }
                progressMenu->menuAction()->setVisible(!currentIds.isEmpty());
                if (currentIds.size() == 1) {
                    progressTray.setToolTip(progressActions.constBegin().value()->toolTip().left(127));
                } else {
                    progressTray.setToolTip(QObject::tr("Auralis — %1 hidden download windows").arg(currentIds.size()));
                }
                progressTray.setVisible(!currentIds.isEmpty());
            });
        QObject::connect(&progressTray, &QSystemTrayIcon::activated, progressMenu,
            [progressMenu](QSystemTrayIcon::ActivationReason reason) {
                if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick)
                    progressMenu->popup(QCursor::pos());
            });
        QObject::connect(&engine, &Engine::updateNotificationRequested, &tray, [&tray](const QString &version) {
            tray.showMessage(QObject::tr("Auralis update available"),
                             QObject::tr("Version %1 is ready to review in Auralis.").arg(version),
                             QSystemTrayIcon::Information);
        });
        QObject::connect(&tray, &QSystemTrayIcon::messageClicked, root, [root, activate] {
            activate();
            QMetaObject::invokeMethod(root, "showUpdates");
        });
        trayMenu.addSeparator();
        QObject::connect(trayMenu.addAction(QObject::tr("Exit")), &QAction::triggered, &engine,
            [&engine] { engine.requestQuit(); });
        tray.setContextMenu(&trayMenu);
        QObject::connect(&tray, &QSystemTrayIcon::activated, &app, [activate](QSystemTrayIcon::ActivationReason reason) {
            if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick)
                activate();
        });
        tray.show();
    }

    std::unique_ptr<EngineSmoke> test;
    if (smoke) {
        qputenv("MDM_DOWNLOADS", QFile::encodeName(engine.dataDirectory()));
        test = std::make_unique<EngineSmoke>(engine);
    }
    QTimer::singleShot(0, &engine, &Engine::start);
    if (smoke) qInfo("Smoke: starting the Qt event loop and Rust service.");
    const int code = app.exec();
    if (smoke) qInfo("Smoke: event loop finished with exit code %d.", code);
    return code;
}
