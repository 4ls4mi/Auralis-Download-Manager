#include "StoreStartup.h"
#include <QSettings>
#include <QObject>
#include <QCoreApplication>
#include <QMetaObject>
#include <future>
#include <memory>
#include <winrt/Windows.ApplicationModel.h>
#include <winrt/Windows.Foundation.h>

namespace {
// Engine local requests run on worker threads. Balance COM initialization there.
struct Apartment {
    Apartment() { winrt::init_apartment(winrt::apartment_type::multi_threaded); }
    ~Apartment() { winrt::uninit_apartment(); }
};
QString mode() {
    return QSettings().value(QStringLiteral("StoreStartup/mode"), QStringLiteral("minimized")).toString();
}
QVariantMap error(const QString &message) { return {{QStringLiteral("error"), message}}; }
winrt::Windows::ApplicationModel::StartupTaskState enableOnUiThread(
    const winrt::Windows::ApplicationModel::StartupTask &task)
{
    using State = winrt::Windows::ApplicationModel::StartupTaskState;
    auto promise = std::make_shared<std::promise<State>>();
    auto future = promise->get_future();
    // RequestEnableAsync must be initiated on the UI thread. The bridge worker
    // waits for completion without blocking Qt's event loop.
    QMetaObject::invokeMethod(QCoreApplication::instance(), [task, promise] {
        try {
            auto operation = task.RequestEnableAsync();
            operation.Completed([promise](auto completed, auto) {
                try { promise->set_value(completed.GetResults()); }
                catch (...) { promise->set_exception(std::current_exception()); }
            });
        } catch (...) { promise->set_exception(std::current_exception()); }
    }, Qt::QueuedConnection);
    return future.get();
}
}

QVariantMap StoreStartup::settings()
{
    try {
        Apartment apartment;
        const auto task = winrt::Windows::ApplicationModel::StartupTask::GetAsync(L"AuralisStartup").get();
        const auto state = task.State();
        using State = winrt::Windows::ApplicationModel::StartupTaskState;
        return {{QStringLiteral("enabled"), state == State::Enabled || state == State::EnabledByPolicy},
                {QStringLiteral("mode"), mode()}};
    } catch (const winrt::hresult_error &failure) {
        return error(QObject::tr("Could not read the Windows startup task. %1")
                     .arg(QString::fromWCharArray(failure.message().c_str())));
    }
}

QVariantMap StoreStartup::save(const QVariantMap &command)
{
    const auto requestedMode = command.value(QStringLiteral("mode")).toString();
    if (requestedMode != QStringLiteral("window") && requestedMode != QStringLiteral("minimized"))
        return error(QObject::tr("Choose a valid startup window mode."));
    try {
        Apartment apartment;
        using namespace winrt::Windows::ApplicationModel;
        const auto task = StartupTask::GetAsync(L"AuralisStartup").get();
        const bool enabled = command.value(QStringLiteral("enabled")).toBool();
        if (enabled) {
            const auto state = enableOnUiThread(task);
            if (state != StartupTaskState::Enabled && state != StartupTaskState::EnabledByPolicy)
                return error(QObject::tr("Windows has disabled this startup task. Enable Auralis in Windows Settings > Apps > Startup."));
        } else {
            if (task.State() == StartupTaskState::EnabledByPolicy)
                return error(QObject::tr("Your administrator controls this startup task."));
            task.Disable();
        }
        QSettings preferences;
        preferences.setValue(QStringLiteral("StoreStartup/mode"), requestedMode);
        preferences.sync();
        if (preferences.status() != QSettings::NoError)
            return error(QObject::tr("Could not save the startup window mode."));
        auto response = settings();
        if (response.contains(QStringLiteral("error"))) return response;
        return {{QStringLiteral("result"), response}};
    } catch (const winrt::hresult_error &failure) {
        return error(QObject::tr("Could not change the Windows startup task. %1")
                     .arg(QString::fromWCharArray(failure.message().c_str())));
    }
}
