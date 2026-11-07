# Performance benchmark (`bench/`)

Scope: measuring the Quickshell shell (`dots/.config/quickshell/ii/`) so that changes can be compared before and after. `bench/run` is a Python script (stdlib only) that benchmarks a snapshot of the shell in a sandbox, prints a table and saves the results as JSON.

## Quick use

```fish
cd ~/git/dots-hyprland
bench/run                       # working tree: startup suite + micro suite (~3 min)
bench/run --baseline main       # A/B: main vs working tree, interleaved (~6 min)
bench/run --suite micro         # only the QML micro-benchmarks (~15 s)
bench/run --suite micro --filter t3 --baseline HEAD~3
bench/run --compare bench/results/<file>.json   # compare with a saved run
```

Other flags: `--ref REF` benchmarks a git ref instead of the working tree, `--runs N` sets the number of startup runs per tree (default 5), `--idle S` sets the idle window (default 10 s), `--samples N` sets the samples per micro-benchmark (default 10), `--no-save` skips writing results, and `--keep` keeps the work dir (snapshots, sandboxes, `qs` logs) for debugging. Use `bench/run --help` for the full list.

**Reading the table:** each metric shows the median and the min..max range across runs. With a baseline, `change` is the change in the median. `verdict` is `slower` or `faster` only when the two ranges don't overlap **and** the change is at least 5% (`MIN_CHANGE_PCT` in `bench/run`). Otherwise it's `~` (noise). With fewer than 3 samples on either side (`MIN_SAMPLES`, e.g. `--runs 1`) it's `?`. Every metric is "lower is better".

**Noise:** results depend on the machine and its load. Compare runs from the same machine only. Prefer `--baseline`, which runs both trees in the same session, alternating, so drift affects both equally. With `--compare`, the two runs come from separate sessions. Micro-benchmark ranges are tight within one session but can shift by tens of percent between sessions, so treat a `--compare` verdict as a hint. Close heavy apps first: `bench/run` warns when the load average is above a quarter of the core count.

## What is measured

### Startup suite (`--suite startup`)

Each run launches the full `shell.qml`, waits for the bar, sits idle, then opens and closes some panels over IPC. One untimed warm-up start per tree fills the QML disk cache first, so the numbers are for a warm start, which is the usual case (`Ctrl+Super+R`).

| Metric | Meaning |
|---|---|
| `startup.loaded_ms` | launch until Quickshell logs `Configuration Loaded` (the root component finished loading) |
| `startup.bar_ms` | launch until the nested compositor reports the `quickshell:bar` layer |
| `startup.cpu_ms` | shell CPU time (all threads, from `/proc/<pid>/stat`) at bar + `--settle` (3 s) |
| `idle.cpu_pct` | shell CPU use over the idle window (100% = one core) |
| `idle.children_cpu_pct` | CPU of the shell's child processes over the idle window (scripts, `node` T3 bridge, …) |
| `memory.rss_mb`, `memory.pss_mb` | from `/proc/<pid>/smaps_rollup` after the idle window. Includes GPU driver mappings. |
| `panel.ipc_overhead_ms` | round trip of a bare `qs ipc … show`. Every `open_ms` includes about this much: ~39 of the ~40 ms measured on the dev machine, so `first_open_cpu_ms` says more about a panel's cost. |
| `panel.<p>.first_open_ms` | first `qs ipc call <target> open` until the panel's layer is mapped (this is when lazy content loads) |
| `panel.<p>.open_ms` | the same for the 2nd and 3rd opens (median) |
| `panel.<p>.first_open_cpu_ms` | shell CPU time from the first open until 0.5 s later |

The panels are listed in `PANELS` in `bench/run`: overview (`search`), `sidebarRight` and `sidebarLeft`. Layer polling goes straight to the nested Hyprland's socket (`j/layers`), not through `hyprctl`, so it adds very little latency.

### Micro suite (`--suite micro`)

`bench/qml/bench.qml` is a harness that runs JS/QML hot paths in-process against the real services. Each benchmark is warmed up for 200 ms. Then each sample repeats `run()` until it has taken ≥100 ms, so sub-millisecond operations can be measured with `Date.now()`. `gc()` runs between samples. The result is the median time per operation.

| Benchmark | What it exercises |
|---|---|
| `t3.snapshot.update` | `T3.handle()` of a 512-thread snapshot of known threads (every bridge reconnect), then the published lists |
| `t3.snapshot.initial` | the same into an empty machine (every `T3Thread` object is created) |
| `t3.thread.update` | one thread update with 512 loaded (steady state) |
| `cliphist.update` | assigning 1000 entries to `Cliphist.entries`, which rebuilds `preparedEntries` (on every copy) |
| `cliphist.search` | `Cliphist.fuzzyQuery()` over 1000 entries (a keystroke in clipboard search) |
| `appsearch.query` | `AppSearch.fuzzyQuery()` over this machine's desktop entries (a keystroke in app search) |
| `appsearch.guessIcon` | `AppSearch.guessIcon()` for a mix of window classes (bar, dock, overview, taskbar) |

T3 and cliphist inputs are synthetic and deterministic (`bench/qml/benchmarks/t3data.js`, `cliphistdata.js`). T3 threads go to a fake `bench` machine, so they never mix with what the real bridge reports. AppSearch uses the installed apps, and the app count is saved in the result's `meta`.

As a check: against `542b7d92^` (before the T3 freeze fix), `t3.snapshot.update` takes ~1240 ms, while after the fix it takes ~6 ms.

## How it works

1. **Snapshot.** The shell is copied into a temp work dir: the working tree is copied directly, and a ref comes from `git archive <ref> dots/.config/quickshell/ii`. `git archive` leaves out the `shapes` submodule, so it is copied from the working tree. Then `bench/qml/bench.qml` goes to the snapshot root and `bench/qml/benchmarks/` goes to `<snapshot>/benchmarks/`, so `qs.*` imports resolve against the code under test.
2. **Sandbox.** Each tree gets private `XDG_CONFIG_HOME`/`XDG_STATE_HOME`/`XDG_CACHE_HOME` dirs. They hold a `first_run.txt` marker (which skips the welcome app and `switchwall.sh`) and a `config.json` that sets only the wallpaper (the repo's default wallpaper). Everything else uses `Config.qml` defaults, not `~/.config/illogical-impulse/config.json`. `qs` runs under `dbus-run-session`, so it has its own D-Bus session: no fight over the notification server, tray or MPRIS with the real shell, and portals start fresh inside it. The cliphist DB is under the sandbox cache, so it is empty, and the T3 token is missing, so the bridge stays offline.
3. **Nested compositor.** `bench/run` starts `Hyprland -c bench/hypr.lua`. It opens as a **window on the current desktop** for the duration of the run. `qs` gets the nested `WAYLAND_DISPLAY` and `HYPRLAND_INSTANCE_SIGNATURE`, so its dispatches, global shortcuts and `hyprctl` calls hit the nested instance. A purely headless output was tried and doesn't work: GBM can't allocate buffers for a headless output on this NVIDIA setup.
4. **Teardown.** `qs`, its D-Bus daemon and the nested Hyprland each run in their own process group, which is killed afterwards.

**What is not isolated:** `Directories.qml` still runs `rm -rf` on `/tmp/quickshell/media/{cliphist,images}` (hard-coded paths shared with the real shell, which only contain caches). The polkit agent registration fails with "An authentication agent already exists" (harmless: the real agent stays). `XDG_DATA_HOME` is not sandboxed, so desktop entries and icons are the real ones.

## Results files

Each benchmarked tree is saved as `bench/results/<YYYYMMDDTHHMMSS>-<commit>[-dirty].json` (gitignored, because the numbers depend on the machine). The file holds `subject` (ref, commit, dirty), `host` (CPU, kernel, Quickshell/Hyprland versions, nested output size, load), `settings`, `startup` (`{metric: {median, min, max, samples}}`) and `micro` (`{name: {median_ms, min_ms, max_ms, samples, meta, description}}`, or `{skipped}`). An A/B run saves both trees. `--compare FILE` reads any such file as the baseline.

## Adding a micro-benchmark

1. Add `bench/qml/benchmarks/<Name>.qml` with a root `Benchmark { … }` (or `T3Bench` for T3). Set `name` (dotted, `area.operation`) and `description`, and implement `run()`. Optional hooks: `setup()`/`teardown()`, `ready()` (return false until async inputs have loaded, up to 15 s), and `perOp: true` with `beforeEach()` for operations of several ms that need fresh state each time (`beforeEach` is untimed).
2. Start the file with `import qs.services` / `import qs.benchmarks` as needed. Same-directory types are not implicit under Quickshell's `qs.*` import scheme.
3. Add the file name to `files` in `bench/qml/bench.qml`.
4. Use inputs that are deterministic, or record their size in `meta`.

Benchmarks are loaded one at a time with `Qt.createComponent`. One that doesn't compile against an older ref (e.g. a service it uses didn't exist yet) shows up as `skip` and doesn't break the run.

**Gotchas:**
- Quickshell's import scanner stops at the first `{` in a file. A brace in a comment above the imports (e.g. a JSON example) hides the imports below it, and you get `module "qs.benchmarks" is not installed`.
- `Qt.quit()` does nothing under Quickshell. The harness prints `BENCH {"done":true}` and `bench/run` kills the process.
- Only directories that some file imports are registered as modules. That is why `bench.qml` imports `qs.benchmarks` without using it.

## Adding a startup metric or panel

Panels: add `(name, ipc target, layer namespace)` to `PANELS` in `bench/run`. The IPC target needs `open()` and `close()` (see the IPC table in [quickshell/architecture.md](quickshell/architecture.md#ipc-and-global-shortcuts)), and the namespace must only be mapped while the panel is open. Other metrics: set `m["<group>.<name>"]` in `run_startup()` and describe it in `METRICS`.
