#pragma once

#include <QObject>
#include <QTcpServer>
#include <QString>

class Engine;

class EngineSmoke final : public QObject
{
    Q_OBJECT

public:
    explicit EngineSmoke(Engine &engine);

private:
    void startDownload();
    void inspectTransfers();
    void verifyShutdown(bool clean);
    void serve();

    Engine &m_engine;
    QTcpServer m_server;
    QString m_name;
    bool m_started = false;
    bool m_transferVerified = false;
};
