import qs.services
import qs.benchmarks
import QtQuick
import "cliphistdata.js" as Data

// One keystroke in the overview's clipboard search.
Benchmark {
    name: "cliphist.search"
    description: "Cliphist.fuzzyQuery() over 1000 clipboard entries"
    meta: ({ entries: 1000 })
    readonly property list<string> queries: ["hypr", "git reb", "ex", "quickshell material", "zzz"]
    property int tick: 0

    function setup() {
        Cliphist.entries = Data.entries(1000, 0);
    }

    function run() {
        return Cliphist.fuzzyQuery(queries[tick++ % queries.length]).length;
    }

    function teardown() {
        Cliphist.entries = [];
    }
}
