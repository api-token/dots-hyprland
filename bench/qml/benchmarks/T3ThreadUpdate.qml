import qs.services
import qs.benchmarks
import QtQuick
import "t3data.js" as T3Data

// One thread changing status while 512 are loaded: the common steady-state message.
T3Bench {
    name: "t3.thread.update"
    description: "T3.handle() one thread update with 512 threads loaded, then publish the lists"
    property int tick: 0

    function setup() {
        T3.handle(snapshot());
        settle();
    }

    function run() {
        T3.handle(T3Data.threadUpdate(machine, 7, tick++));
        settle();
    }
}
