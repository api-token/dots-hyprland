# Distro detection and dependency packaging

## Scope

`sdata/dist-*` translates the shell/compositor's package requirements into native distro packages or a cross-distro Nix environment. Arch is the reference dependency set; Fedora and Gentoo are community-maintained equivalents. Nix is experimental and aimed at non-NixOS distributions (`sdata/lib/dist-determine.sh`, `sdata/dist-nix/README.md`). Installed configuration copying remains a separate stage; see [setup and install](setup-and-install.md).

| Path | Purpose |
| --- | --- |
| `sdata/lib/dist-determine.sh` | OS/architecture identification and route variables |
| `sdata/subcmd-install/1.deps-router.sh` | Native/Nix routing and community dependency freshness check |
| `sdata/dist-arch/install-deps.sh` | pacman/yay bootstrap and local PKGBUILD installer |
| `sdata/dist-arch/illogical-impulse-*/PKGBUILD` | Meta dependency groups and actual built packages |
| `sdata/dist-arch/previous_dependencies.conf` | Migration list for formerly explicit package dependencies |
| `sdata/dist-fedora/{install-deps.sh,feddeps.toml}` | DNF/COPR/local RPM setup and grouped package data |
| `sdata/dist-gentoo/{install-deps.sh,metapkgs.sh}` | Portage preparation and list of II package atoms |
| `sdata/dist-gentoo/overlay/` | Local `ii-dots` repository: ebuilds, Manifests, profiles, metadata |
| `sdata/dist-gentoo/{keywords,useflags,additional-useflags,ii-dots.conf}` | Testing acceptance, direct/transitive feature requirements, repository config |
| `sdata/dist-nix/install-deps.sh` | Nix/Home Manager bootstrap and flake activation |
| `sdata/dist-nix/home-manager/{flake.nix,flake.lock,home.nix,quickshell.nix}` | Pinned inputs, package list, desktop module settings, Qt-wrapped Quickshell |
| `sdata/dist-*/outdate-detect-mode` | Explicit/automatic freshness policy |
| `sdata/deps-info.md` | Purpose inventory and hints for translating package names |

## Detection and routing

`setup:5` sources distro detection before parsing the subcommand. `sdata/lib/dist-determine.sh:72` prefers a repository-root `os-release` override, otherwise `/etc/os-release`; missing both aborts. It parses lowercase `ID` and `ID_LIKE`, stripping quotes, into exported `OS_DISTRO_ID` and `OS_DISTRO_ID_LIKE`.

| Match, in source order (`sdata/lib/dist-determine.sh:88`) | `OS_GROUP_ID` | Route / notice |
| --- | --- | --- |
| ID `arch`, `endeavouros`, `cachyos` | `arch` | Native, standard info |
| Exact ID_LIKE `arch` | `arch` | Native with alike warning |
| ID or exact ID_LIKE `gentoo` | `gentoo` | Native, community notice; alike warning as applicable |
| ID or exact ID_LIKE `fedora` | `fedora` | Native, community notice; alike warning as applicable |
| ID `opensuse-leap`/`opensuse-tumbleweed`, or matching `suse`/`opensuse` ID_LIKE regex | `suse` | Forces `INSTALL_VIA_NIX=true` |
| ID or exact ID_LIKE `debian` | `debian` | Forces Nix |
| Anything else, including an unhandled NixOS ID | `fallback` | Forces Nix and fallback notice |

Most `ID_LIKE` tests are exact strings, not token membership: a multi-token value containing `arch`, `gentoo`, `fedora`, or `debian` may fall through. Do not broaden distro support claims based only on distribution ancestry.

`MACHINE_ARCH=$(uname -m)` is exported; any value other than `x86_64` adds a warning, not an abort (`sdata/lib/dist-determine.sh:124`). Package metadata may allow other architectures, but the installer only claims x86_64 support.

The command-specific options can also select `--via-nix`. The dependency router checks this first, sets `TARGET_ID=nix`, and sources that installer without the native freshness check (`sdata/subcmd-install/1.deps-router.sh:46`). Otherwise only Arch/Gentoo/Fedora native routes are implemented. `OS_GROUP_ID` is retained under Nix: later host setup and home-file tweaks can still depend on the host group.

A custom root `os-release` is ignored by Git (`.gitignore`). It changes selection, not the running OS or its package manager. `ensure_cmds` has separate bootstrap implementations for Arch/Debian/Fedora/SUSE only (`sdata/lib/functions.sh:392`); this helper is not a complete native desktop dependency route.

## `outdate-detect-mode`

`outdate_detect` (`sdata/subcmd-install/1.deps-router.sh:5`) unshallows the checkout if necessary, gets the latest Git commit timestamp touching `sdata/dist-arch` and the target directory, then reads the target's mode file.

| Mode / result | Meaning |
| --- | --- |
| `AUTO` (or another nonspecial value) | Compare latest path commit timestamps |
| `WIP` | Always treated as unfinished/outdated |
| `FORCE_OUTDATED` | Always treated as outdated |
| `FORCE_UPDATED` | Always accepted without timestamp comparison |
| `EMPTY_SOURCE`, `EMPTY_TARGET` | No timestamp found for the corresponding path; treated as outdated |
| `OUTDATED`, `UPDATED` | Target timestamp older than Arch, or at least as new |

Current files: Arch/Fedora/Gentoo say `AUTO`; Nix says `WIP`. The native check runs only for Gentoo/Fedora; Arch is the reference and Nix bypasses it. This is a directory commit-time heuristic, not a package parity test. Even documentation-only commits can affect timestamps. Untracked edits do not establish freshness.

Outdated native routes print warnings and require an explicit interactive continuation. With `ask=false` they abort unless `--ignore-outdate` sets `IGNORE_OUTDATE_CHECK=true` (`sdata/subcmd-install/1.deps-router.sh:92`). The flag bypasses the stop, not the messages. Upstream's [notification workflow](contributing-and-ci.md) posts Arch changes to discussion #2140, but its repository guard disables that job on this fork.

## Arch: local PKGBUILDs

`sdata/dist-arch/install-deps.sh:42` requires pacman, exports `PACMAN_AUTH=sudo` if unset, offers removal of deprecated packages, and performs `pacman -Syu` unless `SKIP_SYSUPDATE=true`. It bootstraps `yay-bin` in `/tmp/buildyay` when yay is missing. Deprecated dependency removal uses `pacman -Rdd` and is an explicit migration action (`:15`); do not reuse that pattern for ordinary removal. MicroTeX (`illogical-impulse-microtex-git`) was dropped with the AI chat's LaTeX rendering and is in that list, so the next Arch setup offers to remove it; Gentoo/Fedora/Nix leave an existing install in place.

`implicitize_old_dependencies` strips `previous_dependencies.conf` and marks matching explicitly installed old dependencies as `--asdeps` (`:24`). This permits packages no longer required by II meta-packages to become orphans; the reference file is not the active dependency list.

The hardcoded `metapkgs` array (`:92`) selects these groups:

| Packages | Role |
| --- | --- |
| `illogical-impulse-{audio,backlight,basic,fonts-themes,kde,portal,python,screencapture,toolkit,widgets,hyprland}` | Dependency containers: `depends=(...)`; see the basic/hyprland PKGBUILDs for minimal examples |
| `illogical-impulse-quickshell-git` | Builds a pinned Quickshell revision and declares extra Qt/QML dependencies |
| `illogical-impulse-bibata-modern-classic-bin` | Downloads/packages Bibata cursor assets |

For each package, `install-local-pkgbuild` sources the PKGBUILD, uses yay to install `depends` as dependencies, then runs `makepkg -Afsi --noconfirm` from that package directory (`sdata/dist-arch/install-deps.sh:74`). Normal installs can leave package build artifacts there; `--clean` only removes root `cache/`. The README asks maintainers not to implement `pkgver()` because it edits Git-tracked PKGBUILDs during builds (`sdata/dist-arch/README.md`).

`illogical-impulse-quickshell-git/PKGBUILD:1` pins commit `4f508be500dea6e5732cc3d50382a0048b17e7b1`, provides/conflicts with regular Quickshell packages, sets a QML install prefix, and installs `quickshell-check.hook`. The hook runs `quickshell --private-check-compat` after installing/upgrading `qt6-base` or `qt6-wayland` (`quickshell-check.hook:1`). Runtime Qt modules belong in `depends`; compiler/build-only inputs belong in `makedepends`.

After core packages, the installer conditionally installs available dinit service packages when `dinitctl` exists (`install-deps.sh:105`). `plasma-browser-integration` is an optional extra, selected automatically in non-asking mode unless skipped/already installed (`:127`).

Arch uninstall loops over II packages and plasma browser integration with `yay -Rns` (`sdata/dist-arch/uninstall-deps.sh`). It is interactive through the shared wrapper and depends on the local package-manager dependency graph.

## Fedora: TOML groups, COPR, and released RPMs

`sdata/dist-fedora/install-deps.sh` requires DNF (its message says Fedora 42+); the README reports testing Fedora Everything 44 x86_64. These are source claims, not installations verified here.

Lifecycle (`install-deps.sh:46`):

1. Upgrade with refresh unless skipped; delete Quickshell versionlock; install yq and createrepo_c.
2. Read `[copr].repos` from `feddeps.toml` and enable each COPR (`:66`). Current entries include the II contributor repo, `sdegler/hyprland`, Darkly, eza, and Starship.
3. Delete/recreate `$HOME/.cache/illogical-impulse-repo`, download **all** release assets from `end-4/ii-package-builds` tag `packages-fedora`, and generate repo metadata (`:27`). RPM build specs/content are external to this checkout; the declared `rpm_specs` path is not used in the current installer.
4. Read each `[groups.NAME]`, deduplicate `packages`, and install with optional `install_opts` (`:77`). The `illogical-impulse` group receives `--repofrompath=... --nogpgcheck` for the downloaded local repo and contains Quickshell/matugen.
5. Attempt to restore the Quickshell versionlock (`:96`). `nolock_qs` is referenced here but is not a declared option in the shared install parser.

`feddeps.toml` covers audio/backlight/basic/cursor/fonts/Hyprland/KDE/portals/Python/Quickshell/screencapture/toolkit/widgets/extras. Names are Fedora-specific: e.g. `qalculate` provides `qalc`, while Fedora's `libqalculate` alone does not (`sdata/deps-info.md`). Selected groups disable weak deps. The Python group includes development packages and Python 3.12; actual Python libraries are installed into the shared uv venv later.

The `r` wrapper records before/after DNF transaction IDs into `sdata/dist-fedora/user_data.yaml` (`install-deps.sh:15`). Not every operation is wrapped: upgrade, initial yq installation, COPR enablement, and versionlocks are outside it. The data file is not covered by current `.gitignore`. Uninstall reads recorded transactions in reverse and offers `dnf history undo` (`sdata/dist-fedora/uninstall-deps.sh`); it is not a complete host rollback.

The README documents post-install application overrides for network settings and changing the update command from pacman to dnf (`sdata/dist-fedora/README.md`). The legacy file copier also appends a Fedora polkit command to `hypr/hyprland/execs.conf`; that old-format path is not the new Lua startup configuration (`sdata/subcmd-install/3.files-legacy.sh:71`). The separately stored Fedora extra is not selected by the installer; see [extras](contributing-and-ci.md).

## Gentoo: local overlay and USE configuration

`sdata/dist-gentoo/install-deps.sh` warns that global `elogind` or `systemd` USE selection is expected. It then:

1. Installs eselect-repository, rsync, and smart-live-rebuild; enables GURU and hyproverlay when missing (`:15`). The README's shorter list omits hyproverlay; follow the actual script.
2. Rsyncs local `overlay/` with `--delete --chown=root:root` to `/var/db/repos/ii-dots`, and copies `ii-dots.conf` under `/etc/portage/repos.conf` (`:27`). The config uses `auto-sync = no`: rerunning installation updates the local overlay, not ordinary `emerge --sync`.
3. Appends `~$(portageq envvar ACCEPT_KEYWORDS)` to every line of `keywords` and writes `/etc/portage/package.accept_keywords/illogical-impulse` (`:35`). Live ebuild lines already include `**`; preserve that distinction when editing the list.
4. Overwrites `/etc/portage/package.use/illogical-impulse` with `useflags`, then appends `additional-useflags` (`:40`). The latter represents transitive requirements (Qt, graphics, codecs, etc.).
5. Syncs repositories, updates/deep-rebuilds `@world` for new USE settings, and rebuilds live packages (`:43`). These operations do **not** consult `SKIP_SYSUPDATE`.
6. Sources `metapkgs.sh` and emerges every atom, then ensures Python 3.12 (`:47`).

Overlay metadata uses EAPI 8, repository name `ii-dots`, masters `gentoo guru`, thin unsigned Manifests (`overlay/{metadata/layout.conf,profiles/eapi,profiles/repo_name}`). `profiles/updates/3Q-2026` records category moves for II packages and Darkly. Keep migrations synchronized with atom changes.

Most II ebuilds are dependency containers using `RDEPEND`; actual cursor/font/theme/Quickshell ebuilds also fetch/install content. The intended complete set is amd64; individual ebuild keywords vary (`sdata/dist-gentoo/README.md`). Quickshell's `0.1.0-r8` ebuild pins the same commit as current Arch, defines Qt slot/subslot dependencies, optional backend/service USE flags, a strict-aliasing patch, and CMake feature switches. It forces the bfd linker if mold was selected (`overlay/gui-apps/illogical-impulse-quickshell-git/illogical-impulse-quickshell-git-0.1.0-r8.ebuild`). Do not infer it tracks latest upstream merely from `-git` in its name.

Gentoo uninstall removes atoms in `metapkgs`, the copied overlay, repos.conf, keyword file, and USE file. **Current gap:** `sdata/dist-gentoo/uninstall-deps.sh` uses `metapkgs` but does not source `metapkgs.sh`; a fresh `setup uninstall` process has not initialized that array. Thus the package-removal loop normally has no entries, although overlay/config cleanup still runs. It also does not depclean automatically. This doc records the gap; it does not fix it.

## Nix / Home Manager

This route is cross-distro WIP, not a dedicated NixOS module (`sdata/dist-nix/README.md`). It bootstraps host-native curl/Fish/swaylock/gnome-keyring through `ensure_cmds`, installs Nix if absent using the NixOS experimental installer, and bootstraps Home Manager release 25.11 if absent (`sdata/dist-nix/install-deps.sh:14`, `:69`).

`hm_deps` (`install-deps.sh:50`) writes the current username to `home-manager/username.nix`, **stages it in Git** so the flake sees it, runs `home-manager switch --flake .#illogical_impulse` with flakes/nix-command enabled, runs a store GPU setup script with sudo, and `git rm -f`s the temporary username file. Interruption can leave checkout/index changes. The startup warning explicitly says this can override an existing Home Manager configuration.

`home-manager/flake.nix` pins nixpkgs and Home Manager release 25.11 and a Quickshell commit via locked inputs. It hardcodes `x86_64-linux`, home directory `/home/USERNAME`, and `home.stateVersion="25.05"`; its comment says not to bump stateVersion routinely. The Quickshell input is `7511545...`, differing from current Arch/Gentoo `4f508be...`; parity is not implied.

`home.nix` enables generic Linux GPU support, portals/fontconfig, Hyprland with no generated settings, and a package list organized around Arch groups. Missing/TODO packages remain commented. Fish, keyring, and screen locking/authentication have host-native requirements; `dots-extra/via-nix/hypridle.conf` uses swaylock (`sdata/subcmd-install/3.files-legacy.sh:64`).

`quickshell.nix` builds a wrapper derivation around the flake's `qs`, supplies Qt/QML modules and KDE libraries, and prefixes `XDG_DATA_DIRS` with GSettings schemas. Add QML runtime dependencies here when required; putting them only in `home.packages` may not give the wrapper its needed runtime environment.

The Nix README explains PAM incompatibilities and GPU setup constraints; the current GPU helper depends on systemd. `2.setups.sh` skips ydotool service enabling under Nix. The README explicitly pauses general dotfile management through Nix; the Bash file-copy stage is still authoritative, though Home Manager creates some ancillary files (portal/fontconfig). There is no `dist-nix/uninstall-deps.sh`, and uninstall selects by native `OS_GROUP_ID`, so it does not undo the activated Home Manager generation.

## Recipes: updating dependencies

### Change an existing platform package

1. Trace the feature's actual executable/QML import/library to its package group. Read `sdata/deps-info.md`, then verify current definitions and installed executable names for the target distro.
2. **Arch:** edit the group's `depends`, or the actual package's `depends`/`makedepends`; increment the appropriate `pkgrel` for a changed recipe (existing PKGBUILDs demonstrate this pattern). For pinned Quickshell, update `_commit`, package metadata/checksums, and review the compatibility hook if necessary. Avoid `pkgver()`.
3. **Fedora:** edit the relevant `feddeps.toml` group's `packages` and optional `install_opts`. If unavailable in base repositories, identify/add the needed COPR. For the prebuilt II group, changes to RPM contents require work in the external package-builds project; editing this TOML does not build RPMs.
4. **Gentoo:** edit the appropriate ebuild `RDEPEND`/`DEPEND`/`BDEPEND` and feature constraints. Add direct requirements to `useflags`, transitive ones to `additional-useflags`, and testing/live atoms to `keywords` as needed. Use an ebuild revision when changing an existing version; regenerate affected Manifests for fetched content. Review `metapkgs.sh` and profile moves if package names/categories change.
5. **Nix:** add the mapped attribute to `home.nix`; add Quickshell runtime Qt modules to `quickshell.nix`. Change flake inputs/lock together when changing pins. Preserve stateVersion unless deliberately migrating user state; ensure non-Nix paths/PAM/service assumptions still hold.
6. Update dependency rationale and docs. Check freshness modes and compare Arch changes with community equivalents; a fresh timestamp is not evidence of runtime compatibility. Python PyPI changes belong in `sdata/uv` instead (see [setup](setup-and-install.md)).

### Add a new dependency group or distro

- A new Arch directory is not discovered by normal installation: add it to `metapkgs` and the uninstall list. Port the group into Fedora TOML, Gentoo atoms/overlay/config, and Nix as appropriate. Experimental Arch updater scans package directories, unlike the normal hardcoded install list.
- For a new native distro, add explicit detection in `sdata/lib/dist-determine.sh`, a `dist-NAME/install-deps.sh`, an `outdate-detect-mode`, and the native router allowlist entry in `1.deps-router.sh`. Add an uninstall implementation if supported and review host-specific stage 2/file behavior. Merely creating a directory does not enable routing.
- Source dependency stages through `setup`, not by invoking them directly: they require shared functions, paths, skip flags, and routing state. Use static syntax/data checks during research; exercise package-manager behavior only on an authorized appropriate host or disposable environment.
