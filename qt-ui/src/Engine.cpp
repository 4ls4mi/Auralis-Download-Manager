#include "Engine.h"
#include "LocalFiles.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QJsonDocument>
#include <QProcess>
#include <QSettings>
#include <QSystemTrayIcon>
#include <QWindow>
#include <QtConcurrentRun>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>
#endif

namespace {
QVariantMap failure(const QString &error)
{
    return {{QStringLiteral("error"), error}};
}

QVariantMap result(const QVariant &value)
{
    return {{QStringLiteral("result"), value}};
}

QVariantMap startupSettings()
{
#ifdef Q_OS_WIN
    QSettings registry(QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"),
                       QSettings::NativeFormat);
    const QString name = QStringLiteral("Auralis Download Manager");
    const QString entry = registry.value(name).toString();
    return {{QStringLiteral("enabled"), !entry.isEmpty()},
            {QStringLiteral("mode"), entry.endsWith(QStringLiteral("--auralis-startup-window"))
                ? QStringLiteral("window") : QStringLiteral("minimized")}};
#else
    return {{QStringLiteral("enabled"), false},
            {QStringLiteral("mode"), QStringLiteral("minimized")}};
#endif
}

QVariantMap setStartupSettings(const QVariantMap &command)
{
    const QString mode = command.value(QStringLiteral("mode")).toString();
    const bool enabled = command.value(QStringLiteral("enabled")).toBool();
    if (mode != QStringLiteral("window") && mode != QStringLiteral("minimized"))
        return failure(QObject::tr("Choose a valid startup window mode."));
#ifdef Q_OS_WIN
    QSettings registry(QStringLiteral("HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"),
                       QSettings::NativeFormat);
    const QString name = QStringLiteral("Auralis Download Manager");
    if (enabled) {
        const QString exe = QDir::toNativeSeparators(QCoreApplication::applicationFilePath());
        registry.setValue(name, QStringLiteral("\"%1\" --auralis-startup-%2").arg(exe, mode));
    } else {
        registry.remove(name);
    }
    registry.sync();
    if (registry.status() != QSettings::NoError)
        return failure(QObject::tr("Could not change the Windows startup entry."));
#else
    if (enabled)
        return failure(QObject::tr("Starting with Windows is available on Windows."));
#endif
    return result(QVariantMap{{QStringLiteral("enabled"), enabled}, {QStringLiteral("mode"), mode}});
}
}

Engine::Engine(QJSEngine *scriptEngine, bool startHidden, bool smoke, QObject *parent)
    : QObject(parent),
      m_scriptEngine(scriptEngine),
      m_library(QCoreApplication::applicationDirPath() + QStringLiteral("/auralis_engine")),
      m_status(tr("Starting download engine")),
      m_startHidden(startHidden),
      m_smoke(smoke)
{
    m_commands.setMaxThreadCount(1);
    m_localJobs.setMaxThreadCount(1);
    m_serviceThread.setMaxThreadCount(1);
    m_library.setLoadHints(QLibrary::PreventUnloadHint);
    m_run = reinterpret_cast<Run>(m_library.resolve("auralis_engine_run"));
    m_request = reinterpret_cast<Request>(m_library.resolve("auralis_engine_request"));
    m_free = reinterpret_cast<Free>(m_library.resolve("auralis_engine_free"));
    const auto profile = reinterpret_cast<Run>(m_library.resolve("auralis_engine_profile"));
    if (m_free && profile)
        m_profile = decode(profile()).value(QStringLiteral("result")).toString();
    connect(&m_service, &QFutureWatcherBase::finished, this, &Engine::finishService);
    m_timer.setInterval(850);
    connect(&m_timer, &QTimer::timeout, this, &Engine::refresh);
}

Engine::~Engine()
{
    // Worker lambdas borrow the engine and profile. Wait while they still exist.
    m_commands.waitForDone();
    m_localJobs.waitForDone();
    m_serviceThread.waitForDone();
}

QString Engine::version() const { return QStringLiteral(AURALIS_VERSION); }

bool Engine::trayAvailable() const
{
    return !m_smoke && QSystemTrayIcon::isSystemTrayAvailable();
}

QVariantMap Engine::decode(char *output) const
{
    if (!output || !m_free)
        return failure(tr("The engine returned no response."));
    const QByteArray data(output);
    m_free(output);
    const QJsonDocument document = QJsonDocument::fromJson(data);
    if (!document.isObject())
        return failure(tr("The engine returned an invalid response."));
    return document.toVariant().toMap();
}

QVariantMap Engine::exchange(const QVariantMap &command) const
{
    if (!m_request || !m_free)
        return failure(tr("The bundled Auralis engine could not be loaded."));
    const QByteArray input = QJsonDocument::fromVariant(command).toJson(QJsonDocument::Compact);
    return decode(m_request(reinterpret_cast<const unsigned char *>(input.constData()), size_t(input.size())));
}

QVariantMap Engine::dispatch(const QVariantMap &command) const
{
    const QString local = command.value(QStringLiteral("local")).toString();
    if (local.isEmpty())
        return exchange(command);
    if (local == QStringLiteral("startupSettings"))
        return result(startupSettings());
    if (local == QStringLiteral("setStartupSettings"))
        return setStartupSettings(command);
    if (local == QStringLiteral("registerBrowserHost")) {
#ifdef Q_OS_WIN
        QProcess host;
        const QString path = QCoreApplication::applicationDirPath() + QStringLiteral("/auralis-browser-host.exe");
        if (!QFileInfo::exists(path))
            return failure(tr("The Auralis browser helper is missing from this installation."));
        host.start(path, {QStringLiteral("--register")});
        if (!host.waitForFinished(10000) || host.exitStatus() != QProcess::NormalExit || host.exitCode())
            return failure(tr("Could not register the browser helper."));
        return result(QVariantMap{{QStringLiteral("ok"), true}});
#else
        return failure(tr("This installer registers browser integration on Windows."));
#endif
    }
    return requestLocalFile(command, m_profile);
}

void Engine::start()
{
    if (!m_run || !m_request || !m_free || m_profile.isEmpty()) {
        setStatus(tr("The bundled Auralis engine could not start."));
        emit serviceStopped(false);
        return;
    }
    m_service.setFuture(QtConcurrent::run(&m_serviceThread, [this] { return decode(m_run()); }));
    m_timer.start();
    refresh();
}

void Engine::request(const QVariantMap &command) { request(command, QJSValue()); }

void Engine::request(const QVariantMap &command, const QJSValue &callback)
{
    const QString local = command.value(QStringLiteral("local")).toString();
    const QString shellAction = command.value(QStringLiteral("shellAction")).toString();
    const bool changesDownloads = local.isEmpty() && shellAction.isEmpty()
        && !command.contains(QStringLiteral("query"));
    const auto deliver = [this, callback, shellAction](const QVariantMap &response) {
        const QVariant value = response.value(QStringLiteral("result"));
        QString error = response.value(QStringLiteral("error")).toString();
        if (error.isEmpty())
            error = value.toMap().value(QStringLiteral("error")).toString();
        if (callback.isCallable()) {
            callback.call({m_scriptEngine->toScriptValue(value),
                           error.isEmpty() ? QJSValue(QJSValue::NullValue) : QJSValue(error)});
        } else if (!error.isEmpty()) {
            emit operationFailed(error);
        }
        if (error.isEmpty() && shellAction == QStringLiteral("update-install"))
            requestQuit();
    };
    if (local == QStringLiteral("openExtensionFolder")) {
        const auto path = QCoreApplication::applicationDirPath() + QStringLiteral("/auralis-extension");
        deliver(openFolder(path) ? result(QVariantMap{{QStringLiteral("ok"), true}})
                                 : failure(tr("Could not open the bundled extension folder.")));
        return;
    }

    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, deliver, changesDownloads] {
        deliver(watcher->result());
        watcher->deleteLater();
        if (changesDownloads)
            refresh();
    });
    QThreadPool *pool = local.isEmpty() && !shellAction.startsWith(QStringLiteral("update-"))
        ? &m_commands : &m_localJobs;
    watcher->setFuture(QtConcurrent::run(pool, [this, command] { return dispatch(command); }));
}

void Engine::refresh()
{
    if (m_refreshing || m_quitting || !running())
        return;
    m_refreshing = true;
    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher] {
        m_refreshing = false;
        applySnapshot(watcher->result());
        watcher->deleteLater();
    });
    watcher->setFuture(QtConcurrent::run(&m_commands, [this] {
        const auto list = exchange({{QStringLiteral("query"), QStringLiteral("list")}});
        const auto data = list.value(QStringLiteral("result")).toMap();
        if (!data.contains(QStringLiteral("downloads")))
            return list;
        const auto chart = exchange({{QStringLiteral("query"), QStringLiteral("glass-visuals")}});
        QFile browserRequest(QDir(m_profile).filePath(QStringLiteral("glass-browser-window-request")));
        QString target;
        if (browserRequest.open(QIODevice::ReadOnly)) {
            target = QString::fromUtf8(browserRequest.read(512)).trimmed();
            browserRequest.close();
            browserRequest.remove();
        }
        return QVariantMap{{QStringLiteral("dashboard"), data},
                           {QStringLiteral("visuals"), chart.value(QStringLiteral("result"))},
                           {QStringLiteral("browserRequest"), target}};
    }));
}

void Engine::applySnapshot(const QVariantMap &response)
{
    if (!response.contains(QStringLiteral("dashboard"))) {
        setReady(false);
        if (running())
            setStatus(tr("Connecting to download engine"));
        return;
    }
    const auto dashboard = response.value(QStringLiteral("dashboard")).toMap();
    const auto visuals = response.value(QStringLiteral("visuals")).toMap();
    if (m_dashboard != dashboard) {
        m_dashboard = dashboard;
        emit dashboardChanged();
    }
    if (!visuals.isEmpty() && m_visuals != visuals) {
        m_visuals = visuals;
        emit visualsChanged();
    }
    setReady(true);
    setStatus(tr("Connected"));
    const QString browserRequest = response.value(QStringLiteral("browserRequest")).toString();
    if (!browserRequest.isEmpty() && !m_smoke)
        emit browserWindowRequested(browserRequest);
    if (m_firstSnapshot) {
        m_firstSnapshot = false;
        request({{QStringLiteral("shellAction"), QStringLiteral("register-interface")}});
    #ifdef Q_OS_WIN
        if (!m_smoke && !qEnvironmentVariableIsSet("AURALIS_TEST_SKIP_HOST"))
            request({{QStringLiteral("local"), QStringLiteral("registerBrowserHost")}});
#endif
    }
}

void Engine::requestQuit(int exitCode)
{
    if (m_quitting)
        return;
    m_exitCode = exitCode;
    if (!running()) {
        QCoreApplication::exit(m_exitCode);
        return;
    }
    m_quitting = true;
    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher] {
        const auto response = watcher->result();
        watcher->deleteLater();
        const QString error = response.value(QStringLiteral("error")).toString();
        if (!error.isEmpty() && running()) {
            m_quitting = false;
            emit operationFailed(error);
        }
    });
    watcher->setFuture(QtConcurrent::run(&m_commands, [this] {
        return exchange({{QStringLiteral("exit"), true}});
    }));
}

void Engine::finishService()
{
    m_timer.stop();
    setReady(false);
    const auto reply = m_service.result();
    const auto error = reply.value(QStringLiteral("error")).toString();
    setStatus(error.isEmpty() ? tr("Engine stopped") : error);
    emit serviceStopped(error.isEmpty());
    if (m_quitting)
        QCoreApplication::exit(error.isEmpty() ? m_exitCode : 1);
}

void Engine::setReady(bool ready)
{
    if (ready == m_ready)
        return;
    m_ready = ready;
    emit readyChanged();
}

void Engine::setStatus(const QString &status)
{
    if (status == m_status)
        return;
    m_status = status;
    emit statusChanged();
}

QString Engine::localPath(const QUrl &url) const
{
    return url.isLocalFile() ? QDir::toNativeSeparators(url.toLocalFile()) : QString();
}

bool Engine::openPath(const QString &path) const
{
    const QFileInfo entry(path);
    return entry.isAbsolute() && entry.exists() && QDesktopServices::openUrl(QUrl::fromLocalFile(entry.absoluteFilePath()));
}

bool Engine::openFolder(const QString &path) const
{
    const QFileInfo entry(path);
    if (!entry.isAbsolute())
        return false;
    return openPath(entry.isDir() ? entry.absoluteFilePath() : entry.absolutePath());
}

bool Engine::applyBackdrop(QWindow *window, bool enabled, bool dark) const
{
#ifdef Q_OS_WIN
    if (!window || !window->isVisible() || m_smoke)
        return false;
    const auto hwnd = reinterpret_cast<HWND>(window->winId());
    constexpr DWORD SystemBackdropType = 38;
    constexpr DWORD ImmersiveDarkMode = 20;
    int current = 0;
    if (FAILED(DwmGetWindowAttribute(hwnd, SystemBackdropType, &current, sizeof current)))
        return false;
    // Desktop Acrylic uses a solid fallback when the window is inactive.
    // Clear it behind Settings so the Qt window can keep its own alpha.
    const bool useAcrylic = enabled && GetForegroundWindow() == hwnd;
    if (useAcrylic) {
        const BOOL darkMode = dark;
        DwmSetWindowAttribute(hwnd, ImmersiveDarkMode, &darkMode, sizeof darkMode);
    }
    constexpr int None = 1;
    constexpr int DesktopAcrylic = 3;
    const int type = useAcrylic ? DesktopAcrylic : None;
    const int margin = useAcrylic ? -1 : 0;
    const MARGINS margins{margin, margin, margin, margin};
    if (FAILED(DwmExtendFrameIntoClientArea(hwnd, &margins)))
        return false;
    if (FAILED(DwmSetWindowAttribute(hwnd, SystemBackdropType, &type, sizeof type))) {
        const MARGINS reset{0, 0, 0, 0};
        DwmExtendFrameIntoClientArea(hwnd, &reset);
        return false;
    }
    return useAcrylic;
#else
    Q_UNUSED(window);
    Q_UNUSED(enabled);
    Q_UNUSED(dark);
    return false;
#endif
}
