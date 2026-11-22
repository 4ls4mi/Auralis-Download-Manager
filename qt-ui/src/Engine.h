#pragma once

#include <QObject>
#include <QFutureWatcher>
#include <QJSValue>
#include <QLibrary>
#include <QThreadPool>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

class QJSEngine;
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
    Q_PROPERTY(bool startHidden READ startHidden CONSTANT)
    Q_PROPERTY(bool trayAvailable READ trayAvailable CONSTANT)

public:
    Engine(QJSEngine *scriptEngine, bool startHidden, bool smoke, QObject *parent = nullptr);

    QVariantMap dashboard() const { return m_dashboard; }
    QVariantMap visuals() const { return m_visuals; }
    bool ready() const { return m_ready; }
    QString status() const { return m_status; }
    QString dataDirectory() const { return m_profile; }
    QString version() const;
    bool startHidden() const { return m_startHidden; }
    bool trayAvailable() const;
    bool running() const { return m_service.isRunning(); }

    void start();
    Q_INVOKABLE void request(const QVariantMap &command);
    Q_INVOKABLE void request(const QVariantMap &command, const QJSValue &callback);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void requestQuit(int exitCode = 0);
    Q_INVOKABLE QString localPath(const QUrl &url) const;
    Q_INVOKABLE bool openPath(const QString &path) const;
    Q_INVOKABLE bool openFolder(const QString &path) const;
    Q_INVOKABLE bool applyBackdrop(QWindow *window, bool enabled, bool dark) const;

signals:
    void dashboardChanged();
    void visualsChanged();
    void readyChanged();
    void statusChanged();
    void operationFailed(const QString &message);
    void browserWindowRequested(const QString &target);
    void serviceStopped(bool clean);

private:
    using Run = char *(*)();
    using Request = char *(*)(const unsigned char *, size_t);
    using Free = void (*)(char *);

    QVariantMap decode(char *output) const;
    QVariantMap exchange(const QVariantMap &command) const;
    QVariantMap dispatch(const QVariantMap &command) const;
    void setReady(bool ready);
    void setStatus(const QString &status);
    void applySnapshot(const QVariantMap &response);
    void finishService();

    QJSEngine *m_scriptEngine;
    QLibrary m_library;
    Run m_run = nullptr;
    Request m_request = nullptr;
    Free m_free = nullptr;
    QThreadPool m_commands;
    QThreadPool m_localJobs;
    QThreadPool m_serviceThread;
    QFutureWatcher<QVariantMap> m_service;
    QTimer m_timer;
    QVariantMap m_dashboard;
    QVariantMap m_visuals;
    QString m_profile;
    QString m_status;
    bool m_ready = false;
    bool m_refreshing = false;
    bool m_quitting = false;
    bool m_firstSnapshot = true;
    bool m_startHidden;
    bool m_smoke;
    int m_exitCode = 0;
};
