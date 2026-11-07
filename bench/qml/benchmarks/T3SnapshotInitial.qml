import qs.services
import qs.benchmarks
import QtQuick

// The first snapshot from a machine: every thread object is created.
T3Bench {
    name: "t3.snapshot.initial"
    description: "T3.handle() a 512-thread snapshot into an empty machine, then publish the lists"
    perOp: true
    property var msg

    function setup() {
        msg = snapshot();
    }

    function beforeEach() {
        clear();
    }

    function run() {
        T3.handle(msg);
        settle();
    }
}
