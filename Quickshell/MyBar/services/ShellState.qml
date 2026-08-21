pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property bool dashboardOpen: false
    property bool drawerOpen:    false
    property bool launcherOpen:  false
    property int  drawerTab:     0   // 0=Essentials, 1=Dashboard

    function toggleDashboard() { dashboardOpen = !dashboardOpen }
    function toggleDrawer()    { drawerOpen = !drawerOpen }
    function openDrawerTab(tab) { drawerTab = tab; drawerOpen = true }
    function closeDashboard()  { dashboardOpen = false }
    function closeDrawer()     { drawerOpen    = false }
    function toggleLauncher()  { launcherOpen  = !launcherOpen }
    function closeLauncher()   { launcherOpen  = false }

    property bool notificationsOpen: false
    function toggleNotifications() { notificationsOpen = !notificationsOpen }
    function closeNotifications()  { notificationsOpen = false }

    property bool settingsOpen: false
    function toggleSettings() { settingsOpen = !settingsOpen }
    function closeSettings()  { settingsOpen = false }
}
