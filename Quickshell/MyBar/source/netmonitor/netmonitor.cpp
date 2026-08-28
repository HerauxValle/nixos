// netmonitor -- reactive WiFi + Bluetooth + LAN state monitor.
//
// Uses libnm (GLib/GObject) for WiFi/ethernet, and a system-bus
// PropertiesChanged subscription for BlueZ -- both fully event-driven,
// no polling loop for either.
//
// Emits JSON lines to stdout on state changes:
//   {"type":"wifi","on":bool,"radio":bool,"ssid":"...","signal":0-100,"ip":"..."}
//   {"type":"bt","on":bool,"device":"..."}
//   {"type":"lan","connected":bool,"iface":"...","ip":"...","mac":"...","speed":"..."}
//
// QML reads this via Process + SplitParser on newline.

#include <NetworkManager.h>
#include <gio/gio.h>
#include <glib.h>
#include <glib-unix.h>

#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/socket.h>

#include <atomic>
#include <cstring>
#include <fstream>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <chrono>
#include <sstream>
#include <iomanip>

// ── JSON helpers ──────────────────────────────────────────────────────────────

static std::string escJson(const std::string &s) {
    std::string r;
    for (char c : s) {
        if (c == '"')       r += "\\\"";
        else if (c == '\\') r += "\\\\";
        else if (c == '\n') r += "\\n";
        else                r += c;
    }
    return r;
}

static std::mutex g_mu;

static void emitWifi(bool on, bool radio, const std::string &ssid, int signal, const std::string &ip) {
    std::lock_guard<std::mutex> lk(g_mu);
    std::cout << "{\"type\":\"wifi\","
              << "\"on\":"      << (on    ? "true" : "false") << ","
              << "\"radio\":"   << (radio ? "true" : "false") << ","
              << "\"ssid\":\""  << escJson(ssid) << "\","
              << "\"signal\":"  << signal << ","
              << "\"ip\":\""    << escJson(ip) << "\"}\n";
    std::cout.flush();
}

static void emitBt(bool on, const std::string &device) {
    std::lock_guard<std::mutex> lk(g_mu);
    std::cout << "{\"type\":\"bt\","
              << "\"on\":"       << (on ? "true" : "false") << ","
              << "\"device\":\"" << escJson(device) << "\"}\n";
    std::cout.flush();
}

static void emitLan(bool connected, const std::string &iface,
                    const std::string &ip, const std::string &mac,
                    const std::string &speed) {
    std::lock_guard<std::mutex> lk(g_mu);
    std::cout << "{\"type\":\"lan\","
              << "\"connected\":" << (connected ? "true" : "false") << ","
              << "\"iface\":\""   << escJson(iface) << "\","
              << "\"ip\":\""      << escJson(ip)    << "\","
              << "\"mac\":\""     << escJson(mac)   << "\","
              << "\"speed\":\""   << escJson(speed) << "\"}\n";
    std::cout.flush();
}

// ── IP address lookup via getifaddrs ─────────────────────────────────────────

static std::string getIfaceIp(const std::string &iface) {
    struct ifaddrs *ifa_list;
    if (getifaddrs(&ifa_list) != 0) return "";
    std::string result;
    for (struct ifaddrs *ifa = ifa_list; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) continue;
        if (iface != ifa->ifa_name) continue;
        char buf[INET_ADDRSTRLEN] = {};
        inet_ntop(AF_INET, &((struct sockaddr_in *)ifa->ifa_addr)->sin_addr, buf, sizeof(buf));
        result = buf;
        break;
    }
    freeifaddrs(ifa_list);
    return result;
}

// ── NMClient state ────────────────────────────────────────────────────────────

struct WifiState {
    bool on     = false;
    bool radio  = true;
    std::string ssid;
    int  signal = 0;
    std::string ip;
};

struct LanState {
    bool connected = false;
    std::string iface;
    std::string ip;
    std::string mac;
    std::string speed;
};

static WifiState g_wifi;
static LanState  g_lan;

static std::string readSysFile(const std::string &path) {
    std::ifstream f(path);
    std::string v; f >> v;
    return v;
}

static void refreshLan(NMClient *client) {
    LanState s;
    const GPtrArray *devs = nm_client_get_devices(client);
    for (guint i = 0; i < devs->len; i++) {
        NMDevice *dev = NM_DEVICE(devs->pdata[i]);
        if (nm_device_get_device_type(dev) != NM_DEVICE_TYPE_ETHERNET) continue;
        if (nm_device_get_state(dev) != NM_DEVICE_STATE_ACTIVATED) continue;

        const char *iface = nm_device_get_iface(dev);
        if (!iface) continue;
        s.iface    = iface;
        s.ip       = getIfaceIp(iface);
        s.mac      = readSysFile(std::string("/sys/class/net/") + iface + "/address");
        std::string spd = readSysFile(std::string("/sys/class/net/") + iface + "/speed");
        s.speed    = spd.empty() ? "" : spd + "Mbps";
        s.connected = true;
        break;
    }
    g_lan = s;
    emitLan(s.connected, s.iface, s.ip, s.mac, s.speed);
}

static void refreshWifi(NMClient *client) {
    WifiState s;

    NMDevice *wdev = nullptr;
    const GPtrArray *devs = nm_client_get_devices(client);
    for (guint i = 0; i < devs->len; i++) {
        NMDevice *dev = NM_DEVICE(devs->pdata[i]);
        if (nm_device_get_device_type(dev) == NM_DEVICE_TYPE_WIFI) {
            wdev = dev;
            break;
        }
    }

    s.radio = nm_client_wireless_get_enabled(client);

    // When the radio's software toggle flips off, NM's wireless-enabled
    // property updates before the device itself has fully deactivated (that
    // transition is async and can lag a beat behind, the same gap "ip link"
    // would show at the kernel level). Don't report a stale active AP/SSID
    // during that window -- a disabled radio can't have a real connection.
    if (wdev && NM_IS_DEVICE_WIFI(wdev) && s.radio) {
        NMDeviceWifi *wifiDev = NM_DEVICE_WIFI(wdev);
        NMAccessPoint *ap = nm_device_wifi_get_active_access_point(wifiDev);
        if (ap) {
            GBytes *ssidBytes = nm_access_point_get_ssid(ap);
            if (ssidBytes) {
                gsize len;
                const guint8 *data = (const guint8 *)g_bytes_get_data(ssidBytes, &len);
                s.ssid = std::string(reinterpret_cast<const char *>(data), len);
            }
            s.signal = nm_access_point_get_strength(ap);
            s.on     = true;
        }
        // get IP
        const char *iface = nm_device_get_iface(wdev);
        if (iface) s.ip = getIfaceIp(iface);
    }

    g_wifi = s;
    emitWifi(s.on, s.radio, s.ssid, s.signal, s.ip);
}

// ── NM signal callbacks ───────────────────────────────────────────────────────

static void onDeviceStateChanged(NMDevice *, NMDeviceState, NMDeviceState,
                                  NMDeviceStateReason, gpointer client) {
    refreshWifi(NM_CLIENT(client));
    refreshLan(NM_CLIENT(client));
}

static void onWirelessEnabledChanged(NMClient *client, GParamSpec *, gpointer) {
    refreshWifi(client);
}

static void onActiveApChanged(NMDeviceWifi *wdev, GParamSpec *, gpointer client) {
    (void)wdev;
    refreshWifi(NM_CLIENT(client));
}

static void onDeviceAdded(NMClient *client, NMDevice *dev, gpointer) {
    g_signal_connect(dev, "state-changed", G_CALLBACK(onDeviceStateChanged), client);
    if (NM_IS_DEVICE_WIFI(dev))
        g_signal_connect(dev, "notify::active-access-point",
                         G_CALLBACK(onActiveApChanged), client);
    refreshWifi(client);
    refreshLan(client);
}

// ── BlueZ D-Bus state (reactive: driven off PropertiesChanged signals, ─────
// no polling loop). BlueZ lives on the system bus; we subscribe once and
// recompute state only when BlueZ itself tells us something changed, so
// updates land within milliseconds instead of waiting out a poll interval.

static std::string g_btAdapterPath = "/org/bluez/hci0";

static std::string discoverBtAdapterPath() {
    FILE *afp = popen(
        "dbus-send --system --dest=org.bluez --print-reply "
        "/org/bluez org.freedesktop.DBus.Introspectable.Introspect 2>/dev/null "
        "| grep -o 'hci[0-9]*' | head -1", "r");
    std::string adapter = "hci0";
    if (afp) {
        char abuf[32] = {};
        if (fgets(abuf, sizeof(abuf), afp)) {
            std::string a(abuf);
            while (!a.empty() && (a.back() == '\n' || a.back() == ' ')) a.pop_back();
            if (!a.empty()) adapter = a;
        }
        pclose(afp);
    }
    return "/org/bluez/" + adapter;
}

static std::string btPollPowered() {
    std::string cmd =
        "dbus-send --system --dest=org.bluez --print-reply "
        + g_btAdapterPath + " org.freedesktop.DBus.Properties.Get "
        "string:org.bluez.Adapter1 string:Powered 2>/dev/null "
        "| awk '/variant/{print $3}'";
    FILE *fp = popen(cmd.c_str(), "r");
    if (!fp) return "";
    char buf[64] = {};
    if (fgets(buf, sizeof(buf), fp)) { /* read result */ }
    pclose(fp);
    std::string r(buf);
    while (!r.empty() && (r.back() == '\n' || r.back() == ' ')) r.pop_back();
    return r;
}

static std::string btPollConnectedDevice() {
    FILE *fp = popen(
        "bluetoothctl devices Connected 2>/dev/null | head -1 | cut -d' ' -f3-", "r");
    if (!fp) return "";
    char buf[256] = {};
    if (fgets(buf, sizeof(buf), fp)) { /* read */ }
    pclose(fp);
    std::string r(buf);
    while (!r.empty() && (r.back() == '\n' || r.back() == '\r' || r.back() == ' ')) r.pop_back();
    return r;
}

static bool        g_btLastOn = false;
static std::string g_btLastDev;
static bool         g_btFirst = true;

static void refreshBt() {
    std::string powered = btPollPowered();
    bool on = (powered == "true");
    std::string dev = on ? btPollConnectedDevice() : "";

    // Always emit the first time: the QML side's cached state may already
    // say "on" from before this process last (re)started, and skipping an
    // unchanged-looking "off" would leave the UI stuck on stale data.
    if (g_btFirst || on != g_btLastOn || dev != g_btLastDev) {
        g_btLastOn  = on;
        g_btLastDev = dev;
        g_btFirst   = false;
        emitBt(on, dev);
    }
}

static void onBtPropertiesChanged(GDBusConnection *, const gchar *, const gchar *,
                                   const gchar *, const gchar *, GVariant *, gpointer) {
    refreshBt();
}

// ── Main ──────────────────────────────────────────────────────────────────────

static GMainLoop *g_loop = nullptr;

static gboolean onSigterm(gpointer) {
    if (g_loop) g_main_loop_quit(g_loop);
    return G_SOURCE_REMOVE;
}

int main() {
    // Disable stdout buffering so QML SplitParser gets lines immediately
    std::ios::sync_with_stdio(false);

    g_loop = g_main_loop_new(nullptr, FALSE);

    g_unix_signal_add(SIGTERM, onSigterm, nullptr);
    g_unix_signal_add(SIGINT,  onSigterm, nullptr);

    // Connect to NetworkManager
    GError *err = nullptr;
    NMClient *client = nm_client_new(nullptr, &err);
    if (!client) {
        std::cerr << "[netmonitor] nm_client_new failed: "
                  << (err ? err->message : "unknown") << "\n";
        if (err) g_error_free(err);
        return 1;
    }

    // Connect to signals on existing devices
    const GPtrArray *devs = nm_client_get_devices(client);
    for (guint i = 0; i < devs->len; i++) {
        NMDevice *dev = NM_DEVICE(devs->pdata[i]);
        g_signal_connect(dev, "state-changed", G_CALLBACK(onDeviceStateChanged), client);
        if (NM_IS_DEVICE_WIFI(dev))
            g_signal_connect(dev, "notify::active-access-point",
                             G_CALLBACK(onActiveApChanged), client);
    }

    g_signal_connect(client, "device-added",
                     G_CALLBACK(onDeviceAdded), nullptr);
    g_signal_connect(client, "notify::wireless-enabled",
                     G_CALLBACK(onWirelessEnabledChanged), nullptr);

    // Emit initial state
    refreshWifi(client);
    refreshLan(client);

    // Bluetooth: reactive via system-bus PropertiesChanged, no polling loop.
    g_btAdapterPath = discoverBtAdapterPath();
    GError *btErr = nullptr;
    GDBusConnection *sysBus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, &btErr);
    if (sysBus) {
        g_dbus_connection_signal_subscribe(
            sysBus,
            "org.bluez",                          // sender
            "org.freedesktop.DBus.Properties",     // interface
            "PropertiesChanged",                   // member
            nullptr,                                // any object path under org.bluez
            nullptr,                                // any arg0
            G_DBUS_SIGNAL_FLAGS_NONE,
            onBtPropertiesChanged, nullptr, nullptr);
    } else {
        std::cerr << "[netmonitor] system bus connect failed: "
                  << (btErr ? btErr->message : "unknown") << "\n";
        if (btErr) g_error_free(btErr);
    }
    refreshBt();

    g_main_loop_run(g_loop);

    g_object_unref(client);
    g_main_loop_unref(g_loop);
    return 0;
}
