# Dependency audit

Floating Mode has no vendored libraries, package-manager install hooks, telemetry, or runtime network dependency.

## Runtime dependencies

| Dependency | Purpose | Expected source |
| --- | --- | --- |
| Omarchy 4 / Omarchy Shell | Loads the service and bar widget | Standard Omarchy installation |
| Hyprland 0.56+ | Window state, geometry, dispatchers, and native plugin ABI | Standard Omarchy installation |
| Quickshell Qt/QML imports | Hosts `BarWidget.qml` and `Service.qml` | Omarchy Shell |
| `hyprctl` | Reads clients and monitors; applies window transitions | Hyprland package |
| `jq` | Safely calculates logical monitor and window geometry | Omarchy base packages |

Runtime operation is local and uses the current user's permissions.

## Explicit one-time installer dependencies

| Dependency | Purpose |
| --- | --- |
| `hyprpm` | Selects the official `hyprbars` commit compatible with the installed Hyprland ABI |
| `git` | Clones that exact official source commit and applies the bundled patch |
| `make`, `gcc`, `g++`, `pkg-config` | Builds `hyprbars.so`, the bundled Aero snap module, and its geometry tests |
| `cmake`, `cpio` | Required by `hyprpm` for headers and plugin management |
| `sudo`, `install` | Replaces and restores only the cached `hyprbars.so` |
| `sed`, `grep`, `awk`, `sha256sum`, `cut`, `mktemp` | Installer validation, module naming, metadata parsing, and temporary workspace handling |

The installer verifies these commands before beginning. It needs network access only for `hyprpm update` and the clone of `https://github.com/hyprwm/hyprland-plugins`.

## Files and privileges

Normal user writes:

- `~/.config/hypr/floating-mode.lua`
- One exact `require("hypr.floating-mode")` line in `~/.config/hypr/hyprland.lua`
- `$XDG_DATA_HOME/omarchy-floating-mode/omarchy-windows-snap-<binary-hash>.so`
- `$XDG_STATE_HOME/omarchy-floating-mode/` for the original module and previous enabled state
- `$XDG_RUNTIME_DIR/omarchy-floating-mode/` for session-only window state

Privileged write:

- `/var/cache/hyprpm/$USER/hyprland-plugins/hyprbars.so`

The content-addressed snap filename lets Hyprland unload an old build before the installer removes it, avoiding in-place replacement of a loaded shared object. The original cached hyprbars module is saved before replacement. `--uninstall` restores it and its previous enabled state, removes the snap module and Lua integration, reloads Hyprland, and deletes the installer state.

## External code

- Official upstream: [hyprwm/hyprland-plugins](https://github.com/hyprwm/hyprland-plugins)
- Modified component: `hyprbars` only
- Local modifications: [`patches/hyprbars-button-hover.patch`](patches/hyprbars-button-hover.patch) and [`patches/hyprbars-disabled-input.patch`](patches/hyprbars-disabled-input.patch)
- Patch purposes: configurable button hover backgrounds and rejecting input while disabled ([hyprland-plugins#701](https://github.com/hyprwm/hyprland-plugins/pull/701))
- Bundled original component: [`contrib/aero-snap`](contrib/aero-snap), licensed under this repository's MIT license
- Snap implementation: Hyprland drag events, work-area geometry, and render-pass previews

The upstream source is not vendored in this repository. Both hyprpm registration and the patched build use the fixed reviewed commit `7644cecdb947060682891a0db2a0cdc5c0b9e704`; the installer verifies the detached checkout before compiling.
