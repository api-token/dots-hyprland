import QtQuick

// Base for one micro-benchmark. bench.qml calls setup(), then run() repeatedly, then teardown().
QtObject {
    required property string name
    property string description: ""
    // Extra facts reported with the result, e.g. input sizes.
    property var meta: ({})
    // Time each run() on its own and call beforeEach() (untimed) before it. Use for operations of
    // a few ms or more that need fresh state every time.
    property bool perOp: false

    // Return false until async inputs have loaded; bench.qml waits up to 15 s.
    function ready() {
        return true;
    }
    function setup() {}
    function beforeEach() {}
    function run() {}
    function teardown() {}
}
