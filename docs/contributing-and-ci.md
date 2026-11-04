# Contributing, automation, and optional extras

## Scope and repository identity

This checkout is the `api-token/dots-hyprland` fork of upstream `end-4/dots-hyprland` (illogical-impulse). At documentation time `git remote -v` reports only `origin=https://github.com/api-token/dots-hyprland.git`; there is **no configured remote named `upstream`**. Upstream identity is visible throughout `.github/README.md`, dependency scripts, templates, and workflow guards. Distinguish the upstream project from an actual local remote before using commands that fetch or merge it.

The fork's current history includes upstream merges and package-specific commits; this is not a clean-room reimplementation. `exp-merge` explicitly requires an `upstream` remote and fast-forwards `main` from it; do not assume the remote exists or invoke that command during research ([setup and install](setup-and-install.md)).

| Path | Responsibility |
| --- | --- |
| `.github/README.md` | Public project overview, install/wiki links, Hyprland 0.55 migration warning, screenshots/history |
| `.github/CONTRIBUTING.md` | Contribution scope, QML loading/style/performance guidelines, local development |
| `.github/pull_request_template.md` | Change description/readiness sections; one-feature-per-PR reminder |
| `.github/ISSUE_TEMPLATE/1-issue.yml` | Bug/support intake and diagnostic requirements |
| `.github/ISSUE_TEMPLATE/2-feature_request.yml` | Feature/use-case/extra-info intake |
| `.github/ISSUE_TEMPLATE/config.yml` | Disables blank issues |
| `.github/workflows/` | Issue moderation, distro-change notification, manually requested context dump |
| `.github/assets/illogical-impulse.svg` | Logo embedded in public README |
| `.github/FUNDING.yml` | Upstream `end-4` GitHub sponsorship target; other platforms unset |
| `dots-extra/` | Optional config assets, only some selected by installer branches |
| `licenses/` | Copies of licenses for borrowed code; per-file notices still required |
| `.gitignore`, `.gitmodules` | Generated/local file exclusions and shapes submodule declaration |

Related: [setup](setup-and-install.md), [distro dependencies](distros.md), [Hyprland](hyprland.md), [dotfiles/theming](dotfiles-and-theming.md), [Quickshell architecture](quickshell/architecture.md).

## Contribution conventions

`.github/CONTRIBUTING.md:3` asks for separate PRs for separate features/fixes and excludes unrelated personal changes, including changed defaults. Features the maintainers do not personally want should be configurable/optional. It suggests discussing large prospective work first; that is advice rather than an automated approval gate.

For shell work (`.github/CONTRIBUTING.md:13`):

- Put optional/unnecessary-at-start content behind a QML `Loader`; place anchors/positioning on the Loader rather than its source component.
- Use `FadeLoader` and its `shown` property when dynamic content does not affect parent layout.
- Keep resource cost and daily usability proportionate. Fancy impractical additions should be configurable and disabled by default.
- Group properties/children meaningfully, use spaces around operators, prefer early returns to unnecessary nesting, and consider inline `component` definitions for local reuse (`:24`).
- Translation work starts at `dots/.config/quickshell/ii/translations/tools` (`:7`). See subsystem docs before changing translation generation.
- Python changes use the uv-created venv, not unmanaged system Python (`:55`, `sdata/uv/README.md`).

These guidelines are prose; none of the current workflows enforces QML formatting, performance, commit style, or tests.

### Local development

The contribution guide assumes Arch-based Linux (`.github/CONTRIBUTING.md:33`). Its complete path is installation into a desktop user account, editing installed files, copying relevant changes into a fork, and opening a PR. Its partial-shell path needs Hyprland plus development Quickshell and a copy of the Quickshell directory; this intentionally does not exercise every integration.

For QML language tooling, the guide creates `~/.config/quickshell/ii/.qmlls.ini` and suggests the official Qt Qml editor extension with `/usr/bin/qmlls6` (`:51`). That local LSP marker is ignored by Git.

The guide starts Hyprland without UWSM and runs `pkill qs; qs -c ii` to observe shell logs; installed QML edits reload live (`:58`). This command stops a running shell, so use it intentionally in a desktop session. It is valid Fish syntax. Do not confuse installed `~/.config/quickshell/ii` with the tracked `dots/.config/quickshell/ii`; the installer copies files rather than symlinking them. Normal reinstall syncs the entire Quickshell directory with deletion, so uncommitted installed edits need care ([setup](setup-and-install.md)).

To iterate from the checkout instead, replace the installed copy with a symlink: `mv ~/.config/quickshell/ii <backup>; ln -s (pwd)/dots/.config/quickshell/ii ~/.config/quickshell/ii` (Fish, run from the repo root), then restart the shell (Ctrl+Super+R). Paths resolve through `Quickshell.shellPath`, so scripts follow the link. QML edits reload live; spawned helpers such as the T3 bridge only restart with the shell. A later `./setup` replaces the link with a copy again.

The README's advertised bootstrap uses Bash process substitution, which is not directly Fish syntax. Prefer `./setup install` from an existing clone in Fish; the script's own shebang invokes Bash. This documentation does not execute it.

### PR and issue intake

`.github/pull_request_template.md` has “Describe your changes” and “Is it ready? Questions/feedback needed?” sections, plus an HTML comment requiring one feature per PR. Supply the concrete behavior change, relevant source paths, and actual validation; there is no checked-in PR checklist or automated test gate here.

The issue form (`.github/ISSUE_TEMPLATE/1-issue.yml`) applies label `ISSUE` and asks reporters to:

1. Search existing issues and read troubleshooting/usage (the reading checkbox is required; successful dotfile/system updates are optional checkboxes).
2. Supply `./diagnose` output, also saved as `diagnose.result`, in a required details block.
3. Describe the issue and attach logs; it suggests English locale and shell logs. A final acknowledgment that logs are needed is required.

How-to questions go to Discussions. Non-Arch distro-specific problems are directed to “Extra Distros” Discussions rather than upstream issues. A deliberately bait checkbox (“I've ticked the checkboxes without reading their contents”) is connected to automatic closure; do not check it in genuine reports.

The feature form (`2-feature_request.yml`) applies label `FEATURE`, asks for English, and provides proposed addition, use case, and extra-info fields. It contains no required-field validations. `config.yml` disables blank issues; it does not itself declare external contact links.

`diagnose` writes local output and offers an opt-in upload to a public pastebin; review the report before sharing ([setup](setup-and-install.md)). Do not invoke diagnostics merely to fill documentation with host details.

## GitHub workflows

The complete checked-in set is four YAML files under `.github/workflows/`. These automate project administration; **there is no build, package install, QML lint, or general test workflow in this set**. Workflow files describe intended execution; whether Actions/secrets/permissions are enabled on the fork is unverified.

| Workflow | Trigger and behavior | Permissions / fork implications |
| --- | --- | --- |
| `auto-close-issue.yml` (`:1`) | On newly opened issues, case-insensitively detects the exact checked bait checkbox, posts explanation, closes as not planned, then locks conversation. Uses GraphQL and REST fallbacks for close/lock (`:30`, `:67`, `:122`). | Declares `issues: write`, uses `GITHUB_TOKEN`; owner/repo come from event, with no upstream-only guard. An enabled fork workflow could act on fork issues. |
| `dist-update-notification.yml` (`:3`) | On pushes to `main` touching `sdata/dist-arch/**`, excluding its README, posts commit SHA/message to discussion #2140 via `gh api graphql`. | Job guard requires `github.repository == 'end-4/dots-hyprland'` (`:15`), so it skips on this fork. Uses `GITHUB_TOKEN` as `GH_TOKEN`; no explicit permissions block. Manual trigger is commented out. |
| `dump-github-context.yml` (`:3`) | `workflow_dispatch` only; prints JSON of the `github` context. | Debugging utility; no checkout, tests, or artifact upload. |
| `moderator.yml` (`:2`) | New issues, issue comments, PR review comments; checks out repository and invokes `github/ai-moderator@v1`. Enables spam/link-spam/AI detection, labels `spam`/`ai-generated`, minimizes detected comments. | Declares issues/PR write plus models/content read (`:13`). No upstream-only guard. Exact external action decisions are outside this repository and unverified. |

### Changing automation

1. Edit the relevant workflow trigger/job, preserving intended fork/upstream boundaries. For distro update notifications, the hardcoded upstream guard and discussion number are deliberate routing details.
2. Trace required GitHub API permissions and the token used. Do not assume `GITHUB_TOKEN` has permissions not declared here or granted by repository settings.
3. Keep issue checkbox wording synchronized with the literal matcher in `auto-close-issue.yml:30` if changing the bait field.
4. Treat executing a moderation/notification workflow as an external write. Static documentation/review does not authorize posting comments, closing issues, or dispatching a workflow.
5. For actual validation, use checks relevant to changed source; current Actions do not provide implementation tests automatically. The experimental updater has a standalone test script but no workflow invocation (`sdata/subcmd-exp-update/exp-update-tester.sh`).

## `dots-extra/`: optional assets and actual integration

`dots-extra` is not recursively copied into `$HOME`. Install selection lives in `sdata/subcmd-install/3.files-legacy.sh` and `3.files-exp.sh`; distinguish assets selected there from standalone examples.

| Extra | Content | Actual integration / limitations |
| --- | --- | --- |
| `fontsets/ar/fonts.conf` | Disables font subpixel RGBA and prepends `Noto Sans Arabic` for generic sans-serif to avoid Arabic fallback issues (file comment names Chromium/Discord). | `--fontset ar` replaces the installed fontconfig source directory in legacy copier (`3.files-legacy.sh:37`) and experimental override (`3.files-exp.sh:171`). Does not itself install the Noto font package. |
| `via-nix/README.md`, `via-nix/hypridle.conf` | Nix-specific idle config, swaylock with black background, 5-minute lock / 10-minute DPMS / 15-minute suspend, Quickshell lock focus after sleep. | Legacy copier chooses it for hypridle when `INSTALL_VIA_NIX=true` (`3.files-legacy.sh:64`). Nix bootstrap ensures native swaylock. Experimental copier still has this substitution as a TODO (`3.files-exp.sh:12`). |
| `fedora/hypr/hyprland/execs.conf` | Older `.conf` startup config for shell, keyring, idle, clipboard, cursor, geoclue, easyeffects, Fedora polkit executable. | No current installer reference to this file. Legacy copier instead appends polkit text to a destination `execs.conf`. Both are old-format paths relative to the current Lua Hyprland tree; automatic use by the Lua config is unverified. |
| `fcitx5/conf/classicui.conf` | Fcitx classic UI preferences: horizontal candidates, Google Sans Flex, Plasma theme, fractional scaling, accent/theme behavior. | No reference in `setup`, `sdata`, `.github`, or the inspected Hyprland/matugen configuration. Treat as a manual opt-in asset, not an installed default. |
| `swaylock/config` | Rubik font, clock, dark lock/indicator palette, daemonization and ignored empty password input. | No corresponding current installer copy rule. The Nix idle config invokes native swaylock, but does not copy this config. Several commented effect options imply a particular implementation may be needed; exact compatibility was not verified. |
| `emacs/material-theme.el` | Emacs `material` theme reads `~/.local/state/quickshell/user/generated/material_colors.scss`, extracts six-digit SCSS colors, defines faces, configures Org display, and adds its own directory to theme search path. | No current installer reference. Loading the file makes the theme available (`provide-theme`); exact generated-color file availability and automatic refresh behavior are unverified. See [theming](dotfiles-and-theming.md) before relying on this historical generated path. |

To integrate a new extra, add an explicit install rule/option and define overwrite/preservation behavior; merely adding a directory here does not install it. See the [new installed file recipe](setup-and-install.md#add-an-installed-file). Existing manual extras provide configuration examples, not proof that their dependencies or runtime hooks are installed.

## Licensing and vendored code

`licenses/README.md:3` says borrowed code files should include a license notice and a license copy should be stored in this directory. Current copies are `LGPL-3.0.txt` and `MIT.txt`; the MIT text contains placeholder copyright fields. This folder is a license-text collection, not a reliable per-file ownership map. Inspect the source notice of copied code and the top-level project license when deciding terms.

The shapes widget dependency is a Git submodule rather than an ordinary copied directory (`.gitmodules:1`):

- Path: `dots/.config/quickshell/ii/modules/common/widgets/shapes`.
- URL: `https://github.com/end-4/rounded-polygon-qmljs.git`.
- The superproject records a specific submodule revision. `sdata/lib/functions.sh:339` initializes/updates recursively when needed during file install; `diagnose:69` reports recursive status.

When changing the submodule revision, review upstream source/license and record the intended gitlink change. Avoid accidentally committing an uninitialized/dirty submodule state as if it were normal source content. The [Quickshell architecture](quickshell/architecture.md) doc covers how the widgets use it.

## Ignore rules and generated state

Current `.gitignore` is intentionally short:

| Pattern | Reason visible from source |
| --- | --- |
| `/diagnose.result` | Local support report created by `diagnose` |
| `/cache` | Installer build/download/cache workspace |
| `__pycache__/`, `*.py[cod]` | Python interpreter caches |
| `/dots/.config/quickshell/ii/.qmlls.ini` | Developer LSP marker described in contribution guide |
| `/.update-lock` | Experimental updater PID lock |
| `/os-release` | Local distro-detection override |
| `*~` | Emacs backup files |

It does **not** ignore `.update-backups/`, `.exp-merge-backups/`, Fedora `user_data.yaml`, local PKGBUILD build products, or arbitrary personal files. Those may appear in status after running scripts; inspect before staging. Nix activation temporarily stages/removes `username.nix`, which can be left behind by interruption (`sdata/dist-nix/install-deps.sh:50`). Do not add broad ignore rules that hide actual dependency inputs/locks: `sdata/uv/requirements.txt` and the Nix `flake.lock` are tracked reproducibility inputs.

## Commit messages observed in history

The repository does not impose one message schema in `.github/CONTRIBUTING.md` or workflows. `git log` at the documented head shows several styles:

| Commit | Observed subject / pattern |
| --- | --- |
| `2f2a376f` | `gentoo: quickshell update + small change (#3687)` |
| `c4f0582c` | `gentoo: update useflags (#3667)` |
| `33f31a08` | `hypr: don't blur behind the wallpaper layer (#3672)` |
| `8d80d0a6` | `qs: make OS name parsing more robust (#3666)` |
| `7d3e85d3` | `fix(hyprland): ignore app maximize requests globally (#3671)` |
| `42d0aae1` | `feat(install): add dinit init system support (#3584)` |
| `107dfd89` | `openrc: duplicate i2c-dev fix` |
| `e29f9dcd` | `bump qs version` |
| `e3ea5807` | `Merge branch 'end-4:main' into main` |

Use a concise subsystem prefix when it helps (`gentoo:`, `hypr:`, `qs:`, etc.) and state the actual change. Conventional Commit forms appear but are not universal. `(#N)` suffixes are observed in merged PR subjects, not a requirement to invent issue/PR numbers. Keep platform changes scoped and describe the real resulting behavior; a package pin update should identify the component affected.
