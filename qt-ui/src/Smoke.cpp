#include "Smoke.h"
#include "Engine.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QJSValue>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickItem>
#include <QMouseEvent>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSaveFile>
#include <QScreen>
#include <QSettings>
#include <QTcpSocket>
#include <QTimer>
#include <QUuid>

#ifdef Q_OS_WIN
#include <QtCore/qt_windows.h>
#endif

#include <utility>

namespace {
const QByteArray Payload = QByteArray("Auralis Qt downloader integrity test\n").repeated(56 * 1024);
constexpr qsizetype InitialBytes = 320 * 1024;
constexpr qsizetype ChunkBytes = 32 * 1024;

QQuickWindow *visibleWindow(const QString &name)
{
    for (auto *window : QGuiApplication::allWindows()) {
        if (window->isVisible() && window->objectName() == name)
            return qobject_cast<QQuickWindow *>(window);
    }
    return nullptr;
}

QJsonObject upgradePreferenceGroup(const QString &group)
{
    return QJsonDocument::fromJson(qgetenv("AURALIS_TEST_UPGRADE_PREFERENCES")).object().value(group).toObject();
}

QSize fittedWindowSize(const QWindow &window, const QSize &saved)
{
    const QSize workArea = window.screen() ? window.screen()->availableGeometry().size() : QSize();
    return (workArea.isEmpty() ? saved : saved.boundedTo(workArea)).expandedTo(window.minimumSize());
}

bool hasExpectedWindowSize(QQuickWindow &window, const QJsonObject &group, const QString &widthKey,
                           const QString &heightKey)
{
    const QSize expected(group.value(widthKey).toInt(), group.value(heightKey).toInt());
    if (expected.isEmpty() || fittedWindowSize(window, expected) == window.size())
        return true;
    qCritical() << "Smoke: saved dimensions differ for" << window.objectName() << window.size() << "expected" << expected;
    return false;
}

bool verifyUpgradePreferences(const QDir &profile)
{
    const QByteArray expectation = qgetenv("AURALIS_TEST_UPGRADE_PREFERENCES");
    if (expectation.isEmpty())
        return true;

    const QJsonObject groups = QJsonDocument::fromJson(expectation).object();
    const auto main = groups.value(QStringLiteral("MainWindow")).toObject();
    const QSize expectedSize(main.value(QStringLiteral("fullWidth")).toInt(),
                             main.value(QStringLiteral("fullHeight")).toInt());
    const auto expectedSidebar = main.value(QStringLiteral("showSidebar"));
    const int expectedScale = groups.value(QStringLiteral("Typography")).toObject()
        .value(QStringLiteral("interfaceScalePercent")).toInt();
    if (!expectedSize.isValid() || !expectedSidebar.isBool() || expectedScale <= 0) {
        qCritical("Smoke: invalid upgrade preference fixture.");
        return false;
    }

    // Check the loaded values before the transfer smoke test resizes any windows.
    QSettings settings;
    settings.sync();
    const QString path = profile.relativeFilePath(settings.fileName());
    if (settings.format() != QSettings::IniFormat || !path.startsWith(QStringLiteral("qt-settings/"))
        || settings.status() != QSettings::NoError) {
        qCritical("Smoke: upgrade settings are outside the isolated fixture profile.");
        return false;
    }
    for (auto group = groups.constBegin(); group != groups.constEnd(); ++group) {
        const QJsonObject values = group.value().toObject();
        for (auto preference = values.constBegin(); preference != values.constEnd(); ++preference) {
            const auto key = group.key() + QLatin1Char('/') + preference.key();
            const QVariant actual = settings.value(key);
            if (!actual.isValid() || actual.toString() != preference.value().toVariant().toString()) {
                qCritical() << "Smoke: a saved preference changed during upgrade:" << key << actual
                            << "expected" << preference.value();
                return false;
            }
        }
    }

    auto *window = visibleWindow(QStringLiteral("mainWindow"));
    if (!window) {
        qCritical("Smoke: the main window did not open after upgrade.");
        return false;
    }
    const auto sidebar = window->property("showSidebar");
    const auto interfaceScale = window->property("interfaceScale");
    const auto fontSettings = window->property("fontSettings");
    const auto *typography = fontSettings.metaType() == QMetaType::fromType<QJSValue>()
        ? fontSettings.value<QJSValue>().toQObject() : fontSettings.value<QObject *>();
    const int startupScale = typography ? typography->property("activeInterfaceScalePercent").toInt() : 0;
    if (window->size() != fittedWindowSize(*window, expectedSize) || !sidebar.isValid() || sidebar.toBool() != expectedSidebar.toBool()
        || !qFuzzyCompare(interfaceScale.toDouble(), expectedScale / 100.0) || startupScale != expectedScale) {
        qCritical() << "Smoke: upgraded main window used incorrect dimensions, sidebar or scale:"
                    << window->size() << sidebar << interfaceScale << startupScale
                    << "expected" << expectedSize << expectedSidebar << expectedScale;
        return false;
    }

    const auto *sidebarItem = window->findChild<QQuickItem *>(QStringLiteral("downloadsSidebar"));
    const auto *recentItem = window->findChild<QQuickItem *>(QStringLiteral("recentDownloadsSidebar"));
    if (!sidebarItem || !recentItem || (!expectedSidebar.toBool() && (sidebarItem->isVisible() || recentItem->isVisible()))) {
        qCritical("Smoke: the saved hidden sidebar preference was not applied to the visible layout.");
        return false;
    }

    const QSize expectedCompactSize(main.value(QStringLiteral("compactWidth")).toInt(),
                                    main.value(QStringLiteral("compactHeight")).toInt());
    if (!QMetaObject::invokeMethod(window, "toggleCompactView") || !window->property("compactView").toBool()
        || (!expectedCompactSize.isEmpty() && window->size() != fittedWindowSize(*window, expectedCompactSize))
        || !QMetaObject::invokeMethod(window, "toggleCompactView") || window->property("compactView").toBool()
        || window->size() != fittedWindowSize(*window, expectedSize) || window->property("showSidebar").toBool() != expectedSidebar.toBool()) {
        qCritical("Smoke: switching workspace modes did not restore their saved sizes and sidebar preference.");
        return false;
    }

    const auto settingsWindow = groups.value(QStringLiteral("SettingsWindowLayout")).toObject();
    const QSize expectedSettingsSize(settingsWindow.value(QStringLiteral("initialWidth")).toInt(),
                                     settingsWindow.value(QStringLiteral("initialHeight")).toInt());
    if (!QMetaObject::invokeMethod(window, "showSettings")) {
        qCritical("Smoke: could not open Settings after the update.");
        return false;
    }
    auto *openedSettings = visibleWindow(QStringLiteral("settingsWindow"));
    if (!openedSettings || openedSettings->size() != fittedWindowSize(*openedSettings, expectedSettingsSize)
        || !openedSettings->close()) {
        qCritical("Smoke: Settings did not use its saved size after the update.");
        return false;
    }

    const QJsonObject appearance = QJsonDocument::fromJson(settings.value(QStringLiteral("WindowAppearance/saved"))
        .toString().toUtf8()).object();
    const auto material = appearance.value(QStringLiteral("mh-glass-material")).toString();
    if (material != QStringLiteral("fractured-pearl") || !window->property("fracturedLayout").toBool()) {
        qCritical("Smoke: the saved Fractured Acrylic material was not restored.");
        return false;
    }
    const auto control = [window](const auto &name) -> QQuickItem * {
        auto *item = window->findChild<QQuickItem *>(name);
        return item && item->isVisible() && item->isEnabled() && item->width() > 0 && item->height() > 0 ? item : nullptr;
    };
    auto *viewButton = control(QStringLiteral("mainViewMenuButton"));
    auto *viewMenu = window->findChild<QObject *>(QStringLiteral("mainViewMenu"));
    if (!control(QStringLiteral("titleDragArea")) || !control(QStringLiteral("downloadList")) || !viewButton
        || !viewMenu || !QMetaObject::invokeMethod(viewButton, "clicked") || !viewMenu->property("visible").toBool()
        || !QMetaObject::invokeMethod(viewMenu, "close")) {
        qCritical("Smoke: Fractured Acrylic hid the normal title bar, download list or View menu.");
        return false;
    }
    qInfo("Smoke: non-default preferences survived the passive upgrade and relaunch.");
    qInfo("Smoke: the normal title bar, download list and View menu are available with Fractured Acrylic.");
    return true;
}

bool isIndependent(QWindow &window)
{
    if (window.parent() || window.transientParent() || window.modality() != Qt::NonModal ||
        (window.flags() & Qt::WindowType_Mask) != Qt::Window)
        return false;
#ifdef Q_OS_WIN
    return !GetWindow(reinterpret_cast<HWND>(window.winId()), GW_OWNER);
#else
    return true;
#endif
}

bool hasRenderedContent(const QImage &frame)
{
    if (frame.isNull())
        return false;
    const auto background = frame.pixel(0, 0);
    for (int y = 8; y < frame.height(); y += 16) {
        for (int x = 8; x < frame.width(); x += 16) {
            if (frame.pixel(x, y) != background)
                return true;
        }
    }
    return false;
}
}

EngineSmoke::EngineSmoke(Engine &engine, TrayCheck checkTray)
    : m_engine(engine), m_checkTray(std::move(checkTray))
{
    const auto root = QDir(m_engine.dataDirectory());
    m_name = QStringLiteral("auralis-qt-smoke-%1.bin").arg(QUuid::createUuid().toString(QUuid::Id128));
    QFile::remove(root.filePath(QStringLiteral("qt-engine-smoke.ok")));
    connect(&m_server, &QTcpServer::newConnection, this, &EngineSmoke::serve);
    connect(&m_engine, &Engine::readyChanged, this, &EngineSmoke::startDownload);
    connect(&m_engine, &Engine::serviceStopped, this, &EngineSmoke::verifyShutdown);
    connect(&m_engine, &Engine::operationFailed, this, &EngineSmoke::fail);
    auto *observe = new QTimer(this);
    connect(observe, &QTimer::timeout, this, &EngineSmoke::inspectTransfers);
    observe->start(100);
    QTimer::singleShot(45000, this, [this] {
        const auto downloads = m_engine.dashboard().value(QStringLiteral("downloads")).toList();
        for (const auto &entry : downloads) {
            const auto download = entry.toMap();
            if (download.value(QStringLiteral("url")).toString() == m_url)
                qInfo() << "Smoke: fixture status at timeout" << download.value(QStringLiteral("status"))
                        << download.value(QStringLiteral("downloaded"));
        }
        qInfo() << "Smoke: progress window/frame/resize at timeout" << bool(m_window) << m_framePresented
                << m_expectedProgressSize;
        if (m_window)
            qInfo() << "Smoke: progress exposure and scene state" << m_window->isExposed()
                    << m_window->geometry() << m_window->isSceneGraphInitialized()
                    << m_window->property("runningTransfer");
        fail(QStringLiteral("The Qt transfer test timed out at step %1.").arg(static_cast<int>(m_step)));
    });
}

void EngineSmoke::startDownload()
{
    if (m_started || !m_engine.ready())
        return;
    m_started = true;
    if (!verifyUpgradePreferences(QDir(m_engine.dataDirectory()))) {
        fail(QStringLiteral("The Qt preferences did not survive the passive upgrade."));
        return;
    }
    qInfo("Smoke: Rust service connected. Requesting the local download confirmation.");
    if (!m_server.listen(QHostAddress::LocalHost, 0)) {
        fail(m_server.errorString());
        return;
    }
    m_url = QStringLiteral("http://127.0.0.1:%1/%2").arg(m_server.serverPort()).arg(m_name);
    m_engine.request({{QStringLiteral("url"), m_url}, {QStringLiteral("name"), m_name}});
}

void EngineSmoke::confirmDownload()
{
    auto *prompt = visibleWindow(QStringLiteral("addDownloadWindow"));
    if (!prompt || !prompt->property("confirming").toBool() || prompt->property("busy").toBool())
        return;
    if (!isIndependent(*prompt)) {
        fail(QStringLiteral("The download confirmation is owned by another window or is modal."));
        return;
    }
    if (!hasExpectedWindowSize(*prompt, upgradePreferenceGroup(QStringLiteral("DetachedWindowLayout")),
                               QStringLiteral("addDownloadWindow/width"), QStringLiteral("addDownloadWindow/height"))) {
        fail(QStringLiteral("The download confirmation did not use its saved size after the update."));
        return;
    }
    auto *destination = prompt->findChild<QObject *>(QStringLiteral("downloadDestination"));
    auto *connections = prompt->findChild<QObject *>(QStringLiteral("downloadConnectionCount"));
    auto *confirm = prompt->findChild<QObject *>(QStringLiteral("confirmStartDownload"));
    if (!destination || !connections || !confirm || !confirm->property("enabled").toBool() ||
        !prompt->setProperty("destinationEdited", true) ||
        !destination->setProperty("text", QDir(m_engine.dataDirectory()).filePath(m_name)) ||
        !connections->setProperty("value", 1)) {
        fail(QStringLiteral("The download confirmation controls could not be used."));
        return;
    }
    m_step = Step::Starting;
    qInfo("Smoke: independent file confirmation opened. Invoking Start download.");
    if (!QMetaObject::invokeMethod(confirm, "clicked"))
        fail(QStringLiteral("The Start download action could not be invoked."));
}

void EngineSmoke::inspectTransfers()
{
    if (!m_started || m_step == Step::Stopped)
        return;
    if (m_step == Step::WaitingForConfirmation) {
        confirmDownload();
        return;
    }
    const auto downloads = m_engine.dashboard().value(QStringLiteral("downloads")).toList();
    for (const auto &entry : downloads) {
        const auto download = entry.toMap();
        if (download.value(QStringLiteral("file")).toString() != m_name &&
            download.value(QStringLiteral("url")).toString() != m_url)
            continue;
        const auto id = download.value(QStringLiteral("id")).toULongLong();
        const auto status = download.value(QStringLiteral("status")).toString();
        if (status == QStringLiteral("Error")) {
            fail(QStringLiteral("The local smoke-test transfer failed."));
            return;
        }
        if (status == QStringLiteral("Complete")) {
            if (m_step != Step::Finishing) {
                fail(QStringLiteral("The transfer completed before both active progress windows were exercised."));
                return;
            }
            if (!verifyCompletion(download))
                return;
            QFile file(download.value(QStringLiteral("path")).toString());
            if (!file.open(QIODevice::ReadOnly) || file.readAll() != Payload) {
                fail(QStringLiteral("The downloaded smoke-test file differs from the local payload."));
                return;
            }
            m_transferVerified = true;
            m_step = Step::Stopped;
            qInfo("Smoke: downloaded bytes verified after pause and resume. Stopping the service.");
            m_engine.requestQuit();
            return;
        }
        if (m_step == Step::WaitingForPause && status == QStringLiteral("Stopped")) {
            if (!m_window) {
                fail(QStringLiteral("The progress window disappeared during pause."));
                return;
            }
            m_window->close();
            m_framePresented = false;
            m_frameReadbackQueued = false;
            m_step = Step::WaitingForResume;
            qInfo("Smoke: transfer paused. Resuming with the progress window closed.");
            m_engine.request({{QStringLiteral("action"), QStringLiteral("start")},
                              {QStringLiteral("ids"), QVariantList{QVariant::fromValue(id)}}});
            return;
        }
        if ((m_step == Step::Starting || m_step == Step::WaitingForResume) &&
            status == QStringLiteral("Downloading")) {
            observeTransferWindow(id);
            if (!m_framePresented || download.value(QStringLiteral("downloaded")).toLongLong() <= 0)
                return;
#ifdef Q_OS_WIN
            const bool requestedDirect3D12 = qgetenv("QSG_RHI_BACKEND") == QByteArrayLiteral("d3d12");
            const auto expectedApi = requestedDirect3D12 ? QSGRendererInterface::Direct3D12
                                                        : QSGRendererInterface::Direct3D11;
            if (m_window->rendererInterface()->graphicsApi() != expectedApi) {
                fail(QStringLiteral("The installed progress window did not render with the requested Windows renderer."));
                return;
            }
            qInfo("Smoke: using Direct3D %d.", requestedDirect3D12 ? 12 : 11);
#endif
            if (!m_resizeVerified) {
                if (!m_expectedProgressSize.isValid()) {
                    resizeTransferWindow();
                    return;
                }
                if (m_window->size() != m_expectedProgressSize) {
                    fail(QStringLiteral("The active progress window did not respond to its resize grip."));
                    return;
                }
                m_resizeVerified = true;
                qInfo("Smoke: active progress window resized.");
            }
            verifyTrayMenu(m_step == Step::WaitingForResume);
        }
        return;
    }
}

void EngineSmoke::verifyTrayMenu(bool resumed)
{
    const Step checking = resumed ? Step::CheckingResumedTrayMenu : Step::CheckingInitialTrayMenu;
    m_step = checking;
    if (!m_checkTray) {
        fail(QStringLiteral("The tray context menu test is unavailable."));
        return;
    }
    m_checkTray([this, checking, resumed](bool opened) {
        if (m_step != checking)
            return;
        if (!opened) {
            fail(QStringLiteral("The tray context menu could not be opened during an active transfer."));
            return;
        }
        if (resumed) {
            m_step = Step::Finishing;
            qInfo("Smoke: resumed progress window rendered and tray context menu opened.");
        } else {
            m_step = Step::WaitingForPause;
            qInfo("Smoke: initial progress window rendered and tray context menu opened. Pausing from the toolbar.");
            if (!pauseTransfer())
                fail(QStringLiteral("The progress window's Pause action could not be invoked."));
        }
    });
}

void EngineSmoke::observeTransferWindow(qulonglong id)
{
    if (!id)
        return;
    for (auto *window : QGuiApplication::allWindows()) {
        auto *progress = qobject_cast<QQuickWindow *>(window);
        if (!progress || !progress->isVisible() || progress->objectName() != QStringLiteral("downloadProgressWindow") ||
            progress->property("downloadId").toULongLong() != id)
            continue;
        if (m_window != progress) {
            if (!isIndependent(*progress)) {
                fail(QStringLiteral("The download progress window is owned by another window or is modal."));
                return;
            }
            const auto layout = upgradePreferenceGroup(QStringLiteral("TransferWindowLayout"));
            const auto expectedCompact = layout.value(QStringLiteral("compactView"));
            if (!m_resizeVerified && expectedCompact.isBool()) {
                const bool compact = expectedCompact.toBool();
                if (progress->property("compactView").toBool() != compact
                    || !hasExpectedWindowSize(*progress, layout,
                        compact ? QStringLiteral("initialCompactWidth") : QStringLiteral("initialExpandedWidth"),
                        compact ? QStringLiteral("initialCompactHeight") : QStringLiteral("initialExpandedHeight"))) {
                    fail(QStringLiteral("The current download did not use its saved mode and size after the update."));
                    return;
                }
            }
#ifdef Q_OS_WIN
            // Exercise the translucent surface and Qt Quick 3D on the Windows renderer.
            progress->setProperty("material", QStringLiteral("aero-gloss"));
#endif
            disconnect(m_frameConnection);
            m_window = progress;
            m_framePresented = false;
            m_frameReadbackQueued = false;
            qInfo("Smoke: found the independent progress window.");
            const QPointer<QQuickWindow> observed(progress);
            m_frameConnection = connect(progress, &QQuickWindow::afterFrameEnd, this, [this, observed] {
                if (observed && m_window == observed && observed->isVisible() &&
                    observed->property("runningTransfer").toBool())
                    m_framePresented = true;
            }, Qt::QueuedConnection);
        }
        progress->update();
        if (!m_framePresented && !m_frameReadbackQueued && progress->isSceneGraphInitialized()) {
            m_frameReadbackQueued = true;
            const QPointer<QQuickWindow> observed(progress);
            QTimer::singleShot(350, this, [this, observed] {
                if (m_framePresented || !observed || m_window != observed || !observed->isVisible() ||
                    !observed->property("runningTransfer").toBool())
                    return;
                // An overlapping top-level window can suppress desktop presentation.
                const QImage image = observed->grabWindow();
                m_framePresented = hasRenderedContent(image);
                qInfo() << "Smoke: progress render readback" << image.size() << m_framePresented
                        << "exposed" << observed->isExposed();
            });
        }
        break;
    }
}

void EngineSmoke::resizeTransferWindow()
{
    const QPoint corner(m_window->width() - 4, m_window->height() - 4);
    const QPoint origin = m_window->mapToGlobal(corner);
    const QPoint delta(28, 24);
    const QPoint target = origin + delta;
    m_expectedProgressSize = m_window->size() + QSize(delta.x(), delta.y());
    QMouseEvent press(QEvent::MouseButtonPress, corner, origin, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(m_window, &press);
    QMouseEvent move(QEvent::MouseMove, m_window->mapFromGlobal(target), target, Qt::NoButton, Qt::LeftButton, Qt::NoModifier);
    QCoreApplication::sendEvent(m_window, &move);
    QMouseEvent release(QEvent::MouseButtonRelease, m_window->mapFromGlobal(target), target, Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
    QCoreApplication::sendEvent(m_window, &release);
    m_window->update();
}

bool EngineSmoke::verifyCompletion(const QVariantMap &download)
{
    auto *completion = visibleWindow(QStringLiteral("downloadCompleteWindow"));
    if (!completion)
        return false;
    const QString exactBytes = completion->property("exactBytes").toString();
    if (exactBytes.isEmpty())
        return false;
    if (m_window && m_window->isVisible()) {
        fail(QStringLiteral("The progress window remained open after the download completed."));
        return false;
    }
    auto *address = completion->findChild<QObject *>(QStringLiteral("completedDownloadAddress"));
    auto *path = completion->findChild<QObject *>(QStringLiteral("completedDownloadPath"));
    auto *size = completion->findChild<QObject *>(QStringLiteral("completedDownloadSize"));
    const QString savedPath = QDir::fromNativeSeparators(download.value(QStringLiteral("path")).toString());
    if (!address || address->property("text").toString() != m_url || !path ||
        QDir::fromNativeSeparators(path->property("text").toString()) != savedPath ||
        exactBytes != QString::number(Payload.size()) || !size || size->property("text").toString().isEmpty()) {
        fail(QStringLiteral("The completion window did not show the download address, saved path, and size."));
        return false;
    }
    const QStringList actions = {
        QStringLiteral("completedDownloadOpen"), QStringLiteral("completedDownloadOpenWith"),
        QStringLiteral("completedDownloadOpenFolder"), QStringLiteral("completedDownloadMove"),
        QStringLiteral("completedDownloadDrag"), QStringLiteral("hideDownloadCompletion"),
        QStringLiteral("completedDownloadClose")
    };
    for (const auto &name : actions) {
        if (!completion->findChild<QObject *>(name)) {
            fail(QStringLiteral("The completion window is missing %1.").arg(name));
            return false;
        }
    }
    return true;
}

bool EngineSmoke::pauseTransfer()
{
    auto *button = m_window ? m_window->findChild<QObject *>(QStringLiteral("pauseOrResumeDownload")) : nullptr;
    return button && button->property("enabled").toBool() && QMetaObject::invokeMethod(button, "clicked");
}

void EngineSmoke::fail(const QString &message)
{
    if (m_step == Step::Stopped)
        return;
    m_step = Step::Stopped;
    qCritical().noquote() << message;
    m_engine.requestQuit(1);
}

void EngineSmoke::verifyShutdown(bool clean)
{
    if (!clean || !m_transferVerified) {
        QCoreApplication::exit(1);
        return;
    }
    qInfo("Smoke: Rust service stopped cleanly.");
    QSaveFile marker(QDir(m_engine.dataDirectory()).filePath(QStringLiteral("qt-engine-smoke.ok")));
    const QByteArray confirmation("Independent confirmation and progress windows, active resizing, tray menus, completion details, and file integrity verified.\n");
    if (!marker.open(QIODevice::WriteOnly) || marker.write(confirmation) != confirmation.size() || !marker.commit())
        qFatal("Could not persist the Qt engine integration result.");
}

void EngineSmoke::serve()
{
    while (auto *socket = m_server.nextPendingConnection()) {
        connect(socket, &QTcpSocket::disconnected, socket, &QTcpSocket::deleteLater);
        connect(socket, &QTcpSocket::readyRead, socket, [this, socket, header = QByteArray(), answered = false]() mutable {
            header += socket->readAll();
            if (answered)
                return;
            if (header.size() > 16384) {
                socket->disconnectFromHost();
                return;
            }
            if (!header.contains("\r\n\r\n"))
                return;
            answered = true;
            static const QRegularExpression range(QStringLiteral("\\r\\nRange:[ \\t]*bytes=([0-9]+)-([0-9]*)"),
                                                   QRegularExpression::CaseInsensitiveOption);
            const auto match = range.match(QString::fromLatin1(header));
            qsizetype first = 0;
            qsizetype last = Payload.size() - 1;
            if (match.hasMatch()) {
                first = match.capturedView(1).toLongLong();
                if (!match.capturedView(2).isEmpty())
                    last = qMin(last, match.capturedView(2).toLongLong());
                if (first > last) {
                    socket->write("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */" +
                                  QByteArray::number(Payload.size()) + "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                    socket->disconnectFromHost();
                    return;
                }
            }
            QByteArray reply(match.hasMatch() ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n");
            if (match.hasMatch()) {
                reply += "Content-Range: bytes " + QByteArray::number(first) + '-' +
                    QByteArray::number(last) + '/' + QByteArray::number(Payload.size()) + "\r\n";
            }
            reply += "Content-Type: application/octet-stream\r\nAccept-Ranges: bytes\r\nConnection: close\r\nContent-Length: " +
                QByteArray::number(last + 1 - first) + "\r\n\r\n";
            socket->write(reply);
            if (header.startsWith("HEAD ")) {
                socket->disconnectFromHost();
                return;
            }

            // Leave enough bytes pending for two visible, in-progress snapshots.
            auto *pump = new QTimer(socket);
            const auto end = last + 1;
            connect(pump, &QTimer::timeout, socket, [this, socket, pump, end, first, position = first]() mutable {
                const bool checkingTray = m_step == Step::CheckingInitialTrayMenu || m_step == Step::CheckingResumedTrayMenu;
                const auto heldBytes = InitialBytes + (checkingTray ? 3 * ChunkBytes : 0);
                const auto available = m_step == Step::Finishing ? end : qMin(end, first + heldBytes);
                if (position < available && socket->bytesToWrite() < ChunkBytes) {
                    const auto written = socket->write(Payload.constData() + position, qMin(ChunkBytes, available - position));
                    if (written < 0) {
                        pump->stop();
                        socket->abort();
                        return;
                    }
                    position += written;
                }
                if (position == end) {
                    pump->stop();
                    socket->disconnectFromHost();
                }
            });
            pump->start(30);
        });
    }
}
