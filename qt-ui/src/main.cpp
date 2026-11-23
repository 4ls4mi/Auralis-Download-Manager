#include "Engine.h"
#include "Smoke.h"

#include <QAction>
#include <QActionGroup>
#include <QApplication>
#include <QClipboard>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QCursor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
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
#include <QTimer>

#include <cstring>
#include <functional>
#include <memory>
#include <optional>

#ifdef Q_OS_WIN
#include <qt_windows.h>
#include <shellapi.h>
#include <shlobj.h>
#endif

namespace {
constexpr auto InstanceMessageLimit = 64;
constexpr auto InstanceConnectionLimit = 16;
constexpr auto InstanceReadTimeoutMs = 3000;

#ifdef Q_OS_WIN
void refreshTaskbarIcon()
{
    const auto executable = QDir::toNativeSeparators(QCoreApplication::applicationFilePath()).toStdWString();
    const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(initialized)) {
        SHFILEINFOW fileInfo{};
        if (SHGetFileInfoW(executable.c_str(), 0, &fileInfo, sizeof(fileInfo), SHGFI_SYSICONINDEX))
            SHUpdateImageW(executable.c_str(), 0, 0, fileInfo.iIcon);
        CoUninitialize();
    }
    SHChangeNotify(SHCNE_UPDATEITEM, SHCNF_PATHW | SHCNF_FLUSHNOWAIT, executable.c_str(), nullptr);
}
#endif

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

class TrayMenus final : public QObject
{
public:
    TrayMenus(Engine &engine, QObject &root, const QIcon &icon, std::function<void()> activate, bool registerIcons)
        : m_engine(engine), m_root(root), m_activate(std::move(activate)), m_mainIcon(icon),
          m_progressIcon(QIcon(QStringLiteral(":/auralis/auralis-progress.png")))
    {
        connect(&m_mainIcon, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
            if (reason == QSystemTrayIcon::Context)
                queuePopup(false);
            else if (reason == QSystemTrayIcon::Trigger || reason == QSystemTrayIcon::DoubleClick)
                m_activate();
        });
        connect(&m_progressIcon, &QSystemTrayIcon::activated, this, [this](QSystemTrayIcon::ActivationReason reason) {
            if (reason == QSystemTrayIcon::Context || reason == QSystemTrayIcon::Trigger
                || reason == QSystemTrayIcon::DoubleClick)
                queuePopup(true);
        });

        if (!registerIcons)
            return;
        connect(&m_engine, &Engine::trayDownloadItemsChanged, this, &TrayMenus::updateProgressIcon);
        connect(&m_engine, &Engine::updateNotificationRequested, this, [this](const QString &version) {
            m_mainIcon.showMessage(tr("Auralis update available"),
                                   tr("Version %1 is ready to review in Auralis.").arg(version),
                                   QSystemTrayIcon::Information);
        });
        connect(&m_mainIcon, &QSystemTrayIcon::messageClicked, this, [this] {
            m_activate();
            QMetaObject::invokeMethod(&m_root, "showUpdates");
        });
        m_mainIcon.setToolTip(QCoreApplication::applicationName());
        m_mainIcon.show();
        updateProgressIcon(downloadSnapshot());
    }

    void exercise(std::function<void(bool)> finish)
    {
        const QVariantList downloads = m_engine.dashboard().value(QStringLiteral("downloads")).toList();
        for (const auto &value : downloads) {
            const auto item = value.toMap();
            if (item.value(QStringLiteral("status")).toString() == QStringLiteral("Downloading")) {
                m_smokeDownloadId = item.value(QStringLiteral("id")).toULongLong();
                break;
            }
        }
        if (!m_smokeDownloadId) {
            finish(false);
            return;
        }

        m_mainIcon.activated(QSystemTrayIcon::Context);
        QTimer::singleShot(900, this, [this, finish = std::move(finish)]() mutable {
            const auto visible = m_popup && m_popup->isVisible();
            const bool hasOpen = visible && hasAction(*m_popup, tr("Open Auralis Download Manager"));
            const bool hasDownloads = visible && hasDownload(m_popup->actions(), m_smokeDownloadId);
            const bool hasSettings = visible && hasAction(*m_popup, tr("Settings"));
            if (m_popup)
                m_popup->close();
            if (!hasOpen || !hasDownloads || !hasSettings) {
                qWarning("Smoke: application tray could not show its commands and active download.");
                m_smokeDownloadId = 0;
                finish(false);
                return;
            }
            m_progressIcon.activated(QSystemTrayIcon::Context);
            QTimer::singleShot(900, this, [this, finish = std::move(finish)] {
                const bool passed = m_popup && m_popup->isVisible()
                    && hasDownload(m_popup->actions(), m_smokeDownloadId)
                    && !hasAction(*m_popup, tr("Settings"));
                if (m_popup)
                    m_popup->close();
                if (!passed)
                    qWarning("Smoke: transfer tray could not show the active download.");
                m_smokeDownloadId = 0;
                finish(passed);
            });
        });
    }

private:
    static bool hasAction(const QMenu &menu, const QString &text)
    {
        for (const auto *action : menu.actions()) {
            if (action->text() == text)
                return true;
        }
        return false;
    }

    static bool hasDownload(const QList<QAction *> &actions, qulonglong id)
    {
        for (const auto *action : actions) {
            if (action->data().toULongLong() == id
                || (action->menu() && hasDownload(action->menu()->actions(), id)))
                return true;
        }
        return false;
    }

    QVariantList downloadSnapshot() const
    {
        const QVariant items = m_root.property("trayDownloadItems");
        if (items.metaType() == QMetaType::fromType<QJSValue>())
            return items.value<QJSValue>().toVariant().toList();
        return items.toList();
    }

    void updateProgressIcon(const QVariantList &items)
    {
        int hidden = 0;
        QString tip;
        for (const auto &value : items) {
            const auto item = value.toMap();
            if (item.value(QStringLiteral("hidden")).toBool()) {
                ++hidden;
                tip = tr("%1\n%2").arg(item.value(QStringLiteral("name")).toString(),
                                        item.value(QStringLiteral("details")).toString());
            }
        }
        if (hidden == 0) {
            m_progressIcon.hide();
            return;
        }
        tip = hidden == 1 ? tip.left(127) : tr("Auralis — %1 hidden download windows").arg(hidden);
        if (m_progressIcon.toolTip() != tip)
            m_progressIcon.setToolTip(tip);
        m_progressIcon.show();
    }

    void queuePopup(bool progress)
    {
        const auto position = QCursor::pos();
        // Explorer's tray callback can run inside a native menu dispatch. Create
        // and show a private Qt menu after the callback has returned.
        QTimer::singleShot(0, this, [this, progress, position] {
            if (m_popup)
                m_popup->close();
            m_popup = std::make_unique<QMenu>();
            const QVariantList items = downloadSnapshot();
            if (progress)
                addDownloads(*m_popup, items, true);
            else
                addMainCommands(*m_popup, items);
            m_popup->popup(position);
        });
    }

    void addDownloads(QMenu &menu, const QVariantList &items, bool hiddenOnly)
    {
        menu.setToolTipsVisible(true);
        QSet<qulonglong> ids;
        for (const auto &value : items) {
            const auto item = value.toMap();
            const auto id = item.value(QStringLiteral("id")).toULongLong();
            const bool hidden = item.value(QStringLiteral("hidden")).toBool() || id == m_smokeDownloadId;
            if (!id || ids.contains(id) || (hiddenOnly && !hidden))
                continue;
            ids.insert(id);

            const QString name = item.value(QStringLiteral("name")).toString();
            auto label = name.size() > 70 ? name.left(68) + QStringLiteral("…") : name;
            label.replace(QLatin1Char('&'), QStringLiteral("&&"));
            auto *action = menu.addAction(tr("%1 — %2").arg(label, item.value(QStringLiteral("summary")).toString()));
            action->setData(QVariant::fromValue(id));
            action->setToolTip(tr("%1\n%2").arg(name, item.value(QStringLiteral("details")).toString()));
            connect(action, &QAction::triggered, this, [this, id] {
                const QVariantList downloads = m_engine.dashboard().value(QStringLiteral("downloads")).toList();
                for (const auto &value : downloads) {
                    if (value.toMap().value(QStringLiteral("id")).toULongLong() == id) {
                        QMetaObject::invokeMethod(&m_root, "showDownload",
                            Q_ARG(QVariant, QVariant::fromValue(id)), Q_ARG(QVariant, QVariant(false)));
                        break;
                    }
                }
            });
        }
        if (ids.isEmpty())
            menu.addAction(hiddenOnly ? tr("No hidden download windows")
                                     : tr("No active or hidden downloads"))->setEnabled(false);
    }

    void addMainCommands(QMenu &menu, const QVariantList &items)
    {
        connect(menu.addAction(tr("Open Auralis Download Manager")), &QAction::triggered, this, m_activate);
        menu.addSeparator();

        const bool available = m_engine.ready() && !m_root.property("busy").toBool();
        const auto addCommand = [this, &menu](const QString &label, const char *method, bool enabled = true) {
            auto *action = menu.addAction(label);
            action->setEnabled(enabled);
            connect(action, &QAction::triggered, this, [this, method] {
                QMetaObject::invokeMethod(&m_root, method);
            });
        };
        addCommand(tr("Add new download…"), "addDownload", available);
        auto *batch = menu.addAction(tr("Add batch download…"));
        batch->setEnabled(available);
        connect(batch, &QAction::triggered, this, [this] {
            m_activate();
            QMetaObject::invokeMethod(&m_root, "showBatchDownload");
        });
        auto *clipboard = menu.addAction(tr("Add batch download from clipboard"));
        clipboard->setEnabled(available);
        connect(clipboard, &QAction::triggered, this, [this] {
            const QVariant text = QApplication::clipboard()->text();
            m_activate();
            QMetaObject::invokeMethod(&m_root, "showBatchDownloadFromClipboard", Q_ARG(QVariant, text));
        });

        addDownloads(*menu.addMenu(tr("Downloads in progress")), items, false);
        menu.addSeparator();

        auto *limiter = menu.addMenu(tr("Speed limiter"));
        limiter->setEnabled(available);
        auto *choices = new QActionGroup(limiter);
        const bool known = m_root.property("traySpeedLimiterKnown").toBool();
        const bool limiterOn = m_root.property("traySpeedLimiterOn").toBool();
        for (bool enable : {true, false}) {
            auto *action = limiter->addAction(enable ? tr("Turn on") : tr("Turn off"));
            action->setCheckable(true);
            action->setChecked(known && enable == limiterOn);
            choices->addAction(action);
            connect(action, &QAction::triggered, this, [this, enable] {
                QMetaObject::invokeMethod(&m_root, "setTraySpeedLimiter", Q_ARG(QVariant, QVariant(enable)));
            });
        }

        addCommand(tr("Scheduler"), "showScheduler");
        const auto queue = m_engine.dashboard().value(QStringLiteral("queues")).toList().value(0).toMap();
        const bool running = queue.value(QStringLiteral("running")).toBool();
        auto *mainQueue = menu.addAction(running ? tr("Stop main download queue") : tr("Start main download queue"));
        mainQueue->setEnabled(available && !queue.isEmpty());
        connect(mainQueue, &QAction::triggered, this, [this, running] {
            QMetaObject::invokeMethod(&m_root, "setMainQueueRunningFromTray", Q_ARG(QVariant, QVariant(!running)));
        });
        addCommand(tr("Settings"), "showSettings");
        menu.addSeparator();
        connect(menu.addAction(tr("Exit Auralis")), &QAction::triggered, this, [this] { m_engine.requestQuit(); });
    }

    Engine &m_engine;
    QObject &m_root;
    std::function<void()> m_activate;
    QSystemTrayIcon m_mainIcon;
    QSystemTrayIcon m_progressIcon;
    std::unique_ptr<QMenu> m_popup;
    qulonglong m_smokeDownloadId = 0;
};

void addBundledTools()
{
    const auto dir = QCoreApplication::applicationDirPath();
    if (QFileInfo::exists(QDir(dir).filePath(QStringLiteral("deno.exe"))))
        qputenv("PATH", QDir::toNativeSeparators(dir).toUtf8() + QDir::listSeparator().toLatin1() + qgetenv("PATH"));
}
}

int main(int argc, char **argv)
{
#ifdef Q_OS_WIN
    if (argc == 2 && std::strcmp(argv[1], "--refresh-taskbar-icon") == 0) {
        QCoreApplication app(argc, argv);
        refreshTaskbarIcon();
        return 0;
    }
#endif
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

    int activeInstanceConnections = 0;
    QLocalServer local;
    local.setSocketOptions(QLocalServer::UserAccessOption);
    local.setMaxPendingConnections(InstanceConnectionLimit);
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
    window->setIcon(appIcon);

    const auto activate = [window] {
        if (!window->isVisible() || window->visibility() == QWindow::Minimized)
            window->showNormal();
        window->raise();
        window->requestActivate();
    };
    QObject::connect(&local, &QLocalServer::newConnection, &app, [&local, &engine, &activeInstanceConnections, activate] {
        while (auto *socket = local.nextPendingConnection()) {
            if (activeInstanceConnections >= InstanceConnectionLimit) {
                socket->abort();
                socket->deleteLater();
                continue;
            }
            ++activeInstanceConnections;
            socket->setReadBufferSize(InstanceMessageLimit);
            QObject::connect(socket, &QObject::destroyed, &local, [&activeInstanceConnections] {
                --activeInstanceConnections;
            });
            QObject::connect(socket, &QLocalSocket::disconnected, socket, &QLocalSocket::deleteLater);
            QTimer::singleShot(InstanceReadTimeoutMs, socket, [socket] {
                socket->abort();
                socket->deleteLater();
            });
            const auto handle = [socket, &engine, activate] {
                if (!socket->canReadLine()) {
                    if (socket->bytesAvailable() >= InstanceMessageLimit)
                        socket->disconnectFromServer();
                    return;
                }
                const auto command = socket->readLine(InstanceMessageLimit + 1).trimmed();
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

    std::optional<TrayMenus> trayMenus;
    const bool registerTrayIcons = !smoke && engine.trayAvailable();
    if (registerTrayIcons || smoke)
        trayMenus.emplace(engine, *root, app.windowIcon(), activate, registerTrayIcons);

    std::unique_ptr<EngineSmoke> test;
    if (smoke) {
        qputenv("MDM_DOWNLOADS", QFile::encodeName(engine.dataDirectory()));
        test = std::make_unique<EngineSmoke>(engine, [&trayMenus](std::function<void(bool)> finish) {
            trayMenus->exercise(std::move(finish));
        });
    }
    QTimer::singleShot(0, &engine, &Engine::start);
    if (smoke) qInfo("Smoke: starting the Qt event loop and Rust service.");
    const int code = app.exec();
    if (smoke) qInfo("Smoke: event loop finished with exit code %d.", code);
    return code;
}
