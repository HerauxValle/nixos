#pragma once
#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantMap>
#include <QDBusAbstractAdaptor>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QThread>
#include <csignal>
#include <sys/types.h>
#include <iostream>

// Core server object -- holds state and emits JSON to stdout.
class NotifServer : public QObject {
    Q_OBJECT
public:
    explicit NotifServer(QObject *parent = nullptr);
    bool registerOnBus();

    uint nextId() { return _nextId++; }

Q_SIGNALS:
    void NotificationClosed(uint id, uint reason);
    void ActionInvoked(uint id, const QString &action_key);

private:
    uint _nextId = 1;
};

// D-Bus adaptor -- properly exports all methods including out-param ones.
class NotifAdaptor : public QDBusAbstractAdaptor {
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.freedesktop.Notifications")
    Q_CLASSINFO("D-Bus Introspection",
        "<interface name=\"org.freedesktop.Notifications\">"
        "  <method name=\"Notify\">"
        "    <arg direction=\"in\"  type=\"s\" name=\"app_name\"/>"
        "    <arg direction=\"in\"  type=\"u\" name=\"replaces_id\"/>"
        "    <arg direction=\"in\"  type=\"s\" name=\"app_icon\"/>"
        "    <arg direction=\"in\"  type=\"s\" name=\"summary\"/>"
        "    <arg direction=\"in\"  type=\"s\" name=\"body\"/>"
        "    <arg direction=\"in\"  type=\"as\" name=\"actions\"/>"
        "    <arg direction=\"in\"  type=\"a{sv}\" name=\"hints\"/>"
        "    <arg direction=\"in\"  type=\"i\" name=\"expire_timeout\"/>"
        "    <arg direction=\"out\" type=\"u\" name=\"id\"/>"
        "  </method>"
        "  <method name=\"CloseNotification\">"
        "    <arg direction=\"in\"  type=\"u\" name=\"id\"/>"
        "  </method>"
        "  <method name=\"GetCapabilities\">"
        "    <arg direction=\"out\" type=\"as\" name=\"capabilities\"/>"
        "  </method>"
        "  <method name=\"GetServerInformation\">"
        "    <arg direction=\"out\" type=\"s\" name=\"name\"/>"
        "    <arg direction=\"out\" type=\"s\" name=\"vendor\"/>"
        "    <arg direction=\"out\" type=\"s\" name=\"version\"/>"
        "    <arg direction=\"out\" type=\"s\" name=\"spec_version\"/>"
        "  </method>"
        "  <signal name=\"NotificationClosed\">"
        "    <arg type=\"u\" name=\"id\"/>"
        "    <arg type=\"u\" name=\"reason\"/>"
        "  </signal>"
        "  <signal name=\"ActionInvoked\">"
        "    <arg type=\"u\" name=\"id\"/>"
        "    <arg type=\"s\" name=\"action_key\"/>"
        "  </signal>"
        "</interface>")

public:
    explicit NotifAdaptor(NotifServer *parent);

public Q_SLOTS:
    uint Notify(const QString &app_name, uint replaces_id, const QString &app_icon,
                const QString &summary, const QString &body,
                const QStringList &actions, const QVariantMap &hints, int expire_timeout);

    void CloseNotification(uint id);
    QStringList GetCapabilities();
    void GetServerInformation(QString &name, QString &vendor,
                              QString &version, QString &spec_version);

Q_SIGNALS:
    void NotificationClosed(uint id, uint reason);
    void ActionInvoked(uint id, const QString &action_key);
};
