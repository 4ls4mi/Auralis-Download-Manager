#include "Engine.h"
#include "Smoke.h"

#include <QAction>
#include <QApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QIcon>
#include <QLocalServer>
#include <QLocalSocket>
#include <QLockFile>
#include <QMenu>
#include <QMessageBox>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSettings>
#include <QStandardPaths>
#include <QSystemTrayIcon>

#include <memory>
#include <optional>

#ifdef Q_OS_WIN
#include <d3d12.h>
#endif

namespace {
bool forwardToInstance(const QString &serverName, const QByteArray &message)
{
    QLocalSocket socket;
    socket.connectToServer(serverName, QIODevice::WriteOnly);
    if (!socket.waitForConnected(400))
        return false;
    socket.write(message);
    return socket.waitForBytesWritten(800);
}

void chooseRenderer()
{
#ifdef Q_OS_WIN
    if (qEnvironmentVariableIsSet("QSG_RHI_BACKEND"))
        return;
    const HRESULT detected = D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_11_0, __uuidof(ID3D12Device), nullptr);
    QQuickWindow::setGraphicsApi(SUCCEEDED(detected) ? QSGRendererInterface::Direct3D12
                                                    : QSGRendererInterface::Direct3D11);
#endif
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
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("Auralis Download Manager"));
    app.setOrganizationName(QStringLiteral("Auralis"));
    app.setApplicationVersion(QStringLiteral(AURALIS_VERSION));
    app.setWindowIcon(QIcon(QStringLiteral(":/auralis/auralis.png")));
    app.setQuitOnLastWindowClosed(false);

    const QStringList arguments = app.arguments();
    const bool smoke = arguments.contains(QStringLiteral("--engine-smoke"));
    if (smoke) {
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
    chooseRenderer();
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
    qml.loadFromModule(QStringLiteral("Auralis"), QStringLiteral("Main"));
    if (qml.rootObjects().isEmpty())
        return 1;
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
    if (engine.trayAvailable()) {
        tray.setToolTip(app.applicationName());
        QObject::connect(trayMenu.addAction(QObject::tr("Open Auralis")), &QAction::triggered, &app, activate);
        QObject::connect(trayMenu.addAction(QObject::tr("Add download")), &QAction::triggered, root,
            [root, activate] { activate(); QMetaObject::invokeMethod(root, "addDownload"); });
        QObject::connect(trayMenu.addAction(QObject::tr("Settings")), &QAction::triggered, root,
            [root] { QMetaObject::invokeMethod(root, "showSettings"); });
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
    return app.exec();
}
