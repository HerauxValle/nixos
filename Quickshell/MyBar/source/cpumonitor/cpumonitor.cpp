// Reads /proc/stat every INTERVAL_MS and prints:
//   cpu <usage_percent>
// to stdout, one line per tick. QML Process+SplitParser reads this.
// INTERVAL_MS is read from argv[1] (default 2000).

#include <chrono>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <thread>

static long long _prevIdle = 0, _prevTotal = 0;

static double readCpu() {
    std::ifstream f("/proc/stat");
    if (!f) return 0.0;
    std::string tag;
    long long u, n, s, i, iow, irq, sirq, steal;
    f >> tag >> u >> n >> s >> i >> iow >> irq >> sirq >> steal;
    long long idle  = i + iow;
    long long total = u + n + s + i + iow + irq + sirq + steal;
    long long dIdle  = idle  - _prevIdle;
    long long dTotal = total - _prevTotal;
    _prevIdle  = idle;
    _prevTotal = total;
    if (dTotal <= 0) return 0.0;
    return (1.0 - static_cast<double>(dIdle) / dTotal) * 100.0;
}

int main(int argc, char *argv[]) {
    int interval = 2000;
    if (argc >= 2) {
        const char *env = std::getenv("AETHERA_CPU_INTERVAL_MS");
        interval = env ? std::atoi(env) : std::atoi(argv[1]);
    } else {
        const char *env = std::getenv("AETHERA_CPU_INTERVAL_MS");
        if (env) interval = std::atoi(env);
    }
    if (interval < 200) interval = 200;

    // prime the counters
    readCpu();
    std::this_thread::sleep_for(std::chrono::milliseconds(interval));

    std::cout << std::fixed;
    std::cout.precision(1);

    while (true) {
        double usage = readCpu();
        std::cout << "cpu " << usage << "\n";
        std::cout.flush();
        std::this_thread::sleep_for(std::chrono::milliseconds(interval));
    }
}
