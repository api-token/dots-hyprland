import qs.services
import qs.benchmarks
import QtQuick
import "t3data.js" as T3Data

// Shared helpers for the T3 benchmarks. Threads go to a fake "bench" machine so they never mix
// with whatever the real bridge reports for "local".
Benchmark {
    readonly property string machine: "bench"
    property int threadCount: 512
    property int projectCount: 20
    meta: ({ threads: threadCount, projects: projectCount })

    function snapshot() {
        return T3Data.snapshot(machine, threadCount, projectCount, 42);
    }

    // What the panel waits for after a message: the published section lists. Older refs had
    // bindings instead of refresh(); bumping revision makes those recompute too.
    function settle() {
        if (typeof T3.refresh === "function")
            T3.refresh();
        else if (T3.revision !== undefined)
            T3.revision++;
        return T3.pinnedThreads.length + T3.activeThreads.length + T3.workingThreads.length
            + T3.snoozedThreads.length + T3.settledThreads.length + T3.attentionCount;
    }

    function clear() {
        T3.handle({ type: "state", machine: machine, online: false, error: "offline" });
        settle();
    }

    function teardown() {
        clear();
    }
}
