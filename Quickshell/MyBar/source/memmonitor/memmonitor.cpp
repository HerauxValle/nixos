// Reads /proc/meminfo every INTERVAL_MS and prints:
//   mem <used_GiB>/<total_GiB>
// to stdout, one line per tick. QML Process+SplitParser reads this.
// INTERVAL_MS is read from AETHERA_MEM_INTERVAL_MS env var (default 5000).

#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>

struct MemInfo {
    double totalGiB = 0.0;
    double usedGiB  = 0.0;
};

static MemInfo readMem() {
    std::ifstream f("/proc/meminfo");
    MemInfo m;
    if (!f) return m;
    std::string key;
    long long val;
    std::string unit;
    long long total = 0, available = 0;
    while (f >> key >> val) {
        std::getline(f, unit); // consume rest of line (unit "kB")
        if (key == "MemTotal:")     total     = val;
        if (key == "MemAvailable:") available = val;
        if (total && available) break;
    }
    m.totalGiB = total     / 1048576.0;
    m.usedGiB  = (total - available) / 1048576.0;
    return m;
}

int main() {
    int interval = 5000;
    const char *env = std::getenv("AETHERA_MEM_INTERVAL_MS");
    if (env) interval = std::atoi(env);
    if (interval < 500) interval = 500;

    std::cout << std::fixed << std::setprecision(1);

    while (true) {
        MemInfo m = readMem();
        std::cout << "mem " << m.usedGiB << "/" << m.totalGiB << "\n";
        std::cout.flush();
        std::this_thread::sleep_for(std::chrono::milliseconds(interval));
    }
}
