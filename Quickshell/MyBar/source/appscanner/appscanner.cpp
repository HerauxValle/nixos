// Scans XDG application directories for .desktop files, plus every
// PATH dir for .AppImage/.desktop/.executable files, and prints
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

// Parses a single .desktop file. Returns false (app left untouched) on
// missing Name/Exec or NoDisplay=true.
static bool parseDesktopFile(const std::string &path, App &app) {
    std::ifstream f(path);
    if (!f) return false;

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

    if (name.empty() || exec.empty() || noDisplay) return false;
    app = {name, exec};
    return true;
}

static bool hasSuffix(const std::string &s, const std::string &suffix) {
    return s.size() >= suffix.size() &&
           s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

static void scanDir(const std::string &dir, std::vector<App> &out) {
    DIR *d = opendir(dir.c_str());
    if (!d) return;

    dirent *ent;
    while ((ent = readdir(d)) != nullptr) {
        const char *n = ent->d_name;
        size_t len = strlen(n);
        if (len < 9 || strcmp(n + len - 8, ".desktop") != 0) continue;

        App app;
        if (parseDesktopFile(dir + "/" + n, app))
            out.push_back(app);
    }
    closedir(d);
}

// Scans one PATH dir for launchable files by extension. .AppImage is
// self-explanatory; .desktop lets an AppImage that ships its own
// desktop file (dropped straight in a PATH dir, not
// ~/.local/share/applications) still show up; .executable is a
// made-up marker extension so ordinary .sh scripts on PATH don't all
// flood the launcher -- only ones deliberately renamed to end in
// .executable get exposed. Name is the filename with that extension
// stripped; Exec is the full path.
static void scanPathDir(const std::string &dir, std::vector<App> &out) {
    DIR *d = opendir(dir.c_str());
    if (!d) return;

    static const std::string kAppImage = ".AppImage";
    static const std::string kDesktop = ".desktop";
    static const std::string kExecutable = ".executable";

    dirent *ent;
    while ((ent = readdir(d)) != nullptr) {
        std::string name = ent->d_name;
        if (name == "." || name == "..") continue;
        std::string path = dir + "/" + name;

        if (hasSuffix(name, kDesktop)) {
            App app;
            if (parseDesktopFile(path, app))
                out.push_back(app);
        } else if (hasSuffix(name, kAppImage)) {
            out.push_back({name.substr(0, name.size() - kAppImage.size()), path});
        } else if (hasSuffix(name, kExecutable)) {
            out.push_back({name.substr(0, name.size() - kExecutable.size()), path});
        }
    }
    closedir(d);
}

// Splits $PATH on ':', same convention as xdgApplicationDirs below.
static std::vector<std::string> pathDirs() {
    std::vector<std::string> dirs;
    const char *path = std::getenv("PATH");
    if (!path || !*path) return dirs;

    std::string p = path;
    size_t pos = 0;
    while (pos <= p.size()) {
        size_t next = p.find(':', pos);
        if (next == std::string::npos) next = p.size();
        std::string part = p.substr(pos, next - pos);
        if (!part.empty()) dirs.push_back(part);
        pos = next + 1;
    }
    return dirs;
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

    for (const auto &dir : pathDirs())
        scanPathDir(dir, apps);

    std::sort(apps.begin(), apps.end(), [](const App &a, const App &b) {
        return a.name < b.name;
    });

    for (const auto &app : apps)
        std::cout << app.name << '\t' << app.exec << '\n';

    return 0;
}
