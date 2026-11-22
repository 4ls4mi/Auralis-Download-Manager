#include "Smoke.h"
#include "Engine.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QSaveFile>
#include <QTcpSocket>
#include <QTimer>
#include <QUuid>

namespace {
const QByteArray Payload = QByteArray("Auralis Qt downloader integrity test\n").repeated(2048);
}

EngineSmoke::EngineSmoke(Engine &engine) : m_engine(engine)
{
    const auto root = QDir(m_engine.dataDirectory());
    m_name = QStringLiteral("auralis-qt-smoke-%1.bin").arg(QUuid::createUuid().toString(QUuid::Id128));
    QFile::remove(root.filePath(QStringLiteral("qt-engine-smoke.ok")));
    connect(&m_server, &QTcpServer::newConnection, this, &EngineSmoke::serve);
    connect(&m_engine, &Engine::readyChanged, this, &EngineSmoke::startDownload);
    connect(&m_engine, &Engine::dashboardChanged, this, &EngineSmoke::inspectTransfers);
    connect(&m_engine, &Engine::serviceStopped, this, &EngineSmoke::verifyShutdown);
    connect(&m_engine, &Engine::operationFailed, this, [this](const QString &message) {
        qCritical().noquote() << message;
        m_engine.requestQuit(1);
    });
    QTimer::singleShot(45000, this, [this] {
        qCritical("The Qt engine integration test timed out.");
        m_engine.requestQuit(1);
    });
}

void EngineSmoke::startDownload()
{
    if (m_started || !m_engine.ready())
        return;
    m_started = true;
    qInfo("Smoke: Rust service connected. Starting the local download.");
    if (!m_server.listen(QHostAddress::LocalHost, 0)) {
        qCritical().noquote() << m_server.errorString();
        m_engine.requestQuit(1);
        return;
    }
    const QString url = QStringLiteral("http://127.0.0.1:%1/%2").arg(m_server.serverPort()).arg(m_name);
    m_engine.request({{QStringLiteral("url"), url},
                      {QStringLiteral("dir"), m_engine.dataDirectory()},
                      {QStringLiteral("name"), m_name},
                      {QStringLiteral("silent"), true},
                      {QStringLiteral("connections"), 1}});
}

void EngineSmoke::inspectTransfers()
{
    if (!m_started || m_transferVerified)
        return;
    const auto downloads = m_engine.dashboard().value(QStringLiteral("downloads")).toList();
    for (const auto &entry : downloads) {
        const auto download = entry.toMap();
        if (download.value(QStringLiteral("file")).toString() != m_name ||
            download.value(QStringLiteral("status")).toString().compare(QStringLiteral("Complete"), Qt::CaseInsensitive))
            continue;
        QFile file(download.value(QStringLiteral("path")).toString());
        m_transferVerified = file.open(QIODevice::ReadOnly) && file.readAll() == Payload;
        if (!m_transferVerified)
            qCritical("The downloaded smoke-test file differs from the local server payload.");
        if (m_transferVerified) qInfo("Smoke: downloaded bytes verified. Stopping the service.");
        m_engine.requestQuit(m_transferVerified ? 0 : 1);
        break;
    }
}

void EngineSmoke::verifyShutdown(bool clean)
{
    if (!clean || !m_transferVerified) {
        QCoreApplication::exit(1);
        return;
    }
    qInfo("Smoke: Rust service stopped cleanly.");
    QSaveFile marker(QDir(m_engine.dataDirectory()).filePath(QStringLiteral("qt-engine-smoke.ok")));
    const QByteArray confirmation("Qt application, Rust downloader, and file integrity verified.\n");
    if (!marker.open(QIODevice::WriteOnly) || marker.write(confirmation) != confirmation.size() || !marker.commit())
        qFatal("Could not persist the Qt engine integration result.");
}

void EngineSmoke::serve()
{
    while (auto *socket = m_server.nextPendingConnection()) {
        connect(socket, &QTcpSocket::disconnected, socket, &QTcpSocket::deleteLater);
        connect(socket, &QTcpSocket::readyRead, socket, [socket, header = QByteArray()]() mutable {
            header += socket->readAll();
            if (header.size() > 16384) {
                socket->disconnectFromHost();
                return;
            }
            if (!header.contains("\r\n\r\n"))
                return;
            QByteArray reply("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nConnection: close\r\nContent-Length: ");
            reply += QByteArray::number(Payload.size()) + "\r\n\r\n";
            socket->write(reply);
            if (!header.startsWith("HEAD "))
                socket->write(Payload);
            socket->disconnectFromHost();
        });
    }
}
