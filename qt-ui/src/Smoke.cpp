#include "Smoke.h"
#include "Engine.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QQuickWindow>
#include <QRegularExpression>
#include <QSaveFile>
#include <QTcpSocket>
#include <QTimer>
#include <QUuid>

namespace {
const QByteArray Payload = QByteArray("Auralis Qt downloader integrity test\n").repeated(56 * 1024);
constexpr qsizetype InitialBytes = 320 * 1024;
constexpr qsizetype ChunkBytes = 32 * 1024;
}

EngineSmoke::EngineSmoke(Engine &engine) : m_engine(engine)
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
        fail(QStringLiteral("The Qt transfer test timed out at step %1.").arg(static_cast<int>(m_step)));
    });
}

void EngineSmoke::startDownload()
{
    if (m_started || !m_engine.ready())
        return;
    m_started = true;
    qInfo("Smoke: Rust service connected. Starting the local download.");
    if (!m_server.listen(QHostAddress::LocalHost, 0)) {
        fail(m_server.errorString());
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
    if (!m_started || m_step == Step::Stopped)
        return;
    const auto downloads = m_engine.dashboard().value(QStringLiteral("downloads")).toList();
    for (const auto &entry : downloads) {
        const auto download = entry.toMap();
        if (download.value(QStringLiteral("file")).toString() != m_name)
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
            QFile file(download.value(QStringLiteral("path")).toString());
            m_transferVerified = file.open(QIODevice::ReadOnly) && file.readAll() == Payload;
            if (!m_transferVerified) {
                fail(QStringLiteral("The downloaded smoke-test file differs from the local payload."));
                return;
            }
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
            m_step = Step::WaitingForResume;
            qInfo("Smoke: transfer paused. Resuming with the progress window closed.");
            m_engine.request({{QStringLiteral("action"), QStringLiteral("start")},
                              {QStringLiteral("ids"), QVariantList{QVariant::fromValue(id)}}});
            return;
        }
        if ((m_step == Step::Starting || m_step == Step::WaitingForResume) &&
            status == QStringLiteral("Downloading") && download.value(QStringLiteral("downloaded")).toLongLong() > 0) {
            observeTransferWindow(id);
            if (!m_framePresented)
                return;
            if (m_step == Step::Starting) {
                m_step = Step::WaitingForPause;
                qInfo("Smoke: the initial active progress window rendered. Pausing from its toolbar.");
                if (!pauseTransfer())
                    fail(QStringLiteral("The progress window's Pause action could not be invoked."));
            } else {
                m_step = Step::Finishing;
                qInfo("Smoke: the resumed active progress window reopened and rendered.");
            }
        }
        return;
    }
}

void EngineSmoke::observeTransferWindow(qulonglong id)
{
    if (!id)
        return;
    for (auto *window : QGuiApplication::allWindows()) {
        auto *progress = qobject_cast<QQuickWindow *>(window);
        if (!progress || !progress->isVisible() || progress->property("downloadId").toULongLong() != id)
            continue;
        if (m_window != progress) {
            disconnect(m_frameConnection);
            m_window = progress;
            m_framePresented = false;
            m_frameConnection = connect(progress, &QQuickWindow::frameSwapped, this, [this] {
                if (m_window && m_window->isVisible() && m_window->property("runningTransfer").toBool())
                    m_framePresented = true;
            }, Qt::QueuedConnection);
        }
        progress->update();
        break;
    }
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
    const QByteArray confirmation("Qt progress windows rendered on start and resume. Rust transfer and file integrity verified.\n");
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
                const auto available = m_step == Step::Finishing ? end : qMin(end, first + InitialBytes);
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
