# Changelog

## 1.6.0 — 2026-09-01

- Kept the Omarchy screensaver fullscreen while Floating Mode is active
- Added a persistent tiled-mode switch for resizing windows by dragging their borders
- Added a persistent switch for applying Floating Mode globally or only to the current workspace
- Hid Floating Mode titlebars on tiled windows outside the selected workspace
- Saved focus-border and window-transparency preferences separately for every workspace when current-workspace scope is selected
- Allowed multiple workspaces to remain in Floating Mode independently
- Limited focus-border and opacity overrides to managed floating windows so tiled workspaces always keep their normal focus border and transparency
- Made the All workspaces switch copy the current workspace's tiled/floating state and visual preferences to every workspace
- Kept the All workspaces switch selectable while Floating Mode synchronization is active
- Adopted already-floating windows into workspace management so the focus-border switch affects every Floating Mode window
- Batched window geometry, focus, transparency, and tiling IPC updates to make mode switching substantially faster
- Captured the target workspace before waiting for the operation lock so delayed actions cannot affect a different workspace
- Changed background synchronization to non-blocking lock acquisition so it cannot queue ahead of user actions
- Restored tiled focus borders with Omarchy's configured active color instead of an unreliable `unset` window property
- Added creation-time Hyprland rules per enabled workspace so newly opened windows enter Floating Mode immediately instead of relying on polling
- Applied each workspace's focus-border preference at window creation so new floating windows never flash or retain the active border when it is disabled
- Applied each workspace's window-transparency preference at creation so newly opened floating windows immediately use the selected opacity
- Made titlebar transparency global so changing it on any workspace updates every workspace
- Restored Omarchy's original window transparency when leaving Floating Mode by disabling opacity rules before clearing per-window overrides
- Replaced ten polling helper processes with one atomic UI status snapshot and kept read-only status checks out of the operation lock
- Limited individual-workspace mode transitions and preference refreshes to the selected workspace instead of resynchronizing every enabled workspace
- Split opacity handling cleanly between creation-time rules for new windows and immediate per-window updates for already-open windows, with overrides cleared on return to Tiling
- Reduced the background repair loop frequency because creation-time rules now handle normal window mapping immediately
- Restored the exact stock Omarchy opacity profile for each window when leaving Floating Mode instead of leaving the last numeric value at 1.0

All notable changes to Floating Mode are documented here.

## 1.5.0 — 2026-08-31

- Add a persistent switch for enabling or disabling native titlebar transparency
- Enable directional mouse resizing: sides affect only their matching axis, corners affect both axes, with matching cursors and an extended border grab area

## 1.4.0 — 2026-08-29

- Open newly mapped windows directly at their centered floating size instead of briefly showing a full-work-area tiled frame
- Prevent Omarchy's Chromium browser tag from re-tiling Chromium-based browsers while Floating Mode is active
- Cascade newly opened floating windows by 28 pixels so overlapping windows remain visible
- Add a persistent transparency switch that can make active and inactive Floating Mode windows fully opaque

## 1.3.1 — 2026-08-29

- Restored the permanent marketplace plugin ID `io.github.rawritude.floating-mode` for update compatibility

## 1.3.0 — 2026-08-29

- Opened, validated, locked, read, and wrote mutable state through the same no-follow, nonblocking file descriptors
- Corrected half-height geometry when snapping directly from fullscreen or maximized state
- Added a persistent Gaps switch for drag and keyboard snapping, enabled by default; disabling it removes both inner and outer gaps

## 1.2.0 — 2026-08-28

- Added Floating Mode-only keyboard snapping: Ctrl+Super+Left/Right selects the corresponding half and Ctrl+Super+Up maximizes the focused window
- Added Ctrl+Super+Down to restore the focused window's original position and size, even after switching repeatedly between keyboard snap positions
- Resolved every keyboard action through Hyprland's current focus state and registered each binding only while Floating Mode is active

## 1.1.1 — 2026-08-28

- Preserved the configured left/right snap mode when detaching and continuing to drag an already snapped window
- Prevented quarter zones from reappearing during a drag when that side is configured for an always-full-height half

## 1.1.0 — 2026-08-28

- Localized the complete bar tooltip and settings menu automatically from the desktop locale: German for `de*`, English otherwise
- Added independent left- and right-edge snap choices for quarter zones or an always-full-height half
- Made snap-side preferences persistent across shell, Hyprland, and login restarts
- Added geometry coverage for all four independently configurable corner zones

## 1.0.15 — 2026-08-28

- Added a right-click settings menu to the Floating Mode bar icon
- Added a persistent Fokusrahmen switch for keeping the configured focus color or matching the inactive window border while Floating Mode is active
- Restored the configured focus border automatically when Floating Mode is disabled

## 1.0.12 — 2026-08-22

- Changed the displayed plugin author from `rawritude` to `Norbert Winter`

## 1.0.11 — 2026-08-22

- Registered every private helper buffer for process-exit cleanup immediately after creation
- Prevented malformed, oversized, or later-stage failures from retaining runtime temp files
- Verified 50 repeated failed sync attempts retain zero managed-ledger snapshots

## 1.0.10 — 2026-08-22

- Read the managed-window ledger once into a private buffer capped at 8 KiB plus one detection byte
- Validate and consume the same snapshot bytes for pruning, convergence checks, appends, and disable transitions
- Removed check-then-reopen structured reads of the mutable ledger path

## 1.0.9 — 2026-08-22

- Pruned closed window addresses from the managed ledger on every synchronization
- Capped the ledger at 8 KiB and 256 unique valid Hyprland addresses
- Atomically replaced the ledger before adding newly managed live windows
- Validated ledger size, count, format, ownership, type, links, and permissions before every structured read

## 1.0.8 — 2026-08-22

- Made bar clicks use the helper's atomic `toggle` operation instead of stale asynchronously polled UI state
- Cancelled pre-action status polls and forced a fresh status read after each transition
- Serialized UI actions and background synchronization with a private runtime lock

## 1.0.7 — 2026-08-22

- Bounded recurring Hyprland client IPC to 1 MiB and 256 objects
- Bounded monitor IPC to 256 KiB and 64 objects
- Rejected truncated, invalid, non-array, and excessive IPC responses before shell-variable allocation
- Reduced the synchronization polling rate from 700 ms to 1 second

## 1.0.6 — 2026-08-22

- Made the reviewed 40-character hyprland-plugins commit literal at every fetch, checkout, verification, and registration site so automated validation can prove the source pin

## 1.0.5 — 2026-08-22

- Removed the shared `/tmp` fallback for runtime state
- Required private, user-owned runtime and state directories
- Rejected symlinked, non-regular, wrong-owner, and hard-linked state files
- Restricted runtime state files to mode 0600

## 1.0.4 — 2026-08-21

- Restored circular hover backgrounds while keeping controls visible
- Pinned the patched hyprbars build to reviewed upstream commit `7644cecdb947060682891a0db2a0cdc5c0b9e704`
- Verifies the detached source checkout before compiling

## 1.0.3 — 2026-08-21

- Kept maximize and close controls permanently visible

## 1.0.2 — 2026-08-21

- Enabled hyprbars' official `icon_on_hover` button effect

## 1.0.1 — 2026-08-21

- Removed the custom native hyprbars patch and privileged binary replacement
- Delegated installation of the unmodified ABI-pinned hyprbars plugin to hyprpm
- Switched titlebar controls to hyprbars' standard `add_button` interface only
- Removed the custom hover-background options

## 1.0.0 — 2026-08-21

- Added an Omarchy bar toggle for tiled and floating modes
- Added automatic handling of windows opened while Floating Mode is active
- Added scale-aware, centered geometry for lone and newly opened windows
- Preserved tiled placement when converting populated workspaces
- Added instant animation-free window transitions
- Added native draggable titlebars through the official Hyprland `hyprbars` plugin
- Added maximize and close controls with a red circular close-hover state
- Added reversible fullscreen cleanup when returning to tiling
- Added multi-monitor, transformed-monitor, and reserved-area support
- Added a dependency-checking installer with ABI-pinned builds and safe restoration
