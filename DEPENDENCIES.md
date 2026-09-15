# Dependency audit

Floating Mode has no vendored libraries, package-manager install hooks, or telemetry. Window management works locally; first-start setup and native ABI rebuilds require network access.

## Runtime dependencies

| Dependency | Purpose | Expected source |
| --- | --- | --- |
| Omarchy 4 / Omarchy Shell | Loads the service and bar widget | Standard Omarchy installation |
| Hyprland 0.56+ | Window state, geometry, dispatchers, and native plugin ABI | Standard Omarchy installation |
| Quickshell Qt/QML imports | Hosts `BarWidget.qml` and `Service.qml` | Omarchy Shell |
| `hyprctl` | Reads clients and monitors; applies window transitions | Hyprland package |
| `jq` | Safely calculates logical monitor and window geometry | Omarchy base packages |
| `flock` (util-linux) | Detects an active setup runner to prevent duplicate setup terminals | Standard Omarchy installation |
| `omarchy launch terminal` | Opens the one-time interactive setup when needed | Standard Omarchy installation |
| `perl` | Opens and validates state-file descriptors without following links or blocking on special files | Arch Linux base packages |

Window operation is local and uses the current user's permissions. On activation, missing native setup automatically opens the existing installer in a terminal; that setup can access GitHub and request sudo as described below. Persistent attempt and lock files live in `$XDG_STATE_HOME/omarchy-floating-mode/setup/`.

## Native setup installer dependencies

| Dependency | Purpose |
| --- | --- |
| `hyprpm` | Registers the pinned official plugins repository and manages native plugin loading |
| `git` | Clones that exact official source commit and applies the bundled patch |
| `make`, `gcc`, `g++`, `pkg-config` | Builds `hyprbars.so`, the bundled Aero snap module, and its geometry tests |
| `cmake`, `cpio` | Required by `hyprpm` for headers and plugin management |
| `sudo` | Runs the bundled descriptor-based installer that replaces or restores only the cached `hyprbars.so` and repairs narrowly scoped root-owned HyprPM account-cache metadata |
| `sed`, `grep`, `awk`, `sha256sum`, `cut`, `mktemp` | Installer validation, module naming, metadata parsing, and temporary workspace handling |

The installer verifies these commands before beginning. It needs network access only for the pinned clone of `https://github.com/hyprwm/hyprland-plugins` (and initial HyprPM registration when hyprbars is absent). A user-owned Omarchy `post-update` hook compares the installed Hyprland ABI hash with the last successful build and invokes the same installer only after an ABI change.

## Files and privileges

Normal user writes:

- `~/.config/hypr/floating-mode.lua`
- One exact `require("hypr.floating-mode")` line in `~/.config/hypr/hyprland.lua`
- `~/.config/omarchy-floating-mode/` for persistent focus-border, transparency, and per-side snap preferences
- `$XDG_DATA_HOME/omarchy-floating-mode/omarchy-windows-snap-<binary-hash>.so`
- `$XDG_STATE_HOME/omarchy-floating-mode/` for the original module and previous enabled state
- `$XDG_RUNTIME_DIR/omarchy-floating-mode/` for session-only window state

Privileged write:

- `/var/cache/hyprpm/<account-from-real-uid>/hyprland-plugins/hyprbars.so`

Additional normal user writes:

- `~/.config/omarchy/hooks/post-update.d/io.github.rawritude.floating-mode`
- `$XDG_STATE_HOME/omarchy-floating-mode/native-abi`

The privileged installer resolves the account from the caller's real UID,
opens every fixed path component with no-follow directory descriptors, checks
ownership and write modes, and atomically replaces the module through the
verified destination descriptor.

The content-addressed snap filename lets Hyprland unload an old build before the installer removes it, avoiding in-place replacement of a loaded shared object. The original cached hyprbars module is saved before replacement. If HyprPM recreated the fixed account cache as root, the privileged helper accepts only root or the real account as owner, rejects links and writable directory components, then repairs ownership only for the account directory, plugin directory, and their exact regular `state.toml` files. `--uninstall` restores the original module and enabled state, removes the snap module, Lua integration, update hook, and ABI state, then reloads Hyprland.

## External code

- Official upstream: [hyprwm/hyprland-plugins](https://github.com/hyprwm/hyprland-plugins)
- Modified component: `hyprbars` only
- Local modifications: [`patches/hyprbars-button-hover.patch`](patches/hyprbars-button-hover.patch) and [`patches/hyprbars-disabled-input.patch`](patches/hyprbars-disabled-input.patch)
- Patch purposes: configurable button hover backgrounds and rejecting input while disabled ([hyprland-plugins#701](https://github.com/hyprwm/hyprland-plugins/pull/701))
- Bundled original component: [`contrib/aero-snap`](contrib/aero-snap), licensed under this repository's MIT license
- Snap implementation: Hyprland drag events, work-area geometry, and render-pass previews

The upstream source is not vendored in this repository. Both hyprpm registration and the patched build use the fixed reviewed commit `7644cecdb947060682891a0db2a0cdc5c0b9e704`; the installer verifies the detached checkout before compiling.
