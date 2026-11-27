#include "Engine.h"
#include "BrowserSetup.h"
#include "FrameResize.h"
#include "LocalFiles.h"
#include "WindowOutline.h"
#include "WindowShadow.h"
#ifdef AURALIS_STORE_EDITION
#include "StoreStartup.h"
#endif

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJSEngine>
#include <QJsonDocument>
#include <QLocale>
#include <QPolygonF>
#include <QProcess>
#include <QQmlEngine>
#include <QRegion>
#include <QSettings>
#include <QSystemTrayIcon>
#include <QTranslator>
#include <QRegularExpression>
#include <QWindow>
#include <QtConcurrentRun>


#ifdef Q_OS_WIN
#include "PanelBackdrop.h"
#include <QJsonObject>
#include <QRandomGenerator>
#include <QVersionNumber>
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
#ifdef AURALIS_STORE_EDITION
    return StoreStartup::settings();
#elif defined(Q_OS_WIN)
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
#ifdef AURALIS_STORE_EDITION
    return StoreStartup::save(command);
#elif defined(Q_OS_WIN)
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
    m_updateJobs.setMaxThreadCount(1);
    m_releaseHistoryJobs.setMaxThreadCount(1);
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
#ifdef Q_OS_WIN
    m_releaseSocket.setMaxAllowedIncomingFrameSize(256);
    m_releaseSocket.setMaxAllowedIncomingMessageSize(256);
    m_releaseSocketTimer.setSingleShot(true);
    connect(&m_releaseSocketTimer, &QTimer::timeout, this, [this] {
        if (!m_releaseHintsEnabled)
            return;
        if (m_releaseSocket.state() == QAbstractSocket::UnconnectedState) {
            m_releaseSocketTimer.start(15000);
            m_releaseSocket.open(QUrl(QStringLiteral("wss://auralis-release-push.auralis-updates.workers.dev/events")));
        } else if (m_releaseSocket.state() != QAbstractSocket::ConnectedState) {
            m_releaseSocket.abort();
            if (!m_releaseSocketTimer.isActive())
                scheduleReleaseReconnect();
        }
    });
    connect(&m_releaseSocket, &QWebSocket::connected, this, [this] {
        m_releaseSocketTimer.stop();
        m_releaseReconnectDelay = 2000;
        emit releaseUpdateHint({});
    });
    connect(&m_releaseSocket, &QWebSocket::disconnected, this, &Engine::scheduleReleaseReconnect);
    connect(&m_releaseSocket, &QWebSocket::textMessageReceived, this, [this](const QString &message) {
        if (!m_releaseHintsEnabled)
            return;
        const auto hint = QJsonDocument::fromJson(message.toUtf8()).object();
        const auto version = hint.value(QStringLiteral("version")).toString();
        const auto parsed = QVersionNumber::fromString(version);
        if (hint.value(QStringLiteral("type")).toString() == QStringLiteral("release")
            && parsed.segmentCount() == 3 && parsed.toString() == version
            && parsed > QVersionNumber::fromString(this->version())) {
            emit releaseUpdateHint(version);
        }
    });
#endif
}

Engine::~Engine()
{
    setReleaseUpdateHintsEnabled(false);
    // Worker lambdas borrow the engine and profile. Wait while they still exist.
    m_commands.waitForDone();
    m_localJobs.waitForDone();
    m_updateJobs.waitForDone();
    m_releaseHistoryJobs.waitForDone();
    m_serviceThread.waitForDone();
}

QString Engine::version() const { return QStringLiteral(AURALIS_VERSION); }

void Engine::initializeInterfaceLanguage()
{
    const auto preference = exchange({{QStringLiteral("shellAction"), QStringLiteral("interface-language")}});
    applyInterfaceLanguage(preference.value(QStringLiteral("result")).toString());
    setStatus(tr("Starting download engine"));
}

void Engine::applyInterfaceLanguage(const QString &language)
{
    QString code = language;
    static const QRegularExpression localePattern(QStringLiteral("^[a-z]{2,3}(-[a-z0-9]{2,8})*$"));
    if (!localePattern.match(code).hasMatch()) code = QStringLiteral("en");
    QString localeName = code;
    localeName.replace(QLatin1Char('-'), QLatin1Char('_'));
    if (m_interfaceLanguage == code)
        return;

    std::unique_ptr<QTranslator> translator;
    if (code != QStringLiteral("en")) {
        translator = std::make_unique<QTranslator>();
        if (!translator->load(QStringLiteral(":/auralis/i18n/auralis_%1.qm").arg(code))) {
            qWarning("Could not load the bundled Auralis translation for %s", qPrintable(localeName));
            return;
        }
    }
    if (m_translator)
        QCoreApplication::removeTranslator(m_translator.get());
    m_translator = std::move(translator);
    if (m_translator)
        QCoreApplication::installTranslator(m_translator.get());
    const QLocale locale(localeName);
    QLocale::setDefault(locale);
    QGuiApplication::setLayoutDirection(locale.textDirection());
    m_interfaceLanguage = code;
    if (auto *qml = qobject_cast<QQmlEngine *>(m_scriptEngine))
        qml->retranslate();
    emit interfaceLanguageChanged();
}

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
#ifdef AURALIS_STORE_EDITION
    // Guard every bridge path, including the fast update-progress request.
    if (command.value(QStringLiteral("shellAction")).toString().startsWith(QStringLiteral("update-")))
        return failure(tr("This edition is updated by Microsoft Store. Open the Store to check for updates."));
#endif
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
        if (m_smoke && shellAction == QStringLiteral("clipboard-prefill"))
            return result(QVariant());
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
    if (local == QStringLiteral("startupSettings")) {
        const auto settings = startupSettings();
        return settings.contains(QStringLiteral("error")) ? settings : result(settings);
    }
    if (local == QStringLiteral("setStartupSettings"))
        return setStartupSettings(command);
    const bool browserStatus = local == QStringLiteral("browserExtensionStatus");
    const bool openStore = local == QStringLiteral("openBrowserExtensionStore");
    const bool offerExtension = local == QStringLiteral("offerBrowserExtension");
    const bool removeOffer = local == QStringLiteral("removeBrowserExtensionOffer");
    const bool removeLegacyPolicy = local == QStringLiteral("removeLegacyBrowserExtensionPolicy");
    const bool repairHost = local == QStringLiteral("registerBrowserHost");
    if (storeEdition() && (offerExtension || removeOffer || removeLegacyPolicy))
        return failure(tr("Install the browser extension from its marketplace. This Store edition does not change browser extension policies. Use the original installer to remove a policy left by an older installation."));
    if (browserStatus || openStore || offerExtension || removeOffer || removeLegacyPolicy || repairHost) {
        QVariantMap status{{QStringLiteral("browser"), QString()}, {QStringLiteral("browserId"), QString()},
                           {QStringLiteral("browserSupported"), false}, {QStringLiteral("extensionPresent"), false},
                           {QStringLiteral("connectedRecently"), false}, {QStringLiteral("storePreviouslyConnected"), false},
                           {QStringLiteral("browserPreviouslyConnected"), false}, {QStringLiteral("storeUrl"), QString()},
                           {QStringLiteral("nativeHostRegistered"), false}, {QStringLiteral("nativeHostCanRegister"), false},
                           {QStringLiteral("nativeHostProblem"), QString()}, {QStringLiteral("externalOfferAvailable"), false},
                           {QStringLiteral("externalOfferRegistered"), false}, {QStringLiteral("externalOfferRemovable"), false},
                           {QStringLiteral("externalOfferProblem"), QString()}, {QStringLiteral("legacyPolicyRemovable"), false}};
#ifdef Q_OS_WIN
        if (!m_smoke) {
            const auto defaultHandler = BrowserSetup::defaultHttpsHandler();
            auto handler = defaultHandler;
            const auto selected = command.value(QStringLiteral("browserExecutable")).toString();
            QStringList executablePaths;
            QVariantList installedBrowsers;
            const auto addBrowser = [&](const BrowserSetup::Handler &candidate) {
                if (candidate.executable.isEmpty()
                    || executablePaths.contains(candidate.executable, Qt::CaseInsensitive))
                    return;
                executablePaths.push_back(candidate.executable);
                installedBrowsers.push_back(QVariantMap{{QStringLiteral("executable"), candidate.executable},
                                                        {QStringLiteral("name"), candidate.name}});
                if (candidate.executable.compare(selected, Qt::CaseInsensitive) == 0 || handler.executable.isEmpty())
                    handler = candidate;
            };
            addBrowser(defaultHandler);
            if (browserStatus || !selected.isEmpty()) {
                const auto response = exchange({{QStringLiteral("shellAction"), QStringLiteral("installed-browsers")}});
                for (const auto &entry : response.value(QStringLiteral("result")).toList()) {
                    const auto browser = entry.toMap();
                    addBrowser({BrowserSetup::validatedBrowserExecutable(browser.value(QStringLiteral("executable")).toString()),
                                browser.value(QStringLiteral("name")).toString()});
                }
                if (!selected.isEmpty() && !executablePaths.contains(selected, Qt::CaseInsensitive) && !browserStatus)
                    return failure(tr("This browser is no longer available. Choose an installed browser."));
            }
            status.insert(QStringLiteral("browser"), handler.name);
            status.insert(QStringLiteral("browserExecutable"), handler.executable);
            status.insert(QStringLiteral("installedBrowsers"), installedBrowsers);
            const bool isDefault = !handler.executable.isEmpty()
                && handler.executable.compare(defaultHandler.executable, Qt::CaseInsensitive) == 0;
            const auto browserStatusForHandler = [this, &handler] {
                return exchange({{QStringLiteral("shellAction"), QStringLiteral("browser-extension-status")},
                                 {QStringLiteral("executable"), handler.executable}});
            };
            const auto response = browserStatusForHandler();
            if (response.contains(QStringLiteral("error")))
                return response;
            const auto browserResult = response.value(QStringLiteral("result")).toMap();
            const auto browserId = browserResult.value(QStringLiteral("browserId")).toString();
            const auto expectedBrowser = command.value(QStringLiteral("expectedBrowser")).toString();
            const bool browserSpecified = (openStore || repairHost) && !expectedBrowser.isEmpty();
            if ((offerExtension || removeOffer || removeLegacyPolicy || browserSpecified) && expectedBrowser != browserId)
                return failure(tr("The browser changed. Review browser setup again."));
            if (!browserResult.value(QStringLiteral("browserSupported")).toBool()) {
                if (browserStatus)
                    return result(status);
                // Preserve manual repair for other bundles and browsers.
                if (repairHost) {
                    const auto error = BrowserSetup::registerNativeHost({}, true);
                    return error.isEmpty() ? result(QVariantMap{{QStringLiteral("ok"), true}}) : failure(error);
                }
                return failure(tr("This browser is unable to use the Auralis listing in the Chrome Web Store."));
            }
            const QString store = BrowserSetup::storeUrl().toString(QUrl::FullyEncoded);
            if (browserStatus) {
                for (auto it = browserResult.constBegin(); it != browserResult.constEnd(); ++it)
                    status.insert(it.key(), it.value());
                const auto host = BrowserSetup::nativeHostStatus(browserId);
                const bool canPrepare = host.registered || (host.canRegister && !host.anotherApplication);
                status.insert(QStringLiteral("storeUrl"), store);
                status.insert(QStringLiteral("nativeHostRegistered"), host.registered);
                status.insert(QStringLiteral("nativeHostCanRegister"), host.canRegister);
                status.insert(QStringLiteral("nativeHostProblem"), host.problem);
                status.insert(QStringLiteral("legacyPolicyRemovable"), !storeEdition() && BrowserSetup::legacyPolicyRemovable(browserId));
                if (browserId == QStringLiteral("chrome") && isDefault) {
                    const auto offer = BrowserSetup::chromeOfferStatus();
                    status.insert(QStringLiteral("externalOfferAvailable"), !storeEdition() && offer.available && canPrepare);
                    status.insert(QStringLiteral("externalOfferRegistered"), offer.registered);
                    status.insert(QStringLiteral("externalOfferRemovable"), !storeEdition() && offer.removable);
                    status.insert(QStringLiteral("externalOfferProblem"), offer.available && !canPrepare ? host.problem : offer.problem);
                }
                return result(status);
            }
            if (repairHost) {
                const auto error = BrowserSetup::registerNativeHost(browserId, true);
                return error.isEmpty() ? result(QVariantMap{{QStringLiteral("ok"), true},
                    {QStringLiteral("nativeHostRegistered"), true}}) : failure(error);
            }
            const bool requiresDefault = selected.isEmpty() || offerExtension || removeOffer;
            const auto browserStillSelected = [&handler, requiresDefault] {
                const auto current = requiresDefault ? BrowserSetup::defaultHttpsHandler().executable
                    : BrowserSetup::validatedBrowserExecutable(handler.executable);
                return current.compare(handler.executable, Qt::CaseInsensitive) == 0;
            };
            if (removeLegacyPolicy) {
                bool approvalRequired = false;
                auto error = BrowserSetup::removeLegacyPolicy(browserId, &approvalRequired);
                if (approvalRequired)
                    error = BrowserSetup::removeLegacyChromePolicyWithAdministratorApproval();
                if (!error.isEmpty())
                    return failure(error);
                const auto arguments = BrowserSetup::browserPolicyRefreshArguments(browserId, handler.executable);
                const bool refreshRequested = !arguments.isEmpty() && browserStillSelected()
                    && QProcess::startDetached(handler.executable, arguments);
                return result(QVariantMap{{QStringLiteral("ok"), true}, {QStringLiteral("legacyPolicyRemoved"), true},
                                          {QStringLiteral("refreshRequested"), refreshRequested}});
            }
            if ((offerExtension || removeOffer) && (browserId != QStringLiteral("chrome") || !isDefault))
                return failure(tr("Chrome can offer the extension only when it is your Windows default browser."));
            if (removeOffer) {
                const auto error = BrowserSetup::removeChromeOffer();
                if (!error.isEmpty())
                    return failure(error);
                return result(QVariantMap{{QStringLiteral("ok"), true}, {QStringLiteral("offerRemoved"), true}});
            }
            if (offerExtension) {
                const auto extensionDetected = [](const QVariantMap &value) {
                    return value.value(QStringLiteral("extensionDiscovery")).toString() != QStringLiteral("missing")
                        && (value.value(QStringLiteral("extensionPresent")).toBool()
                            || value.value(QStringLiteral("connectedRecently")).toBool());
                };
                const auto alreadyInstalled = [] {
                    return result(QVariantMap{{QStringLiteral("ok"), true}, {QStringLiteral("alreadyInstalled"), true}});
                };
                if (extensionDetected(browserResult))
                    return alreadyInstalled();
                const auto offer = BrowserSetup::chromeOfferStatus();
                if (!offer.available)
                    return failure(offer.problem);
                const auto registrationError = BrowserSetup::registerNativeHost(browserId, false);
                if (!registrationError.isEmpty())
                    return failure(registrationError);
                const auto rechecked = browserStatusForHandler();
                if (rechecked.contains(QStringLiteral("error")))
                    return rechecked;
                if (!browserStillSelected())
                    return failure(tr("The Windows default browser changed. Review browser setup again."));
                if (extensionDetected(rechecked.value(QStringLiteral("result")).toMap()))
                    return alreadyInstalled();
                const auto offerError = BrowserSetup::registerChromeOffer();
                if (!offerError.isEmpty())
                    return failure(offerError);
                const bool browserOpened = browserStillSelected()
                    && QProcess::startDetached(handler.executable, QStringList{});
                return result(QVariantMap{{QStringLiteral("ok"), true}, {QStringLiteral("offerRegistered"), true},
                                          {QStringLiteral("browserOpened"), browserOpened}, {QStringLiteral("pending"), true}});
            }
            const auto registrationError = BrowserSetup::registerNativeHost(browserId, false);
            if (!browserStillSelected() || !QProcess::startDetached(handler.executable, {store}))
                return failure(tr("Could not open the selected browser."));
            QVariantMap opened{{QStringLiteral("ok"), true}, {QStringLiteral("openedInBrowser"), true},
                               {QStringLiteral("nativeHostRegistered"), registrationError.isEmpty()}};
            if (!registrationError.isEmpty())
                opened.insert(QStringLiteral("message"), registrationError);
            return result(opened);
        }
#endif
        return browserStatus ? result(status) : failure(tr("Browser setup is unavailable here."));
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
#ifdef Q_OS_WIN
    if (!m_smoke) {
        m_localJobs.start([this] {
            if (!BrowserSetup::isInstalledApplication())
                return;
            const auto handler = BrowserSetup::defaultHttpsHandler();
            if (handler.executable.isEmpty())
                return;
            const auto status = exchange({{QStringLiteral("shellAction"), QStringLiteral("browser-extension-status")},
                                          {QStringLiteral("executable"), handler.executable}});
            const auto browser = status.value(QStringLiteral("result")).toMap();
            if (browser.value(QStringLiteral("browserSupported")).toBool())
                BrowserSetup::registerNativeHost(browser.value(QStringLiteral("browserId")).toString(), false);
        });
    }
#endif
    m_timer.start();
    refresh();
}

void Engine::request(const QVariantMap &command) { request(command, QJSValue()); }

void Engine::request(const QVariantMap &command, const QJSValue &callback)
{
    const QString local = command.value(QStringLiteral("local")).toString();
    const QString shellAction = command.value(QStringLiteral("shellAction")).toString();
    const bool installingUpdate = shellAction == QStringLiteral("update-install");
    const bool changesDownloads = local.isEmpty() && shellAction.isEmpty()
        && !command.contains(QStringLiteral("query"));
    const QString language = changesDownloads
        && command.value(QStringLiteral("action")).toString() == QStringLiteral("glass-setting")
        && command.value(QStringLiteral("category")).toString() == QStringLiteral("language")
        ? command.value(QStringLiteral("queue")).toString() : QString();
    const auto deliver = [this, callback, installingUpdate, language](const QVariantMap &response) {
        const QVariant value = response.value(QStringLiteral("result"));
        const QVariantMap data = value.toMap();
        QString error = response.value(QStringLiteral("error")).toString();
        if (error.isEmpty())
            error = data.value(QStringLiteral("error")).toString();
        if (error.isEmpty() && !language.isEmpty() && data.value(QStringLiteral("saved")).toBool())
            applyInterfaceLanguage(language);
        if (callback.isCallable()) {
            callback.call({m_scriptEngine->toScriptValue(value),
                           error.isEmpty() ? QJSValue(QJSValue::NullValue) : QJSValue(error)});
        } else if (!error.isEmpty()) {
            emit operationFailed(error);
        }
        if (error.isEmpty() && installingUpdate && data.value(QStringLiteral("ok")).toBool())
            requestQuit();
    };
    if (installingUpdate && (m_updateInstallPending || m_quitting)) {
        deliver(failure(tr("Auralis is already closing or preparing an update.")));
        return;
    }
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

    if (installingUpdate)
        m_updateInstallPending = true;
    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher, deliver, changesDownloads, installingUpdate] {
        deliver(watcher->result());
        if (installingUpdate)
            m_updateInstallPending = false;
        watcher->deleteLater();
        if (changesDownloads)
            refresh();
    });
    const bool clipboardPrefill = shellAction == QStringLiteral("clipboard-prefill");
    QThreadPool *pool = shellAction == QStringLiteral("update-history") ? &m_releaseHistoryJobs
        : shellAction.startsWith(QStringLiteral("update-")) ? &m_updateJobs
        : local.isEmpty() && !clipboardPrefill ? &m_commands : &m_localJobs;
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
    const QString language = visuals.value(QStringLiteral("interfaceLanguage")).toString();
    if (!language.isEmpty())
        applyInterfaceLanguage(language);
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
    }
}

void Engine::requestRestart()
{
    if (m_updateInstallPending) {
        emit restartFailed(tr("Wait for Auralis to finish preparing the update."));
        return;
    }
    if (!m_smoke)
        requestQuit(RestartExitCode);
}

void Engine::requestQuit(int exitCode)
{
    if (m_quitting)
        return;
    m_exitCode = exitCode;
    m_quitting = true;
    emit quittingChanged();
    if (!running()) {
        QCoreApplication::exit(m_exitCode);
        return;
    }
    auto *watcher = new QFutureWatcher<QVariantMap>(this);
    connect(watcher, &QFutureWatcherBase::finished, this, [this, watcher] {
        const auto response = watcher->result();
        watcher->deleteLater();
        const QString error = response.value(QStringLiteral("error")).toString();
        if (!error.isEmpty() && running()) {
            m_quitting = false;
            emit quittingChanged();
            if (m_exitCode == RestartExitCode)
                emit restartFailed(error);
            else
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
    const auto nativePath = QDir::fromNativeSeparators(path.trimmed());
    if (nativePath.isEmpty() || nativePath.contains(QChar::Null))
        return {};
    const QFileInfo info(nativePath);
    const auto absolutePath = info.isAbsolute()
        ? info.absoluteFilePath()
        : QDir::home().absoluteFilePath(nativePath);
    return QUrl::fromLocalFile(QDir::cleanPath(absolutePath));
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

void Engine::setReleaseUpdateHintsEnabled(bool enabled)
{
#ifdef Q_OS_WIN
    enabled = enabled && !m_smoke;
#ifdef AURALIS_STORE_EDITION
    enabled = false;
#endif
    if (enabled == m_releaseHintsEnabled)
        return;
    m_releaseHintsEnabled = enabled;
    m_releaseReconnectDelay = 2000;
    if (enabled) {
        m_releaseSocketTimer.start(0);
    } else {
        m_releaseSocketTimer.stop();
        m_releaseSocket.abort();
    }
#else
    Q_UNUSED(enabled);
#endif
}

#ifdef Q_OS_WIN
void Engine::scheduleReleaseReconnect()
{
    if (!m_releaseHintsEnabled)
        return;
    const int jitter = QRandomGenerator::global()->bounded(1000);
    m_releaseSocketTimer.start(m_releaseReconnectDelay + jitter);
    m_releaseReconnectDelay = qMin(60000, m_releaseReconnectDelay * 2);
}
#endif

bool Engine::applyBackdrop(QWindow *window, bool enabled, bool dark) const
{
#ifdef Q_OS_WIN
    if (!window || !window->isVisible() || m_smoke)
        return false;
    const auto hwnd = reinterpret_cast<HWND>(window->winId());
    constexpr DWORD SystemBackdropType = 38;
    constexpr DWORD ImmersiveDarkMode = 20;
    constexpr int NoBackdrop = 1;
    constexpr int DesktopAcrylic = 3;
    // Acrylic belongs to the Windows compositor and can extend beyond the Qt scene's shape.
    const bool shaped = window->property("frameCornerRadius").toInt() > 0;
    if (enabled && !shaped && GetForegroundWindow() == hwnd) {
        const BOOL darkMode = dark;
        DwmSetWindowAttribute(hwnd, ImmersiveDarkMode, &darkMode, sizeof darkMode);
        const MARGINS extend{-1, -1, -1, -1};
        if (SUCCEEDED(DwmExtendFrameIntoClientArea(hwnd, &extend))
            && SUCCEEDED(DwmSetWindowAttribute(hwnd, SystemBackdropType, &DesktopAcrylic, sizeof DesktopAcrylic)))
            return true;
    }

    // Reset both parts even if the system backdrop attribute is unavailable on this Windows version.
    DwmSetWindowAttribute(hwnd, SystemBackdropType, &NoBackdrop, sizeof NoBackdrop);
    const MARGINS reset{0, 0, 0, 0};
    DwmExtendFrameIntoClientArea(hwnd, &reset);
    return false;
#else
    Q_UNUSED(window);
    Q_UNUSED(enabled);
    Q_UNUSED(dark);
    return false;
#endif
}

bool Engine::applyPanelBackdrop(QWindow *window, const QVariantList &panels, bool enabled, const QString &finish) const
{
#ifdef Q_OS_WIN
    return !m_smoke && PanelBackdrop::update(window, panels, enabled, finish);
#else
    Q_UNUSED(window);
    Q_UNUSED(panels);
    Q_UNUSED(enabled);
    Q_UNUSED(finish);
    return false;
#endif
}

void Engine::setWindowCornerRadius(QWindow *window, int radius) const
{
    if (!window)
        return;
    const auto configuredCorners = window->property("frameCornerMask");
    const int corners = configuredCorners.isValid() ? configuredCorners.toInt() & 15 : 15;
    const auto state = window->windowStates();
    const bool shaped = radius > 0 && corners && (window->flags() & Qt::FramelessWindowHint)
        && !state.testAnyFlags(Qt::WindowMaximized | Qt::WindowFullScreen);
#ifdef Q_OS_WIN
    const bool wasShaped = !window->mask().isEmpty();
    if (window->isVisible() && shaped != wasShaped) {
        if (shaped)
            applyBackdrop(window, false, false);
        // Prevent DWM from drawing a rectangular non-client frame around a shaped window.
        const auto hwnd = reinterpret_cast<HWND>(window->winId());
        const DWMNCRENDERINGPOLICY policy = shaped ? DWMNCRP_DISABLED : DWMNCRP_USEWINDOWSTYLE;
        DwmSetWindowAttribute(hwnd, DWMWA_NCRENDERING_POLICY, &policy, sizeof policy);
    }
#endif
    if (!shaped) {
        WindowOutline::configureAntialiasing(window, {});
        if (!window->mask().isEmpty())
            window->setMask({});
#ifdef Q_OS_WIN
        if (window->property("acrylicMode").toBool())
            WindowShadow::clearFrame(window);
        else
            WindowShadow::update(window, QSizeF(0, 0), 0);
#endif
        return;
    }
    if (window->size().isEmpty())
        return;

    const qreal width = window->width();
    const qreal height = window->height();
    const QSizeF reach(qMin(qreal(radius), width / 2), qMin(radius * (113.0 / 114.0), height / 2));
    const bool antialiasing = WindowOutline::configureAntialiasing(window, reach, corners);
    // Keep the native input mask, but leave room for the GPU to draw its fractional edge
    // inside it. Shaped Windows still have no native acrylic or non-client frame.
    const qreal fringe = antialiasing ? 2 : 0;
    const QRegion mask(WindowOutline::framePolygon(QRectF(0, 0, width, height),
                                                   reach, corners, fringe).toPolygon());
    if (mask != window->mask())
        window->setMask(mask);
#ifdef Q_OS_WIN
    WindowShadow::update(window, reach, corners);
#endif
}

void Engine::installInteractiveResize(QWindow *window, int borderSize, int cornerSize) const
{
    FrameResize::install(window, borderSize, cornerSize);
}
