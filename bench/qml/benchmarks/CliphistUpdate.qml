import qs.services
import qs.benchmarks
import QtQuick
import "cliphistdata.js" as Data

// Runs on every copy: Cliphist re-reads the history and re-prepares every entry for search.
Benchmark {
    name: "cliphist.update"
    description: "Assign 1000 clipboard entries to Cliphist and rebuild preparedEntries"
    meta: ({ entries: 1000 })
    property var lists: []
    property int tick: 0

    function setup() {
        // Distinct arrays, so every assignment is a real change.
        lists = [Data.entries(1000, 0), Data.entries(1000, 1)];
    }

    function run() {
        Cliphist.entries = lists[tick++ % 2];
        return Cliphist.preparedEntries.length;
    }

    function teardown() {
        Cliphist.entries = [];
    }
}
