import qs.services
import qs.benchmarks
import QtQuick

// Called for window classes by the bar, dock, overview and taskbar.
Benchmark {
    name: "appsearch.guessIcon"
    description: "AppSearch.guessIcon() for a mix of window classes"
    readonly property list<string> classes: ["firefox", "org.kde.dolphin", "com.mitchellh.ghostty",
        "code-oss", "steam_app_1234", "jetbrains-idea", "Spotify", "unknown-app-xyz"]
    property int tick: 0

    function ready() {
        return AppSearch.list.length > 0;
    }

    function setup() {
        meta = { apps: AppSearch.list.length };
    }

    function run() {
        return AppSearch.guessIcon(classes[tick++ % classes.length]);
    }
}
