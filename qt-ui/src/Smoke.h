#pragma once

#include <QObject>
#include <QPointer>
#include <QSize>
#include <QTcpServer>
#include <QString>

#include <functional>

class Engine;
class QQuickWindow;

class EngineSmoke final : public QObject
{
    Q_OBJECT

public:
    using TrayCheck = std::function<void(std::function<void(bool)>)>;
    EngineSmoke(Engine &engine, TrayCheck checkTray);

private:
    enum class Step {
        WaitingForConfirmation, Starting, CheckingInitialTrayMenu, WaitingForPause,
        WaitingForResume, CheckingResumedTrayMenu, Finishing, Stopped
    };

    void startDownload();
    void confirmDownload();
    void inspectTransfers();
    void observeTransferWindow(qulonglong id);
    void resizeTransferWindow();
    bool verifyCompletion(const QVariantMap &download);
    void verifyTrayMenu(bool resumed);
    bool pauseTransfer();
    void fail(const QString &message);
    void verifyShutdown(bool clean);
    void serve();

    Engine &m_engine;
    TrayCheck m_checkTray;
    QTcpServer m_server;
    QPointer<QQuickWindow> m_window;
    QMetaObject::Connection m_frameConnection;
    QString m_name;
    QString m_url;
    QSize m_expectedProgressSize;
    Step m_step = Step::WaitingForConfirmation;
    bool m_started = false;
    bool m_framePresented = false;
    bool m_resizeVerified = false;
    bool m_transferVerified = false;
};
