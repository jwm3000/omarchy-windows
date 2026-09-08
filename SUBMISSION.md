### Repository URL

https://github.com/jwm3000/omarchy-windows

### Category

Desktop

### Tags

bar, hyprland, quickshell

### Suggest a missing tag

_No response_

### Maintainer notes

Floating Mode adds an instant tiled-to-floating workflow for large and ultrawide monitors. It preserves useful window placement, centers lone and newly opened applications with comfortable margins, supports directional border resizing and Aero-style snapping, and restores only windows it managed. Runtime compositor and QML helpers are supervised with deadlines, live output limits, and process-group cleanup. Its explicit one-time installer builds the official hyprbars source commit `7644cecdb947060682891a0db2a0cdc5c0b9e704`, applies two reviewable patches, and replaces the cached module through a real-UID-derived, ownership-checked, no-follow descriptor chain. A user-owned Omarchy post-update hook compares the installed Hyprland ABI with the last successful native build and invokes that same installer only after an ABI change. The descriptor-based helper safely recovers the fixed account cache and its exact state files if HyprPM recreated them as root. The native titlebar renders only on Floating Mode-managed windows.

### Submission checklist
- [x] The GitHub repository is public.
- [x] Installation, updating, recovery, and removal are documented.
- [x] `omarchy plugin validate` succeeds on Omarchy 4.
- [x] Both QML entry points pass `qmllint` against the installed Omarchy shell.
- [x] Shell scripts pass `bash -n`.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
