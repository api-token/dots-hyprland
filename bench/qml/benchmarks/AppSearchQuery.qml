import qs.services
import qs.benchmarks
import QtQuick

// One keystroke in the overview's app search. Uses this machine's installed apps.
Benchmark {
    name: "appsearch.query"
    description: "AppSearch.fuzzyQuery() over the installed desktop entries"
    readonly property list<string> queries: ["f", "fire", "term", "settings", "code", "zzz"]
    property int tick: 0

    function ready() {
        return AppSearch.list.length > 0;
    }

    function setup() {
        meta = { apps: AppSearch.list.length };
    }

    function run() {
        return AppSearch.fuzzyQuery(queries[tick++ % queries.length]).length;
    }
}
