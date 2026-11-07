import qs.services
import qs.benchmarks
import QtQuick

// A snapshot for threads the shell already has: what every bridge reconnect sends.
T3Bench {
    name: "t3.snapshot.update"
    description: "T3.handle() a 512-thread snapshot of known threads, then publish the lists"
    property var msg

    function setup() {
        msg = snapshot();
        T3.handle(msg);
        settle();
    }

    function run() {
        T3.handle(msg);
        settle();
    }
}
