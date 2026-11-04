# Setup, installation, and maintenance commands

## Scope and entry points

`setup` is a Bash dispatcher for dependency installation, host setup, copying dotfiles, and maintenance. Run commands as the target desktop user; it rejects root and uses `sudo` internally (`setup:10`, `sdata/lib/functions.sh:78`). This document describes source behavior, not a verified installation on every supported host. No installer or diagnostic command was executed while writing it.

Related: [distro dependencies](distros.md), [Hyprland](hyprland.md), [dotfiles and theming](dotfiles-and-theming.md), [contributing and CI](contributing-and-ci.md).

| Path | Responsibility |
| --- | --- |
| `setup` | Repository-root selection, library loading, subcommand allowlist and explicit step dispatch |
| `sdata/subcmd-*/options.sh` | Per-command GNU `getopt` parsing, help, state variables |
| `sdata/subcmd-install/{0.greeting,1.deps-router,2.setups,3.files}.sh` | Ordered installation stages, sourced into one Bash process |
| `sdata/subcmd-install/3.files-legacy.sh` | Default installation target list |
| `sdata/subcmd-install/3.files-exp.{sh,yaml}` | Optional YAML-driven target list and interpreter |
| `sdata/subcmd-*/0.run.sh` | Non-install command implementations |
| `sdata/lib/environment-variables.sh` | XDG defaults, installer state paths, colors, temporary-file array |
| `sdata/lib/functions.sh` | Interactive execution/error wrappers, logging, backup/Git/package helpers |
| `sdata/lib/dist-determine.sh` | Host identification; see [distros](distros.md) |
| `sdata/lib/package-installers.sh` | Shared font/cursor/MicroTeX/uv builders and Python venv setup |
| `sdata/dist-*` | Platform dependency definitions and dependency uninstall implementations |
| `sdata/uv/` | Python input requirements, committed lock, Nix build environment, usage notes |
| `diagnose` | Independent support report generator with an optional public upload |
| `sdata/deps-info.md` | Human-maintained dependency purpose/reference inventory, principally Arch |

## Dispatch and execution model

1. `setup:2` changes to its own directory, sets `REPO_ROOT`, then sources environment variables, functions, package installers, and distro detection. Thus even help passes through distro detection before option parsing.
2. `setup:48` recognizes a fixed subcommand list. `install-deps`, `install-setups`, and `install-files` share `sdata/subcmd-install/options.sh`; other commands use their own directory.
3. `setup:65` sources `options.sh` when present. Install dispatch explicitly sources named scripts; it does **not** glob/sort numbered steps. Non-install commands source `0.run.sh` and exit (`setup:126`).
4. Full install prints host information, pauses, starts sudo keepalive, runs greeting → deps → setups → files unless the corresponding `SKIP_ALL*` flag is true (`setup:68`). The three partial install commands run only their named stage. Dependency/setup partial commands start keepalive; file-only does not.
5. `set -e` applies after library loading (`setup:11`). Sourced stages share variables, functions, working directory, and traps; do not treat them as independent executable scripts.

`sudo_init_keepalive` requests credentials once and runs `sudo true` every 60 seconds in a child process; install/deps/setups trap `sudo_stop_keepalive` on EXIT/INT/TERM (`sdata/lib/functions.sh:84`). Commands invoked elsewhere may still request sudo independently.

### Shared helper conventions

| Helper in `sdata/lib/functions.sh` | Behavior and caller contract |
| --- | --- |
| `try` (`:6`) | Runs a command and suppresses failure |
| `v` (`:7`) | Prints command; if `$ask` executes as true, asks yes/exit/skip/yesforall; calls `x` to execute |
| `x` (`:34`) | On error asks retry/exit/ignore; an ignored error permits an incomplete result |
| `showfun`, `pause` (`:58`, `:64`) | Print function definition; pause unless `ask=false` |
| `log_*`, `require_command` (`:144`) | Newer log and prerequisite helpers used heavily by experimental update commands |
| `git_auto_unshallow`, `latest_commit_timestamp` (`:127`) | Fetch complete history if shallow; latest path commit timestamp for distro freshness |
| `auto_update_git_submodule` (`:339`) | Runs recursive init/update if status starts with `+`, `-`, or `U` |
| `backup_clashing_targets` (`:346`) | Backs up matching immediate source/target names recursively using rsync; leaves targets in place |
| `install_cmds`, `ensure_cmds` (`:392`, `:450`) | Install missing command providers on Arch/Debian/Fedora/SUSE; maps `ip` to platform package name; other groups get a manual-install message |
| `dedup_and_sort_listfile` (`:463`) | Sorts unique paths through a temporary file |

The library also exposes path validation, comparison, timestamp backup, CI detection, progress, disk-space, and temporary-file helpers (`sdata/lib/functions.sh:176`). Their existence does not imply every stage calls them. Registering a temp file does not itself install an exit trap.

### Variables and on-disk state

Defaults come from `sdata/lib/environment-variables.sh:2`; existing nonempty XDG values are retained. They are ordinary shell assignments, not automatically exported to child processes.

| Variable | Default / use |
| --- | --- |
| `XDG_BIN_HOME` | `$HOME/.local/bin` |
| `XDG_CACHE_HOME` | `$HOME/.cache` |
| `XDG_CONFIG_HOME` | `$HOME/.config` |
| `XDG_DATA_HOME` | `$HOME/.local/share` |
| `XDG_STATE_HOME` | `$HOME/.local/state` |
| `BACKUP_DIR` | `$HOME/ii-original-dots-backup`, overridable by environment |
| `DOTS_CORE_CONFDIR` | `$XDG_CONFIG_HOME/illogical-impulse` |
| `INSTALLED_LISTFILE` | `$DOTS_CORE_CONFDIR/installed_listfile`; absolute installed paths accumulated for uninstall |
| `FIRSTRUN_FILE` | `$DOTS_CORE_CONFDIR/installed_true`; presence means later install |
| `REPO_ROOT`, `SUBCMD_NAME`, `SUBCMD_DIR` | Dispatcher context, shared with sourced steps |
| `OS_DISTRO_ID`, `OS_DISTRO_ID_LIKE`, `OS_GROUP_ID`, `INSTALL_VIA_NIX` | Distro routing context; see [distros](distros.md) |

`ask` is not initialized by the libraries. Full-install greeting chooses it unless `--force` sets it false (`sdata/subcmd-install/0.greeting.sh:33`). Partial installs bypass the greeting; do not assume all entry paths initialize it the same way.

## Installation stages

### Options

Actual parsing is `sdata/subcmd-install/options.sh:48` (prefer this over help text spelling). Main options:

- `-f` / `--force`: sets `ask=false`; does not turn every later read into a noninteractive operation.
- `-F` / `--firstrun`: forces first-run file treatment; help misspells the long option as `--fisrtrun`.
- `-c` / `--clean`: removes repository `cache/` during option phase 1.
- `--skip-allgreeting`, `--skip-alldeps`, `--skip-allsetups`, `--skip-allfiles`: skip whole stages.
- `-s` / `--skip-sysupdate`, `--ignore-outdate`, `--skip-plasmaintg`: dependency controls; implementation varies per distro.
- `--skip-backup`, `--skip-quickshell`, `--skip-hyprland`, `--skip-hyprland-entry`, `--skip-fish`, `--skip-fontconfig`, `--skip-miscconf`: default file-copy controls.
- `--core`: alias for skipping plasma integration, Fish, fontconfig, miscellaneous config; does not trim core dependency metapackages.
- `--fontset NAME`: validates a directory under `dots-extra/fontsets/` and substitutes its fontconfig source.
- `--exp-files`: selects YAML copier; `--via-nix`: selects Nix dependencies.

### 1. Dependencies

`sdata/subcmd-install/1.deps-router.sh:46` selects Nix first when requested/forced, otherwise native Arch/Gentoo/Fedora. Non-Arch native routes compare Git commit times with Arch before proceeding. It then sources `sdata/dist-TARGET/install-deps.sh` in the current shell. Package definitions and freshness controls are covered in [distros](distros.md).

### 2. Host setup and Python

`sdata/subcmd-install/2.setups.sh` performs these operations in order:

- Creates/populates the Python venv through `install-python-packages` (`:23`).
- Adds the user to `video,input`, plus `i2c` outside Fedora; creates the `i2c` group if needed (`:10`).
- On systemd (`:30`), writes Fedora `uinput` module/udev settings or non-Fedora `i2c-dev` module settings; enables ydotool except under Nix and enables Bluetooth. If no session bus address exists, uses `sudo systemctl --machine=USER@.host --user`. Fedora may symlink the system ydotool service into `/usr/lib/systemd/user/`.
- On OpenRC (`:56`), configures module loading, removes the old exact `modules=i2c-dev` assignment, enables modules/ydotool/Bluetooth, then starts the latter two.
- On dinit (`:73`), appends module and Hyprland `custom/env.lua` socket configuration, writes `/etc/dinit.d/ydotool`, and enables selected system/user services if their boot links are absent.
- On Gentoo, recursively changes ownership of `~/.local/` to the current user (`:101`).
- Sets GNOME interface font/dark preference and KDE widget style Darkly (`:105`).

The stage is not a complete machine provisioner; the greeting explicitly excludes drivers/hardware setup (`sdata/subcmd-install/0.greeting.sh:28`). Some steps append text, so the idempotence goal is not universal.

### 3. Copying files: wrapper versus target lists

`3.files.sh` is the shared implementation/wrapper, not a competing file list. It defines copy helpers, ensures XDG destination roots, computes first-run state, initializes submodules, offers an initial clash backup, selects legacy/experimental targets, installs Google Sans Flex outside Fedora if absent, records first-run state, deduplicates the installed list, and attempts a Hyprland reload (`sdata/subcmd-install/3.files.sh:194`).

Files are **copied**, not symlinked to the checkout. Editing `dots/` alone does not update an installed desktop. Default targets map `dots/.config/...` to `$XDG_CONFIG_HOME/...` and selected `dots/.local/share/...` to `$XDG_DATA_HOME/...`.

#### Default targets and customization preservation

Source of truth: `sdata/subcmd-install/3.files-legacy.sh`.

| Target | Default behavior |
| --- | --- |
| Miscellaneous immediate `dots/.config/*`, excluding quickshell/fish/hypr/fontconfig (`:7`) | Directories rsync with `--delete`; individual files overwrite; Konsole data copies without deletion |
| Entire `$XDG_CONFIG_HOME/quickshell` (`:22`) | rsync `--delete`, including configurations other than `ii`; local edits/additions here are not preserved |
| Fish (`:30`) | rsync `--delete` excluding `conf.d`; that directory is protected from normal copying/deletion |
| Fontconfig (`:37`) | rsync `--delete`, source replaced by `dots-extra/fontsets/NAME` when selected |
| `hypr/hyprland/` (`:46`) | rsync `--delete` |
| Existing `hypr/hyprland.conf` (`:51`) | Renamed to `.conf.old` to let the Lua entry load |
| `hypr/hyprland.lua` (`:58`) | Overwritten unless `--skip-hyprland-entry`; it is not first-run-only |
| `hypr/hyprlock.conf`, `hypr/hypridle.conf` (`:55`, `:64`) | Auto-backup file policy below; Nix substitutes its extra hypridle config |
| `hypr/custom/` (`:75`) | If directory exists, skipped entirely; otherwise copied |
| II SVG under data `icons/` (`:79`) | File overwrite; installed outside the miscellaneous skip block |

`install_file__auto_backup` (`sdata/subcmd-install/3.files.sh:102`) handles an existing target by moving it to `TARGET.old` and installing the source on first run; later runs install the source as `TARGET.new` while keeping the target. A missing target is installed normally. `.old`/`.new` names are fixed, not timestamped.

`install_dir__ignore_existing` sounds file-granular, but its wrapper first skips an existing destination directory entirely (`sdata/subcmd-install/3.files.sh:150`). This explains `hypr/custom/` preservation, including why later template additions do not appear automatically.

The optional initial backup checks matching immediate names in `dots/.config` and `dots/.local/share`; it recursively copies clashes into the corresponding `BACKUP_DIR` trees (`sdata/subcmd-install/3.files.sh:12`). In force mode it backs up only when the backup root does not already exist. It is not a new timestamped snapshot on each install. Uninstall does not automatically restore it.

`cp_file` appends the copied target's absolute path to `INSTALLED_LISTFILE`. Rsync wrappers append only output records whose itemization starts with `>`; they do not maintain a complete directory/symlink inventory (`sdata/subcmd-install/3.files.sh:46`). The final first-run marker and Google font directory are recorded separately. Do not infer full reversibility from this list.

#### Experimental YAML targets

`--exp-files` sources `3.files-exp.sh`, using a fixed `CONFIG_FILE=sdata/subcmd-install/3.files-exp.yaml` (`:24`). It requires Mike Farah-style `yq` and `envsubst`; it does not provision them itself. Interactive mode runs a wizard that **edits the tracked YAML in place** (`:27`, `:155`). Preferences select Fish/Zsh and Foot/Kitty patterns; the current YAML terminal default is `foot`. The stored keybinding preference has no corresponding conditional target in this YAML.

Patterns contain `from`, `to`, `mode`, optional rsync `excludes`, and optional `condition: {type, value}` matched against `user_preferences`. Destination expansion uses `envsubst`, so required variables must be exported in the environment; Bash-only XDG defaults are not sufficient for that child process (`3.files-exp.sh:165`). Fontset override is implemented (`:171`). YAML version `1.0` is present but not validated.

| Mode (`3.files-exp.sh:217`) | Actual operation |
| --- | --- |
| `sync` | rsync `--delete` for directories; ordinary rsync for files |
| `soft` | rsync without `--delete`; **overwrites differing existing files**, despite YAML comment saying it skips them |
| `hard` | `cp -r` |
| `hard-backup` | If differing target exists, rename to `.old.N`, then copy; skip when comparison says identical |
| `soft-backup` | If differing target exists, copy source as `.new`; otherwise copy missing target |
| `skip` | No operation |
| `skip-if-exists` | Copy only if destination absent |

This path is not equivalent to legacy: it syncs only `quickshell/ii`, has explicit miscellaneous patterns, does not consult legacy per-category skip variables, does not implement the Nix hypridle substitution, and uses raw copy/rsync rather than installed-list helpers. Its copies therefore are not recorded for uninstall; shared postprocessing still records the marker/font. Directory hash comparison includes path names from `md5sum`, so equal content in different roots is not a reliable equality test (`3.files-exp.sh:111`). Missing sources warn and skip. Symlinks, custom YAML overrides, and version enforcement appear as TODOs, not implemented features.

## Python venv and dependency reference

`install-python-packages` (`sdata/lib/package-installers.sh:69`) unconditionally selects `$XDG_STATE_HOME/quickshell/.venv`, attempts `uv venv -p 3.12`, activates it, installs `sdata/uv/requirements.txt`, then deactivates. Under Nix the pip step runs inside `sdata/uv/shell.nix` to provide native build tools/libraries. This belongs to setup stage 2, not the distro dependency stage.

- `sdata/uv/requirements.in`: direct package requests (image processing, color generation, GTK/Python tooling, Google auth/HTTP, etc.).
- `sdata/uv/requirements.txt`: committed compiled version lock. Change the input and regenerate it, rather than editing transitive pins individually (`sdata/uv/README.md`).
- `sdata/uv/shell.nix`: pkg-config, Meson, Ninja, Cairo, DBus, DBus-GLib, GLib.
- Runtime wrappers must activate/use this environment; `sdata/uv/README.md` explains wrapper and shebang strategies. Its `env.conf` examples predate Lua. The current setting is `dots/.config/hypr/hyprland/env.lua:16`, pointing to `$HOME/.local/state/quickshell/.venv`.

The installer respects an alternate `XDG_STATE_HOME`, but the shipped runtime Lua setting uses the fixed home-relative default. Keep those aligned when changing paths. The final warning in `3.files.sh:256` also still refers to old `.conf` filenames.

Shared `package-installers.sh` additionally provides source/cache builders for Rubik, Gabarito, Bibata, MicroTeX, and an upstream uv installer. These are helpers, not proof that the current native distro route invokes them. MicroTeX helper installs into `/opt/MicroTeX`; font helpers use `/usr/local/share/`.

`sdata/deps-info.md` distinguishes empty meta-packages from actual built packages and explains why dependencies exist. Use it to locate package groups and required executables, then verify against current platform definitions: it contains explicit uncertainty and older names (for example its matugen entry differs from current package scripts). Its `qalc` example illustrates why matching package names across distros is insufficient.

## Other subcommands

### `uninstall`

`sdata/subcmd-uninstall/0.run.sh:107` offers view/edit/delete of `INSTALLED_LISTFILE`, then scans empty directories under config and Konsole data for another deletion prompt. Deletion is interactive through `/dev/tty`; uninstall accepts only help options, with no `--force` switch. It deletes recorded targets, including directory targets recursively; it does not compare current content with the installed version.

Next it offers group removal and deletion of `/etc/modules-load.d/i2c-dev.conf`, then sources `sdata/dist-$OS_GROUP_ID/uninstall-deps.sh` if present (`:119`). The route does not use `INSTALL_VIA_NIX`. Services, venv, Fedora uinput settings, dinit configuration, and backup restoration are not comprehensively reversed. The command itself says it is incomplete and not fully tested (`:6`). See [distros](distros.md) for platform-specific gaps.

### `resetfirstrun` and `checkdeps`

`resetfirstrun` only removes `FIRSTRUN_FILE`, ignoring failure (`sdata/subcmd-resetfirstrun/0.run.sh:6`). It does not reset Quickshell settings or erase installed files. Its parser currently accepts long `--help` but omits advertised short `-h` from the short-option list (`sdata/subcmd-resetfirstrun/options.sh:14`).

`checkdeps PATH` reads one existing list file despite the help's plural ellipsis. It strips `#` comments/blank lines, splits spaces, and compares package names with the AUR compressed package list plus `pacman -Ssq` (`sdata/subcmd-checkdeps/{options,0.run}.sh`). It requires curl/gzip/pacman, writes `cache/dependencies_stripped.conf`, and does not refresh the repository databases. It expects a plain package list, not a PKGBUILD or TOML. The source requests avoiding repeated bandwidth-heavy use.

### `exp-update`

This experimental per-file updater is separate from `install`; source warns to prefer normal reinstall updates (`sdata/subcmd-exp-update/0.run.sh:781`). Its lifecycle:

1. Guard with repository `.update-lock`; trap cleanup (`:743`). `SOURCE_ONLY=true` skips main execution for helper tests.
2. Detect `dots/` or flat `.config`/`.local/bin`/`.local/share` layout (`:60`).
3. Load ignore patterns from repository `.updateignore`, `$XDG_CONFIG_HOME/illogical-impulse/updateignore`, and legacy `$HOME/.updateignore` (`:165`). Supports exact paths, globs, directory/root prefixes, and leading `**` substring patterns; this is its own matcher, not Git's ignore engine.
4. Optionally stash dirty tracked changes after a prompt, then `git pull --ff-only` and initialize submodules (`:823`). It does not pop the stash. Pull failure warns and continues locally.
5. With `-p/--packages`, check/rebuild Arch PKGBUILDs using pacman/makepkg, copying sources to temporary build dirs (`:514`, `:895`). Other platforms skip this facility.
6. Use reflog `HEAD@{1}` versus `HEAD` to identify commits and added/copied/modified/renamed files; fallback scans all regular files. `-f/--force` scans all (`:698`). Deleted upstream files are not deleted from home.
7. Map paths directly into `$HOME`, bypassing customized XDG roots and legacy install skip/preservation policies (`:1047`). New files copy directly; differing files offer replace/keep/`.old`/`.new`/diff/skip/ignore/timestamp backup choices (`:346`). Backups go to repository `.update-backups`; ignore choice appends to the XDG ignore file.
8. Mark all regular `~/.local/bin` files executable (`:1128`). It does not maintain `INSTALLED_LISTFILE`.

Options live in `sdata/subcmd-exp-update/options.sh`: `-n/--dry-run`, `-v/--verbose`, `-s/--skip-notice`, `--non-interactive`, and `--default-choice NAME` in addition to force/packages. Default conflict choice is skip. Noninteractive mode supplies defaults to `safe_read`: the notice and dirty-checkout confirmations default to no and abort, so unattended use needs a skipped notice and a clean checkout; package-build confirmation defaults to yes. Dry-run has guards around major mutations, but detached-HEAD checkout and stale-lock removal are outside those guards; do not assume a strict read-only contract.

`exp-update-tester.sh` contains temporary-repo/helper tests for structure mapping, ignores, flags, locks, caching, safe input, syntax, and optional ShellCheck. It is not called by `setup` or current GitHub workflows; execution was not verified for this documentation.

### `exp-merge`

`sdata/subcmd-exp-merge/0.run.sh:24` requires a clean tracked checkout and a remote literally named `upstream`. It fetches upstream, checks out `main`, fast-forwards it from `upstream/main`, switches/creates persistent `exp-merge-branch`, replaces checkout Quickshell files with `~/.config/quickshell`, commits `user changes`, and rebases onto main (`:61`, `:90`, `:125`).

It then prompts to apply/backup/save `quickshell.new`/skip; separately offers Hyprland replacement while preserving only `custom/`; backups live under repository `.exp-merge-backups` (`:153`, `:217`). On normal completion it returns to `main`, not the caller's original branch (`:322`). Paths are hardcoded under `$HOME/.config`, and `git add .` is broader than the copied subtree. Rebase failures print manual continue/abort instructions. Flags: `--dry-run`, `--skip-notice`, `--skip-fetch` (`options.sh`). Do not run as a routine doc/research check: this command deliberately changes branches/history/configuration and needs the appropriate authorization.

### `virtmon`

`sdata/subcmd-virtmon/0.run.sh` ensures wayvnc/lsof/jq/ip, starts `hypr_mon_guard` unless disabled, finds a free TCP port 5900–5999, creates headless output `TESTER-PORT`, configures it through `hyprctl`, and serves it with wayvnc bound to `0.0.0.0` (`:6`, `:42`, `:58`, `:81`). The displayed instructions specify empty VNC credentials. This exposes a real network listener.

Defaults are 1920×1080, 60 FPS, auto position, scale 1. Options include `--res`, `--fps`, `--pos`, `--sca`, `--ext`, `-d/--daemon`, `--no-guard`, and `-c/--clean` (`options.sh`). Foreground completion removes its output; background use requires cleanup. Cleanup removes `TESTER-*` outputs and controls `/tmp/wayvncctl_tester_*` sessions. `hypr_mon_guard` polls every 30 seconds and reloads Hyprland when no monitor is enabled; cleanup does not stop the guard. Environment knobs include `WAYVNC_LOGLEVEL` and `WAYVNC_EX_ARGS`.

## Diagnostics

`diagnose` intentionally avoids sourcing installer libraries (`diagnose:5`). It changes to repository root, deletes/recreates `diagnose.result`, forces English locale, rejects root, and tees command output plus success/failure markers (`:12`, `:20`). It records origin/HEAD/status/submodules, OS IDs and repository custom `os-release`, selected XDG/venv variables, default venv directory, Hyprland version, and Arch pacman package versions (`:65`). Non-Arch pacman failures appear in the report; this is not a cross-distro dependency validator. `_check_venv` is defined but not called.

After generation, if curl exists, it offers an explicit opt-in upload to public `https://0x0.st` (`diagnose:99`). Inspect the file before upload; do not run it as a passive read-only research operation. `diagnose.result` is ignored by Git.

## Common changes

### Add a subcommand

1. Create `sdata/subcmd-NAME/options.sh` using an existing small `getopt` parser/help function as a pattern; initialize command-specific variables there.
2. Create sourced `0.run.sh`, using shared library context and `v`/`x` for interactive installer operations. No shebang/executable bit is needed for sourced files.
3. Add `NAME` to `setup:52` and global help. The generic branch then loads `0.run.sh`. A command with multiple stages needs explicit dispatch, like install; numbered filenames alone do nothing.
4. Check traps/global variable names for collisions. Keep user shell examples Fish-compatible by invoking `./setup NAME`; implementation remains Bash.
5. Review without executing stages: `bash -n setup sdata/subcmd-NAME/options.sh sdata/subcmd-NAME/0.run.sh` from this checkout. Use disposable environments for behavior that changes the host.

### Add a dependency

1. Identify the executable/library and why the feature needs it; update `sdata/deps-info.md`.
2. For OS packages follow the per-platform recipes in [distros](distros.md), including the platform's actual executable provider and any build/runtime distinction.
3. For Python edit `sdata/uv/requirements.in`; from `sdata/uv/`, run `uv pip compile requirements.in -o requirements.txt` and review/commit both files (`sdata/uv/README.md`). This command works in Fish.
4. Verify callers activate/use the venv and keep shipped runtime environment paths aligned. Do not install a Python runtime dependency only into system Python.

### Add an installed file

1. Place the source under the appropriate `dots/.config` or selected data subtree; `dots/` is not copied wholesale.
2. Determine ownership: overwrite/delete-managed default, user-owned first-run template, or file with `.old`/`.new` policy. For default legacy installation add an explicit helper call to `3.files-legacy.sh` when outside its existing discovery rules. An immediate miscellaneous `.config` entry is already discovered automatically.
3. Use `install_file`, `install_file__auto_backup`, `install_dir__sync`, `install_dir__sync_exclude`, or the directory skip helpers defined in `3.files.sh`; do not add another `v`/`x` around these public wrappers. Review the exact existing-target behavior first.
4. Add/update an explicit YAML pattern too if experimental installs should receive it. Validate actual mode behavior, environment export, and exclusions; YAML copier does not inherit legacy skip or recording behavior.
5. Check backup/uninstall implications and update this doc plus the appropriate subsystem doc. For new package-provided assets, put them in distro packaging rather than silently mixing them into home-copy rules.
