// notifserver -- implements org.freedesktop.Notifications D-Bus service.
//
// For each Notify call, emits a JSON line to stdout:
//   {"type":"notify","id":1,"app":"...","summary":"...","body":"...","actions":[...],"timeout":5000}
// For CloseNotification:
//   {"type":"close","id":1}
//
// QML NotificationService.qml reads this via Process + SplitParser.

#include "notifserver.h"
#include <QCoreApplication>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusError>
#include <QThread>
#include <csignal>
#include <sys/types.h>
#include <iostream>
#include <string>

// ── JSON helper ───────────────────────────────────────────────────────────────

static std::string esc(const QString &s) {
    std::string r;
    for (QChar c : s) {
        if (c == '"')       r += "\\\"";
        else if (c == '\\') r += "\\\\";
        else if (c == '\n') r += "\\n";
        else if (c == '\r') r += "";
        else                r += c.toLatin1();
    }
    return r;
}

// ── NotifServer ───────────────────────────────────────────────────────────────

NotifServer::NotifServer(QObject *parent) : QObject(parent) {
    new NotifAdaptor(this);
}

bool NotifServer::registerOnBus() {
    QDBusConnection bus = QDBusConnection::sessionBus();
    if (!bus.isConnected()) {
        std::cerr << "[notifserver] Cannot connect to session D-Bus\n";
        return false;
    }

    // Kill any existing notification daemon that holds the name.
    // ReplaceExistingService only works if the owner set AllowReplacement -- most don't.
    QDBusConnectionInterface *iface = bus.interface();
    auto ownerReply = iface->serviceOwner("org.freedesktop.Notifications");
    if (ownerReply.isValid() && !ownerReply.value().isEmpty()) {
        auto pidReply = iface->servicePid(ownerReply.value());
        if (pidReply.isValid() && pidReply.value() > 0) {
            uint pid = pidReply.value();
            std::cerr << "[notifserver] Displacing existing notification daemon (pid " << pid << ")\n";
            ::kill(static_cast<pid_t>(pid), SIGTERM);
            QThread::msleep(400);
        }
    }

    if (!bus.registerObject("/org/freedesktop/Notifications", this)) {
        std::cerr << "[notifserver] registerObject failed: "
                  << bus.lastError().message().toStdString() << "\n";
        return false;
    }

    auto reply = iface->registerService(
        "org.freedesktop.Notifications",
        QDBusConnectionInterface::DontQueueService,
        QDBusConnectionInterface::DontAllowReplacement);
    if (!reply.isValid() || reply.value() == QDBusConnectionInterface::ServiceNotRegistered) {
        std::cerr << "[notifserver] registerService failed: "
                  << reply.error().message().toStdString() << "\n";
        return false;
    }

    return true;
}

// ── NotifAdaptor ──────────────────────────────────────────────────────────────

NotifAdaptor::NotifAdaptor(NotifServer *parent)
    : QDBusAbstractAdaptor(parent)
{
    setAutoRelaySignals(true);
}

uint NotifAdaptor::Notify(const QString &app_name, uint replaces_id,
                           const QString &/*app_icon*/, const QString &summary,
                           const QString &body, const QStringList &actions,
                           const QVariantMap &/*hints*/, int expire_timeout) {
    NotifServer *srv = static_cast<NotifServer *>(parent());
    uint id = (replaces_id > 0) ? replaces_id : srv->nextId();

    std::string actJson = "[";
    for (int i = 0; i + 1 < actions.size(); i += 2) {
        if (i > 0) actJson += ",";
        actJson += "{\"key\":\"" + esc(actions[i]) + "\","
                    "\"label\":\"" + esc(actions[i+1]) + "\"}";
    }
    actJson += "]";

    std::cout << "{\"type\":\"notify\","
              << "\"id\":"        << id << ","
              << "\"app\":\""     << esc(app_name) << "\","
              << "\"summary\":\"" << esc(summary) << "\","
              << "\"body\":\""    << esc(body) << "\","
              << "\"actions\":"   << actJson << ","
              << "\"timeout\":"   << expire_timeout << "}\n";
    std::cout.flush();
    return id;
}

void NotifAdaptor::CloseNotification(uint id) {
    std::cout << "{\"type\":\"close\",\"id\":" << id << "}\n";
    std::cout.flush();
    Q_EMIT NotificationClosed(id, 3);
}

QStringList NotifAdaptor::GetCapabilities() {
    return {"body", "actions", "persistence"};
}

void NotifAdaptor::GetServerInformation(QString &name, QString &vendor,
                                         QString &version, QString &spec_version) {
    name         = "Aethera Shell Notifications";
    vendor       = "aethera";
    version      = "1.0";
    spec_version = "1.2";
}

// ── main ──────────────────────────────────────────────────────────────────────

int main(int argc, char *argv[]) {
    QCoreApplication app(argc, argv);

    NotifServer server;
    if (!server.registerOnBus())
        return 1;

    return app.exec();
}
