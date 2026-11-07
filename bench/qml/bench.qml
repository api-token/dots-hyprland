//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

// Micro-benchmark harness. bench/run copies this file to the root of a snapshot of the shell
// (next to shell.qml) and bench/qml/benchmarks/ to <snapshot>/benchmarks/, so `qs.*` imports
// resolve against the code under test. Each result is printed as a "BENCH <json>" line.
// See docs/benchmark.md.
//
// qs.benchmarks is unused here, but Quickshell only registers directories that some file imports.
// Its import scanner stops at the first curly brace, so keep braces out of these comments.

import qs.modules.common
import qs.benchmarks
import QtQuick
import Quickshell

ShellRoot {
    id: root

    // One file per benchmark in benchmarks/. Loaded one by one, so a benchmark that doesn't
    // compile against an older ref is reported as skipped instead of breaking the run.
    readonly property list<string> files: [
        "T3Snapshot.qml",
        "T3SnapshotInitial.qml",
        "T3ThreadUpdate.qml",
        "CliphistUpdate.qml",
        "CliphistSearch.qml",
        "AppSearchQuery.qml",
        "AppSearchGuessIcon.qml",
    ]
    readonly property string filter: Quickshell.env("II_BENCH_FILTER") ?? ""
    readonly property int samples: parseInt(Quickshell.env("II_BENCH_SAMPLES") ?? "") || 10
    // A sample repeats run() until it takes at least this long, so sub-millisecond operations are
    // measurable with Date.now()'s 1 ms resolution.
    readonly property int sampleMs: 100

    function emit(obj) {
        console.log("BENCH " + JSON.stringify(obj));
    }

    function median(values) {
        const s = values.slice().sort((a, b) => a - b);
        const mid = Math.floor(s.length / 2);
        return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
    }

    function measure(b) {
        b.setup();
        // Warm up the JS engine's JIT and any lazy bindings.
        const warmEnd = Date.now() + 200;
        let warm = 0;
        do {
            b.beforeEach();
            b.run();
            warm++;
        } while (Date.now() < warmEnd || warm < 3);

        const times = [];
        for (let s = 0; s < root.samples; s++) {
            gc();
            if (b.perOp) {
                // beforeEach() is untimed, so time each run() on its own.
                b.beforeEach();
                const t0 = Date.now();
                b.run();
                times.push(Date.now() - t0);
                continue;
            }
            let n = 0;
            const t0 = Date.now();
            let elapsed = 0;
            do {
                b.run();
                n++;
                elapsed = Date.now() - t0;
            } while (elapsed < root.sampleMs);
            times.push(elapsed / n);
        }
        b.teardown();
        return {
            median_ms: root.median(times),
            min_ms: Math.min(...times),
            max_ms: Math.max(...times),
            samples: times.length
        };
    }

    function runOne(index) {
        if (index >= root.files.length) {
            root.emit({ done: true }); // bench/run stops qs here (Qt.quit() is a no-op in Quickshell)
            return;
        }
        const file = root.files[index];
        const next = () => Qt.callLater(() => root.runOne(index + 1)); // let the event loop run
        const comp = Qt.createComponent(Qt.resolvedUrl(`benchmarks/${file}`));
        const b = comp.status === Component.Ready ? comp.createObject(root) : null;
        if (!b) {
            root.emit({ name: file.replace(/\.qml$/, ""), skipped: comp.errorString().trim() || "createObject failed" });
            next();
            return;
        }
        if (root.filter && !b.name.includes(root.filter)) {
            b.destroy();
            next();
            return;
        }
        root.whenReady(b, Date.now() + 15000, () => {
            try {
                if (!b.ready())
                    throw new Error("inputs never became ready");
                const result = root.measure(b);
                root.emit(Object.assign({ name: b.name, description: b.description, meta: b.meta }, result));
            } catch (e) {
                root.emit({ name: b.name, skipped: String(e) });
            }
            b.destroy();
            next();
        });
    }

    // Polls b.ready(), for inputs that services load asynchronously (e.g. desktop entries).
    function whenReady(b, deadline, then) {
        if (b.ready() || Date.now() > deadline) {
            then();
            return;
        }
        retryTimer.job = () => root.whenReady(b, deadline, then);
        retryTimer.start();
    }
    Timer {
        id: retryTimer
        property var job
        interval: 100
        onTriggered: job()
    }

    property bool started: false
    function start() {
        if (started || !Config.ready)
            return;
        started = true;
        startTimer.start();
    }
    Connections {
        target: Config
        function onReadyChanged() {
            root.start();
        }
    }
    Component.onCompleted: root.start()
    // Give services a moment to finish their own async startup work.
    Timer {
        id: startTimer
        interval: 1500
        onTriggered: root.runOne(0)
    }
}
