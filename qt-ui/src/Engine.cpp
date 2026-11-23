#include "Engine.h"
#include "FrameResize.h"
#include "LocalFiles.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJSEngine>
#include <QJsonDocument>
#include <QProcess>
#include <QRegularExpression>
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

#ifdef Q_OS_WIN
QString chromeExecutableAt(QString path)
{
    path = QDir::fromNativeSeparators(path.trimmed());
    if (path.size() >= 2 && path.startsWith(QLatin1Char('"')) && path.endsWith(QLatin1Char('"')))
        path = path.mid(1, path.size() - 2);
    if (path.size() < 3 || !path[0].isLetter() || path[1] != QLatin1Char(':') || path[2] != QLatin1Char('/'))
        return {};
    const QFileInfo executable(path);
    if (!executable.isAbsolute()
        || executable.fileName().compare(QStringLiteral("chrome.exe"), Qt::CaseInsensitive) != 0
        || !executable.isFile())
        return {};
    return executable.canonicalFilePath();
}

QString chromeExecutable()
{
    const QString appPath = QStringLiteral("\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\chrome.exe");
    for (const auto &root : {QStringLiteral("HKEY_CURRENT_USER"), QStringLiteral("HKEY_LOCAL_MACHINE")}) {
        for (auto format : {QSettings::Registry64Format, QSettings::Registry32Format}) {
            const QSettings registry(root + appPath, format);
            const QString executable = chromeExecutableAt(registry.value(QStringLiteral(".")).toString());
            if (!executable.isEmpty())
                return executable;
        }
    }
    for (const char *variable : {"LOCALAPPDATA", "ProgramFiles", "ProgramFiles(x86)"}) {
        const QString directory = qEnvironmentVariable(variable);
        if (directory.isEmpty())
            continue;
        for (const auto &channel : {QStringLiteral("Chrome"), QStringLiteral("Chrome Beta"),
                                    QStringLiteral("Chrome Dev"), QStringLiteral("Chrome SxS")}) {
            const QString executable = chromeExecutableAt(
                QDir(directory).filePath(QStringLiteral("Google/%1/Application/chrome.exe").arg(channel)));
            if (!executable.isEmpty())
                return executable;
        }
    }
    return {};
}

QUrl chromeExtensionStoreUrl(const QVariantMap &status)
{
    const QUrl url(status.value(QStringLiteral("storeUrl")).toString(), QUrl::StrictMode);
    static const QRegularExpression listing(QStringLiteral("\\A/detail/auralis-download-manager/[a-p]{32}\\z"));
    if (url.isValid() && url.scheme() == QStringLiteral("https")
        && url.authority() == QStringLiteral("chromewebstore.google.com")
        && !url.hasQuery() && !url.hasFragment()
        && listing.match(url.path(QUrl::FullyEncoded)).hasMatch())
        return url;
    return {};
}
#endif
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
    m_updateJobs.setMaxThreadCount(1);
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
    m_updateJobs.waitForDone();
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
    if (local.isEmpty()) {
        const QString shellAction = command.value(QStringLiteral("shellAction")).toString();
        if (m_smoke && shellAction.startsWith(QStringLiteral("update-")))
            return failure(tr("External update requests are disabled during the installation smoke test."));
        if (shellAction == QStringLiteral("update-check")) {
            auto request = command;
            request.insert(QStringLiteral("currentVersion"), version());
            return exchange(request);
        }
        if (shellAction == QStringLiteral("update-install")) {
            const auto backup = exchange({{QStringLiteral("query"), QStringLiteral("glass-full-backup-status")}});
            const auto status = backup.value(QStringLiteral("result")).toMap();
            if (!status.contains(QStringLiteral("pending")))
                return failure(tr("Could not confirm that Auralis is ready to close for the update."));
            if (status.value(QStringLiteral("pending")).toBool())
                return failure(tr("Wait for the download backup or restore to finish before installing the update."));
        }
        return exchange(command);
    }
    if (local == QStringLiteral("startupSettings"))
        return result(startupSettings());
    if (local == QStringLiteral("setStartupSettings"))
        return setStartupSettings(command);
    if (local == QStringLiteral("chromeExtensionStatus") || local == QStringLiteral("openChromeExtensionStore")
        || local == QStringLiteral("openChromeExtensions")) {
        const bool openStore = local == QStringLiteral("openChromeExtensionStore");
        const bool manage = local == QStringLiteral("openChromeExtensions");
#ifdef Q_OS_WIN
        if (!m_smoke) {
            const QString chrome = chromeExecutable();
            if (manage) {
                if (chrome.isEmpty())
                    return failure(tr("Google Chrome was not found."));
                if (!QProcess::startDetached(chrome, {QStringLiteral("chrome://extensions/")}))
                    return failure(tr("Could not open Chrome’s extension manager."));
                return result(QVariantMap{{QStringLiteral("ok"), true}});
            }
            const auto response = exchange({{QStringLiteral("shellAction"), QStringLiteral("chrome-extension-status")}});
            if (response.contains(QStringLiteral("error")))
                return response;
            auto status = response.value(QStringLiteral("result")).toMap();
            const QUrl store = chromeExtensionStoreUrl(status);
            if (!openStore) {
                status.insert(QStringLiteral("chromeDetected"), !chrome.isEmpty());
                status.insert(QStringLiteral("storeUrl"), store.toString(QUrl::FullyEncoded));
                return result(status);
            }
            if (store.isEmpty())
                return failure(tr("Could not verify the Auralis Chrome Web Store listing."));
            if (!chrome.isEmpty() && QProcess::startDetached(chrome, {store.toString(QUrl::FullyEncoded)}))
                return result(QVariantMap{{QStringLiteral("ok"), true}, {QStringLiteral("openedInChrome"), true}});
            // Run the desktop URL handoff on the application's GUI thread.
            return result(QVariantMap{{QStringLiteral("storeUrl"), store.toString(QUrl::FullyEncoded)}});
        }
#endif
        if (openStore || manage)
            return failure(tr("Opening the Chrome Web Store is unavailable here."));
        return result(QVariantMap{{QStringLiteral("chromeDetected"), false},
                                  {QStringLiteral("connectedRecently"), false},
                                  {QStringLiteral("storePreviouslyConnected"), false},
                                  {QStringLiteral("chromePreviouslyConnected"), false},
                                  {QStringLiteral("storeUrl"), QString()}});
    }
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
    const auto deliver = [this, callback, shellAction, local](const QVariantMap &response) {
        QVariant value = response.value(QStringLiteral("result"));
        QString error = response.value(QStringLiteral("error")).toString();
        if (error.isEmpty())
            error = value.toMap().value(QStringLiteral("error")).toString();
#ifdef Q_OS_WIN
        if (error.isEmpty() && local == QStringLiteral("openChromeExtensionStore")
            && !value.toMap().value(QStringLiteral("ok")).toBool()) {
            const QUrl store = chromeExtensionStoreUrl(value.toMap());
            if (!store.isEmpty() && QDesktopServices::openUrl(store))
                value = QVariantMap{{QStringLiteral("ok"), true}, {QStringLiteral("openedInChrome"), false}};
            else
                error = tr("Could not open the Auralis Chrome Web Store listing.");
        }
#endif
        if (callback.isCallable()) {
            callback.call({m_scriptEngine->toScriptValue(value),
                           error.isEmpty() ? QJSValue(QJSValue::NullValue) : QJSValue(error)});
        } else if (!error.isEmpty()) {
            emit operationFailed(error);
        }
        if (error.isEmpty() && shellAction == QStringLiteral("update-install")
            && value.toMap().value(QStringLiteral("ok")).toBool())
            requestQuit();
    };
    if (local == QStringLiteral("openExtensionFolder")) {
        const auto path = QCoreApplication::applicationDirPath() + QStringLiteral("/auralis-extension");
        deliver(openFolder(path) ? result(QVariantMap{{QStringLiteral("ok"), true}})
                                 : failure(tr("Could not open the bundled extension folder.")));
        return;
    }
    // This ABI call reads the updater's in-memory counters without waiting on its transfer worker.
    if (shellAction == QStringLiteral("update-progress")) {
        deliver(exchange(command));
        return;
    }

    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, deliver, changesDownloads] {
        deliver(watcher->result());
        watcher->deleteLater();
        if (changesDownloads)
            refresh();
    });
    QThreadPool *pool = shellAction.startsWith(QStringLiteral("update-")) ? &m_updateJobs
        : local.isEmpty() ? &m_commands : &m_localJobs;
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

QUrl Engine::localMediaUrl(const QUrl &url) const
{
    if (!url.isLocalFile() || !url.host().isEmpty())
        return {};
    const auto path = QDir::fromNativeSeparators(url.toLocalFile());
    if (!QDir::isAbsolutePath(path) || path.startsWith(QStringLiteral("//")) || path.contains(QChar::Null))
        return {};
#ifdef Q_OS_WIN
    if (path.size() < 3 || !path.at(0).isLetter() || path.at(1) != u':' || path.at(2) != u'/')
        return {};
#endif
    return QUrl::fromLocalFile(path);
}

QUrl Engine::localFileUrl(const QString &path) const
{
    return QFileInfo(path).isAbsolute() ? QUrl::fromLocalFile(path) : QUrl();
}

void Engine::dragCompletedFile(QWindow *window, quint64 id, const QJSValue &callback)
{
#ifdef Q_OS_WIN
    if (window && window->isVisible()) {
        const auto hwnd = static_cast<qlonglong>(window->winId());
        const QVariantMap source{{QStringLiteral("hwnd"), hwnd},
                                 {QStringLiteral("pid"), QCoreApplication::applicationPid()}};
        request({{QStringLiteral("action"), QStringLiteral("glass-drag-file")},
                 {QStringLiteral("ids"), QVariantList{QVariant::fromValue(id)}},
                 {QStringLiteral("queue"), QString::fromUtf8(QJsonDocument::fromVariant(source).toJson(QJsonDocument::Compact))}},
                callback);
        return;
    }
    const QString error = tr("The download window is no longer available.");
#else
    Q_UNUSED(window);
    Q_UNUSED(id);
    const QString error = tr("File dragging is available on Windows.");
#endif
    if (callback.isCallable())
        callback.call({QJSValue(QJSValue::NullValue), QJSValue(error)});
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

void Engine::notifyUpdate(const QString &version)
{
    if (!m_smoke && !version.isEmpty())
        emit updateNotificationRequested(version);
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

void Engine::installInteractiveResize(QWindow *window, int borderSize, int cornerSize) const
{
    FrameResize::install(window, borderSize, cornerSize);
}
