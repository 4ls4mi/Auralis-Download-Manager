#pragma once

#include <QObject>
#include <QFutureWatcher>
#include <QJSValue>
#include <QLibrary>
#include <QThreadPool>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>
#include <memory>

#ifdef Q_OS_WIN
#include <QtWebSockets/QWebSocket>
#endif

class QJSEngine;
class QTranslator;
class QWindow;

class Engine final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap dashboard READ dashboard NOTIFY dashboardChanged)
    Q_PROPERTY(QVariantMap visuals READ visuals NOTIFY visualsChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY readyChanged)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged)
    Q_PROPERTY(QString dataDirectory READ dataDirectory CONSTANT)
    Q_PROPERTY(QString version READ version CONSTANT)
    Q_PROPERTY(bool storeEdition READ storeEdition CONSTANT)
    Q_PROPERTY(QString interfaceLanguage READ interfaceLanguage NOTIFY interfaceLanguageChanged)
    Q_PROPERTY(bool startHidden READ startHidden CONSTANT)
    Q_PROPERTY(bool trayAvailable READ trayAvailable CONSTANT)
    Q_PROPERTY(bool interactiveSetup READ interactiveSetup CONSTANT)
    Q_PROPERTY(bool quitting READ quitting NOTIFY quittingChanged)

public:
    static constexpr int RestartExitCode = 64;

    Engine(QJSEngine *scriptEngine, bool startHidden, bool smoke, QObject *parent = nullptr);

    ~Engine() override;

    QVariantMap dashboard() const { return m_dashboard; }
    QVariantMap visuals() const { return m_visuals; }
    bool ready() const { return m_ready; }
    QString status() const { return m_status; }
    QString dataDirectory() const { return m_profile; }
    QString version() const;
    bool storeEdition() const {
#ifdef AURALIS_STORE_EDITION
        return true;
#else
        return false;
#endif
    }
    QString interfaceLanguage() const { return m_interfaceLanguage; }
    bool startHidden() const { return m_startHidden; }
    bool trayAvailable() const;
    bool interactiveSetup() const { return !m_smoke; }
    bool running() const { return m_service.isRunning(); }
    bool quitting() const { return m_quitting; }

    void initializeInterfaceLanguage();
    void start();
    Q_INVOKABLE void request(const QVariantMap &command);
    Q_INVOKABLE void request(const QVariantMap &command, const QJSValue &callback);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void requestQuit(int exitCode = 0);
    Q_INVOKABLE void requestRestart();
    Q_INVOKABLE QString localPath(const QUrl &url) const;
    Q_INVOKABLE QUrl localMediaUrl(const QUrl &url) const;
    Q_INVOKABLE QUrl localFileUrl(const QString &path) const;
    Q_INVOKABLE void dragCompletedFile(QWindow *window, quint64 id, const QJSValue &callback);
    Q_INVOKABLE bool openPath(const QString &path) const;
    Q_INVOKABLE bool openFolder(const QString &path) const;
    Q_INVOKABLE void setTrayDownloadItems(const QVariantList &items) { emit trayDownloadItemsChanged(items); }
    Q_INVOKABLE void notifyUpdate(const QString &version);
    Q_INVOKABLE void setReleaseUpdateHintsEnabled(bool enabled);
    Q_INVOKABLE bool applyBackdrop(QWindow *window, bool enabled, bool dark) const;
    Q_INVOKABLE void setWindowCornerRadius(QWindow *window, int radius) const;
    Q_INVOKABLE void installInteractiveResize(QWindow *window, int borderSize, int cornerSize) const;

signals:
    void dashboardChanged();
    void visualsChanged();
    void trayDownloadItemsChanged(const QVariantList &items);
    void readyChanged();
    void statusChanged();
    void interfaceLanguageChanged();
    void operationFailed(const QString &message);
    void browserWindowRequested(const QString &target);
    void serviceStopped(bool clean);
    void updateNotificationRequested(const QString &version);
    void releaseUpdateHint(const QString &version);
    void quittingChanged();
    void restartFailed(const QString &message);

private:
    using Run = char *(*)();
    using Request = char *(*)(const unsigned char *, size_t);
    using Free = void (*)(char *);

    QVariantMap decode(char *output) const;
    QVariantMap exchange(const QVariantMap &command) const;
    QVariantMap dispatch(const QVariantMap &command) const;
    void setReady(bool ready);
    void setStatus(const QString &status);
    void applyInterfaceLanguage(const QString &language);
    void applySnapshot(const QVariantMap &response);
    void finishService();
#ifdef Q_OS_WIN
    void scheduleReleaseReconnect();
#endif

    QJSEngine *m_scriptEngine;
    QLibrary m_library;
    Run m_run = nullptr;
    Request m_request = nullptr;
    Free m_free = nullptr;
    QThreadPool m_commands;
    QThreadPool m_localJobs;
    QThreadPool m_updateJobs;
    QThreadPool m_releaseHistoryJobs;
    QThreadPool m_serviceThread;
    QFutureWatcher<QVariantMap> m_service;
    QTimer m_timer;
#ifdef Q_OS_WIN
    QTimer m_releaseSocketTimer;
    QWebSocket m_releaseSocket;
    int m_releaseReconnectDelay = 2000;
    bool m_releaseHintsEnabled = false;
#endif
    QVariantMap m_dashboard;
    QVariantMap m_visuals;
    QString m_profile;
    QString m_status;
    QString m_interfaceLanguage;
    std::unique_ptr<QTranslator> m_translator;
    bool m_ready = false;
    bool m_refreshing = false;
    bool m_quitting = false;
    bool m_updateInstallPending = false;
    bool m_firstSnapshot = true;
    bool m_startHidden;
    bool m_smoke;
    int m_exitCode = 0;
};
