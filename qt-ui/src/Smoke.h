#pragma once

#include <QObject>
#include <QPointer>
#include <QTcpServer>
#include <QString>

class Engine;
class QQuickWindow;

class EngineSmoke final : public QObject
{
    Q_OBJECT

public:
    explicit EngineSmoke(Engine &engine);

private:
    enum class Step { Starting, WaitingForPause, WaitingForResume, Finishing, Stopped };

    void startDownload();
    void inspectTransfers();
    void observeTransferWindow(qulonglong id);
    bool pauseTransfer();
    void fail(const QString &message);
    void verifyShutdown(bool clean);
    void serve();

    Engine &m_engine;
    QTcpServer m_server;
    QPointer<QQuickWindow> m_window;
    QMetaObject::Connection m_frameConnection;
    QString m_name;
    Step m_step = Step::Starting;
    bool m_started = false;
    bool m_framePresented = false;
    bool m_transferVerified = false;
};
