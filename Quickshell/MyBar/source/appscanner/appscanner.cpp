// Scans XDG application directories for .desktop files and prints
// tab-separated "Name\tExec" lines, sorted, skipping NoDisplay entries.
// Much faster than the equivalent shell pipeline over 100+ files.

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

static std::string homeDir() {
    const char *h = std::getenv("HOME");
    return h ? h : "";
}

struct App {
    std::string name;
    std::string exec;
};

static void scanDir(const std::string &dir, std::vector<App> &out) {
    DIR *d = opendir(dir.c_str());
    if (!d) return;

    dirent *ent;
    while ((ent = readdir(d)) != nullptr) {
        const char *n = ent->d_name;
        size_t len = strlen(n);
        if (len < 9 || strcmp(n + len - 8, ".desktop") != 0) continue;

        std::ifstream f(dir + "/" + n);
        if (!f) continue;

        std::string line, name, exec;
        bool noDisplay = false;
        bool inDesktopEntry = false;

        while (std::getline(f, line)) {
            if (line == "[Desktop Entry]") { inDesktopEntry = true; continue; }
            if (!line.empty() && line[0] == '[') { inDesktopEntry = false; continue; }
            if (!inDesktopEntry) continue;

            if (name.empty() && line.rfind("Name=", 0) == 0)
                name = line.substr(5);
            else if (exec.empty() && line.rfind("Exec=", 0) == 0)
                exec = line.substr(5);
            else if (line.rfind("NoDisplay=", 0) == 0 && line.substr(10) == "true")
                noDisplay = true;
        }

        if (!name.empty() && !exec.empty() && !noDisplay)
            out.push_back({name, exec});
    }
    closedir(d);
}

// XDG Base Directory spec: search $XDG_DATA_HOME/applications (falling back
// to ~/.local/share/applications) plus every dir in $XDG_DATA_DIRS (falling
// back to /usr/local/share/:/usr/share/). NixOS doesn't populate
// /usr/share/applications at all -- system packages land in
// /run/current-system/sw/share/applications, which is only reachable via
// XDG_DATA_DIRS, so hardcoding /usr/share/applications finds nothing there.
static std::vector<std::string> xdgApplicationDirs() {
    std::vector<std::string> dirs;

    const char *dataHome = std::getenv("XDG_DATA_HOME");
    if (dataHome && *dataHome)
        dirs.push_back(std::string(dataHome) + "/applications");
    else
        dirs.push_back(homeDir() + "/.local/share/applications");

    const char *dataDirs = std::getenv("XDG_DATA_DIRS");
    std::string dd = (dataDirs && *dataDirs) ? dataDirs : "/usr/local/share/:/usr/share/";

    size_t pos = 0;
    while (pos <= dd.size()) {
        size_t next = dd.find(':', pos);
        if (next == std::string::npos) next = dd.size();
        std::string part = dd.substr(pos, next - pos);
        if (!part.empty()) {
            if (part.back() == '/') part.pop_back();
            dirs.push_back(part + "/applications");
        }
        pos = next + 1;
    }
    return dirs;
}

int main() {
    std::vector<App> apps;

    for (const auto &dir : xdgApplicationDirs())
        scanDir(dir, apps);

    std::sort(apps.begin(), apps.end(), [](const App &a, const App &b) {
        return a.name < b.name;
    });

    for (const auto &app : apps)
        std::cout << app.name << '\t' << app.exec << '\n';

    return 0;
}
