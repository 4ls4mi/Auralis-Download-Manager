#include "Engine.h"
#include "Smoke.h"
#include "Typography.h"

#include <QAction>
#include <QActionGroup>
#include <QApplication>
#include <QClipboard>
#include <QColor>
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
#include <QPainter>
#include <QPalette>
#include <QPixmap>
#include <QPointer>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QSet>
#include <QSettings>
#include <QStandardPaths>
#include <QSystemTrayIcon>
#include <QTimer>

#include <algorithm>
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

QVariant qmlValue(const QObject *object, const char *property)
{
    const QVariant value = object ? object->property(property) : QVariant();
    return value.metaType() == QMetaType::fromType<QJSValue>()
        ? value.value<QJSValue>().toVariant() : value;
}

QColor trayColor(const QVariantMap &palette, const char *key, const QColor &fallback)
{
    const QVariant value = palette.value(QString::fromLatin1(key));
    const QColor color = value.value<QColor>();
    return color.isValid() ? color : fallback;
}

QColor mixTrayColor(const QColor &base, const QColor &tint, qreal weight)
{
    return QColor::fromRgbF(base.redF() + (tint.redF() - base.redF()) * weight,
                            base.greenF() + (tint.greenF() - base.greenF()) * weight,
                            base.blueF() + (tint.blueF() - base.blueF()) * weight);
}

void setTrayPopupFrame(QMenu &menu, const QPalette &palette)
{
    menu.setWindowFlag(Qt::FramelessWindowHint);
    menu.setAttribute(Qt::WA_TranslucentBackground);
    menu.setPalette(palette);
    for (auto *action : menu.actions()) {
        if (auto *submenu = action->menu())
            setTrayPopupFrame(*submenu, palette);
    }
}

void styleTrayPopup(QMenu &menu, const QObject *materialTheme)
{
    const auto profile = qmlValue(materialTheme, "palette").toMap();
    const auto colors = qmlValue(materialTheme, "menuColors").toMap();
    const auto hex = [](const QColor &color) { return color.name(QColor::HexArgb); };
    const QColor surface = trayColor(colors, "surface", QColor("#242934"));
    const QColor ink = trayColor(colors, "ink", QColor("#f5f6fa"));
    const QColor muted = trayColor(colors, "muted", QColor("#aab4c5"));
    const QColor border = trayColor(colors, "border", QColor("#555b6a"));
    const QColor highlight = trayColor(colors, "highlight", QColor("#7950d4"));
    const QColor pressed = trayColor(colors, "pressed", QColor("#6542b2"));
    const QColor highlightInk = trayColor(colors, "highlightInk", Qt::white);
    const QColor rail = trayColor(colors, "rail", highlightInk);
    const qreal gloss = std::clamp(profile.value(QStringLiteral("gloss")).toDouble(), 0., 1.);
    const QColor upper = mixTrayColor(surface, trayColor(profile, "upper", ink), .04 + gloss * .13);
    const QColor shade = mixTrayColor(surface, trayColor(profile, "shade", surface), .16 + gloss * .22);
    const int radius = std::clamp(profile.value(QStringLiteral("panelRadius"), 10).toInt() + 2, 6, 13);

    QPalette palette = menu.palette();
    palette.setColor(QPalette::Window, surface);
    palette.setColor(QPalette::WindowText, ink);
    palette.setColor(QPalette::Text, ink);
    palette.setColor(QPalette::ButtonText, ink);
    palette.setColor(QPalette::Highlight, highlight);
    palette.setColor(QPalette::HighlightedText, highlightInk);
    palette.setColor(QPalette::Disabled, QPalette::Text, muted);
    palette.setColor(QPalette::Disabled, QPalette::WindowText, muted);
    setTrayPopupFrame(menu, palette);

    const auto panel = QStringLiteral(
        "qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 %1, stop:0.21 %2, stop:1 %3)")
        .arg(hex(upper), hex(surface), hex(shade));
    const auto selection = QStringLiteral(
        "qlineargradient(x1:0, y1:0, x2:0, y2:1, stop:0 %1, stop:0.34 %1, stop:1 %2)")
        .arg(hex(highlight), hex(pressed));
    menu.setStyleSheet(QStringLiteral(
        "QMenu { background: %1; color: %2; border: 1px solid %3; border-radius: %4px;"
        " padding: 6px; font-size: 13px; min-width: 214px; menu-scrollable: 1; }"
        "QMenu::item { padding: 6px 27px 6px 24px; border: 1px solid transparent;"
        " border-left: 3px solid transparent; border-radius: 7px; }"
        "QMenu::item:selected:enabled { background: %5; color: %6; border-left-color: %7; }"
        "QMenu::item:disabled { color: %8; }"
        "QMenu::separator { height: 1px; background: %3; margin: 4px 8px; }")
        .arg(panel, hex(ink), hex(border), QString::number(radius),
             selection, hex(highlightInk), hex(rail), hex(muted)));
}

enum class TrayGlyph { Add, Scheduler, Settings, Exit };

QIcon trayActionIcon(TrayGlyph glyph, const QColor &color, const QColor &activeInk)
{
    const auto render = [glyph](const QColor &ink) {
        QPixmap pixmap(36, 36);
        pixmap.setDevicePixelRatio(2);
        pixmap.fill(Qt::transparent);
        QPainter painter(&pixmap);
        painter.setRenderHint(QPainter::Antialiasing);
        painter.setPen(QPen(ink, 1.7, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));
        switch (glyph) {
        case TrayGlyph::Add:
            painter.drawLine(9, 3, 9, 15);
            painter.drawLine(3, 9, 15, 9);
            break;
        case TrayGlyph::Scheduler:
            painter.drawEllipse(QRectF(2.3, 2.3, 13.4, 13.4));
            painter.drawPolyline(QPolygonF{QPointF(9, 5), QPointF(9, 9), QPointF(12, 11)});
            break;
        case TrayGlyph::Settings:
            for (int rail = 0; rail < 3; ++rail) {
                const int y = 4 + rail * 5;
                const int x = rail == 1 ? 11 : 6;
                painter.drawLine(2, y, x - 2, y);
                painter.drawLine(x + 2, y, 16, y);
                painter.drawEllipse(QRectF(x - 1.5, y - 1.5, 3, 3));
            }
            break;
        case TrayGlyph::Exit:
            painter.drawPolyline(QPolygonF{QPointF(10, 3), QPointF(3, 3), QPointF(3, 15), QPointF(10, 15)});
            painter.drawLine(8, 9, 15, 9);
            painter.drawPolyline(QPolygonF{QPointF(12, 6), QPointF(15, 9), QPointF(12, 12)});
            break;
        }
        painter.end();
        return pixmap;
    };
    QIcon icon(render(color));
    const QPixmap selected = render(activeInk);
    icon.addPixmap(selected, QIcon::Active);
    icon.addPixmap(selected, QIcon::Selected);
    return icon;
}

class TrayMenus final : public QObject
{
public:
    TrayMenus(Engine &engine, QObject &root, QObject *materialTheme, const QIcon &icon,
              std::function<void()> activate, bool registerIcons)
        : m_engine(engine), m_root(root), m_materialTheme(materialTheme), m_activate(std::move(activate)), m_mainIcon(icon),
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
        return qmlValue(&m_root, "trayDownloadItems").toList();
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
            styleTrayPopup(*m_popup, m_materialTheme);
            const auto icon = (progress ? m_progressIcon : m_mainIcon).geometry();
            const bool nearIcon = icon.adjusted(-8, -8, 8, 8).contains(position);
            m_popup->popup(icon.isValid() && !nearIcon ? icon.center() : position);
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
        connect(menu.addAction(m_mainIcon.icon(), tr("Open Auralis Download Manager")),
                &QAction::triggered, this, m_activate);
        menu.addSeparator();

        const auto profile = qmlValue(m_materialTheme, "palette").toMap();
        const auto colors = qmlValue(m_materialTheme, "menuColors").toMap();
        const QColor activeInk = trayColor(colors, "highlightInk", Qt::white);
        const auto icon = [this, &profile, &activeInk](TrayGlyph glyph, const char *symbol, const QColor &fallback) {
            QVariant tone;
            if (m_materialTheme) {
                QMetaObject::invokeMethod(m_materialTheme, "actionColor", Q_RETURN_ARG(QVariant, tone),
                    Q_ARG(QVariant, QVariant(QString::fromLatin1(symbol))),
                    Q_ARG(QVariant, profile.value(QStringLiteral("light"))));
            }
            const QColor color = tone.value<QColor>();
            return trayActionIcon(glyph, color.isValid() ? color : fallback, activeInk);
        };
        const bool available = m_engine.ready() && !m_root.property("busy").toBool();
        const auto addCommand = [this, &menu](const QString &label, const char *method, const QIcon &glyph, bool enabled = true) {
            auto *action = menu.addAction(glyph, label);
            action->setEnabled(enabled);
            connect(action, &QAction::triggered, this, [this, method] {
                QMetaObject::invokeMethod(&m_root, method);
            });
        };
        addCommand(tr("Add new download…"), "addDownload", icon(TrayGlyph::Add, "add", QColor("#55f38e")), available);
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

        addDownloads(*menu.addMenu(m_progressIcon.icon(), tr("Downloads in progress")), items, false);
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

        addCommand(tr("Scheduler"), "showScheduler", icon(TrayGlyph::Scheduler, "clock", QColor("#67e8e9")));
        const auto queue = m_engine.dashboard().value(QStringLiteral("queues")).toList().value(0).toMap();
        const bool running = queue.value(QStringLiteral("running")).toBool();
        auto *mainQueue = menu.addAction(running ? tr("Stop main download queue") : tr("Start main download queue"));
        mainQueue->setEnabled(available && !queue.isEmpty());
        connect(mainQueue, &QAction::triggered, this, [this, running] {
            QMetaObject::invokeMethod(&m_root, "setMainQueueRunningFromTray", Q_ARG(QVariant, QVariant(!running)));
        });
        addCommand(tr("Settings"), "showSettings", icon(TrayGlyph::Settings, "settings", QColor("#c09aff")));
        menu.addSeparator();
        const QIcon exitIcon = trayActionIcon(TrayGlyph::Exit, trayColor(colors, "danger", QColor("#ff7498")), activeInk);
        connect(menu.addAction(exitIcon, tr("Exit Auralis")), &QAction::triggered, this, [this] { m_engine.requestQuit(); });
    }

    Engine &m_engine;
    QObject &m_root;
    QPointer<QObject> m_materialTheme;
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
    // Qt Quick's legacy --device option takes priority over setSceneGraphBackend().
    const auto argumentsEnd = std::remove_if(argv + 1, argv + argc, [](const char *argument) {
        return std::strncmp(argument, "--device=", sizeof("--device=") - 1) == 0;
    });
    argc = static_cast<int>(argumentsEnd - argv);
    argv[argc] = nullptr;
    if (argc == 2 && std::strcmp(argv[1], "--refresh-taskbar-icon") == 0) {
        QCoreApplication app(argc, argv);
        refreshTaskbarIcon();
        return 0;
    }
#endif
    bool smoke = false;
    for (int index = 1; index < argc; ++index) {
        if (std::strcmp(argv[index], "--engine-smoke") == 0) {
            smoke = true;
            qInstallMessageHandler(writeSmokeLog);
            qInfo("Smoke: constructing the Qt application.");
            break;
        }
    }
    QCoreApplication::setApplicationName(QStringLiteral("Auralis Download Manager"));
    QCoreApplication::setOrganizationName(QStringLiteral("Auralis"));
    const QByteArray inheritedScale = qgetenv("QT_SCALE_FACTOR");
    const int activeInterfaceScale = smoke ? 100 : Typography::applyStartupInterfaceScale();
    QApplication app(argc, argv);
    // Qt caches the factor during startup. Restore the environment for child processes.
    if (activeInterfaceScale != 100) {
        if (inheritedScale.isNull())
            qunsetenv("QT_SCALE_FACTOR");
        else
            qputenv("QT_SCALE_FACTOR", inheritedScale);
    }
    app.setApplicationVersion(QStringLiteral(AURALIS_VERSION));
    QIcon appIcon(QStringLiteral(":/auralis/auralis.ico"));
    if (appIcon.availableSizes().isEmpty())
        appIcon = QIcon(QStringLiteral(":/auralis/auralis.png"));
    app.setWindowIcon(appIcon);
    app.setQuitOnLastWindowClosed(false);

    const QStringList arguments = app.arguments();
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
#ifdef Q_OS_WIN
    QQuickWindow::setSceneGraphBackend(QStringLiteral("rhi"));
    QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D12);
#endif
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QQuickWindow::setDefaultAlphaBuffer(true);

    // QML bindings must be destroyed before their native context objects.
    Typography typography(activeInterfaceScale);
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
    qml.rootContext()->setContextProperty(QStringLiteral("typography"), &typography);
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
        trayMenus.emplace(engine, *root,
            qml.singletonInstance<QObject *>(QStringLiteral("Auralis"), QStringLiteral("MaterialTheme")),
            app.windowIcon(), activate, registerTrayIcons);

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
